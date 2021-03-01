from sqlalchemy import and_, create_engine
from sqlalchemy.orm import sessionmaker
from models import Album, Artist, Scrobble, Track
from helpers import get_db_path, get_spotify_api_keys, get_spotify_api
from database_stuff import add_track, add_artist, add_album

key_file = "api_keys.yaml"

client_secret, client_id = get_spotify_api_keys(key_file)

sp = get_spotify_api(client_secret, client_id)

db_path = get_db_path(key_file)

engine = create_engine(f"sqlite:///{db_path}")
Session = sessionmaker()
Session.configure(bind=engine)
session = Session()


def simplify_db_result(db_result):
    # the tracks come back as a list of sqlalchemy result objects which are basically tuples of length 1
    # the spotify api package can't handle this so we need to parse into a tuple of strings
    # first we unpack the list of result objects using *track
    # then we use zip to grab the first element in each result object
    # then we convert the resulting zip object into a list that contains one tuple with all the track id's
    # then we just grab that tuple, ie. the first element in the list
    return tuple(zip(*db_result))[0]


def chunk(long_list, chunk_size=50):
    # break the tuple of tracks into a list of tuples of length 50 b/c that's the limit for one api request
    return [long_list[i: i+chunk_size] for i in range(0, len(long_list), chunk_size)]


def dechunk(chunks):
    # that comes back as a list of dicts and within each dict is the tracks key that has a list of dicts of track data
    # so we loop over each chunk, and then within each chunk we loop over the list of track data dicts in each chunk's tracks key, pulling out the individual track data dicts and putting each of those track data dicts into a list
    if isinstance(chunks[0], list) == 1:
        return [item for chunk in chunks for item in chunk]

    else:
        key = list(chunks[0].keys())[0]
        return [item for chunk in chunks for item in chunk[key]]


def populate_db(session, sp):
    # get the unique list of tracks that are scrobbled but not already in the tracks table
    tracks = simplify_db_result(
        session.query(Scrobble.spotify_id).distinct().filter(~Scrobble.spotify_id.in_(
            session.query(Track.spotify_id).distinct())
        ).all()
    )
    
    
    track_data = dechunk(
        # iterate over that list of chunks, hitting the spotify api for the track data in each chunk
        [sp.tracks(chunk) for chunk in chunk(tracks)]
    )

    track_feature_data = dechunk(
        # iterate over that list of chunks, hitting the spotify api for the track feature data in each chunk
        [sp.audio_features(chunk) for chunk in chunk(tracks, 100)]
    )

    for track_data, track_features in zip(track_data, track_feature_data):
        add_track(session, sp, track_data=track_data, track_features=track_features)
    
    session.commit()

    artist_ids = { track['artists'][0]['id'] for track in track_data }

    existing_artist_ids = simplify_db_result(
        session.query(Artist.spotify_id).distinct()
    )

    new_artist_ids = [ id for id in artist_ids if id not in existing_artist_ids ]

    artist_data = dechunk(
        [ sp.artists(artist_chunk) for artist_chunk in chunk(new_artist_ids) ]
    )
    
    for artist in artist_data:
        add_artist(session, sp, artist_data=artist)

    session.commit()

    album_ids = {track['album']['id'] for track in track_data}

    existing_album_ids = simplify_db_result(
        session.query(Album.spotify_id).distinct()
    )

    new_album_ids = [id for id in album_ids if id not in existing_album_ids]

    album_data = dechunk(
        [sp.albums(album_chunk) for album_chunk in chunk(new_album_ids, 20)]
    )

    for album in album_data:
        add_album(session, sp, album_id=None, album_data=album)
    
    session.commit()

    return


if __name__ == '__main__':
    populate_db()
