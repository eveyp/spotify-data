from sqlalchemy import and_, create_engine
from sqlalchemy.orm import sessionmaker
from models import Album, Artist, Scrobble, Track
from helpers import get_db_path, get_spotify_api_keys, get_spotify_api

key_file = "api_keys.yaml"

client_secret, client_id = get_spotify_api_keys(key_file)

sp = get_spotify_api(client_secret, client_id)

db_path = get_db_path(key_file)

engine = create_engine(f"sqlite:///{db_path}")
Session = sessionmaker()
Session.configure(bind=engine)
session = Session()


scrobble_data = sp.current_user_recently_played()

def add_scrobble(session, timestamp, track_id, track_name):
    scrobble = Scrobble(
        timestamp = timestamp,
        spotify_id = track_id,
        track_name = track_name
    )

    session.add(scrobble)

    return

def add_artist(session, sp, artist_id=None, artist_data=None):
    if artist_data is None:
        artist_data = sp.artist(artist_id)

    if artist_id is None:
        artist_id = artist_data['id']
    
    try:
        image_url = artist_data['images'][0]['url']
    except IndexError:
        image_url = None

    artist = Artist(
        spotify_id=artist_id,
        name=artist_data['name'],
        popularity=artist_data['popularity'],
        image_url=image_url,
        # genres = artist_data['genres']
    )

    session.add(artist)

    return


def add_album(session, sp, album_id=None, album_data=None):
    if album_data is None:
        album_data = sp.album(album_id)

    if album_id is None:
        album_id = album_data['id']

    try:
        cover_url = album_data['images'][0]['url']
    except IndexError:
        cover_url=None
        
    album = Album(
        spotify_id=album_id,
        name=album_data['name'],
        lead_artist_id=album_data['artists'][0]['id'],
        cover_url=cover_url,
        label=album_data['label'],
        popularity=album_data['popularity'],
        release_date=album_data['release_date'],
        type=album_data['type']
    )
    
    session.add(album)
    
    return


def add_track(session, sp, track_id=None, track_data=None, track_features=None):
    if track_data is None:
        track_data = sp.track(track_id)
    
    if track_features is None:
        track_features = sp.audio_features(track_id)[0]
    
    if track_id is None:
        track_id = track_data['id']

    track = Track(
        spotify_id=track_id,
        lead_artist_id=track_data['artists'][0]['id'],
        album_id=track_data['album']['id'],
        name=track_data['name'],
        length_ms=track_data['duration_ms'],
        explicit=track_data['explicit'],
        popularity=track_data['popularity'],
        track_number=track_data['track_number'],
        acousticness=track_features['acousticness'],
        danceability=track_features['danceability'],
        energy=track_features['energy'],
        instrumentalness=track_features['instrumentalness'],
        key=track_features['key'],
        liveness=track_features['liveness'],
        mode=track_features['mode'],
        speechiness=track_features['speechiness'],
        tempo=track_features['tempo'],
        valence=track_features['valence'],
        time_signature=track_features['time_signature']
    )

    session.add(track)

    return

def process_scrobble(session, scrobble_data):
    # parse the timestamp from the scrobble data
    timestamp = scrobble_data['played_at']

    # check if a scrobble with that timestamp already exists
    scrobble = (
        session.query(Scrobble)
        .filter(Scrobble.timestamp == timestamp)
        .one_or_none()
    )
    
    # if the scrobble does exist we don't have to do anything and just return
    if scrobble is not None:
        return

    # otherwise, parse the track id from the scrobble data
    track_id = scrobble_data['track']['id']
    
    # check if the track exists
    track = (
        session.query(Track)
        .filter(Track.spotify_id == track_id)
        .one_or_none()
    )

    # if the track exists, we know that we have the artist and album, so just add the scrobble and return
    if track is not None:
        track_name = scrobble_data['track']['name']
        
        add_scrobble(timestamp, track_id, track_name)

        session.commit()

        return

    # otherwise parse the artist_id from the scrobble data
    artist_id = scrobble_data['track']['artists'][0]['id']

    # check if the artist exists
    artist = (
        session.query(Artist)
        .filter(Artist.spotify_id == artist_id)
        .one_or_none()
    )

    # if the artist doesn't exist, add them
    if artist is None:
        add_artist(session, sp, artist_id)
    
    # parse the album id from the scrobble data
    album_id = scrobble_data['track']['album']['id']

    # check if the album exists
    album = (
        session.query(Album)
        .filter(Album.spotify_id == album_id)
        .one_or_none()
    )

    # if the album doesn't exist, add it
    if album is None:
        add_album(session, sp, album_id)
    
    # add the track
    add_track(session, sp, track_id)

    # add the scrobble
    add_scrobble(session, timestamp, scrobble_data['track']['id'], scrobble_data['track']['name'])

    # commit the db changes and return
    session.commit()

    return



    
