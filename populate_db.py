import scrobbler
from models import Album, Artist, Scrobble, Track


def simplify_db_result(db_result):
    # the tracks come back as a list of sqlalchemy result objects which are basically tuples of length 1
    # the spotify api package can't handle this so we need to parse into a tuple of strings
    # we use a list comprehension to grab the first element from each tuple and put it in a list
    return [i[0] for i in db_result]

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


class Populator(scrobbler.Scrobbler):
    def get_new_tracks(self):
        # get the unique list of tracks that are scrobbled but not already in the tracks table
        tracks = simplify_db_result(
            self.db.query(Scrobble.spotify_id).distinct().filter(~Scrobble.spotify_id.in_(
                self.db.query(Track.spotify_id).distinct())
            ).all()
        )

        # don't want any None's so remove them if they are in there
        if None in tracks:
            tracks.remove(None)

        return tracks

    def get_new_artists(self, tracks):
        new_track_artists = {track['artists'][0]['id'] for track in tracks}

        existing_artist_ids = simplify_db_result(
            self.db.query(Artist.spotify_id).distinct()
        )

        new_artist_ids = [
            id for id in new_track_artists if id not in existing_artist_ids]

        # don't want any None's so remove them if they are in there
        if None in new_artist_ids:
            new_artist_ids.remove(None)

        return new_artist_ids


    def get_new_albums(self, tracks):
        new_track_albums = {track['album']['id'] for track in tracks}

        existing_album_ids = simplify_db_result(
            self.db.query(Album.spotify_id).distinct()
        )

        new_album_ids = [
            id for id in new_track_albums if id not in existing_album_ids]

        # don't want any None's so remove them if they are in there
        if None in new_album_ids:
            new_album_ids.remove(None)

        return new_album_ids


def main(populator: Populator):
    new_tracks = populator.get_new_tracks()

    if len(new_tracks) == 0:
        print("No new tracks, exiting.")
        return

    print(f'Found {len(new_tracks)} new tracks.')

    print("Fetching track data.")
    track_data = dechunk(
        # iterate over that list of chunks, hitting the spotify api for the track data in each chunk
        [populator.sp.tracks(chunk) for chunk in chunk(new_tracks)]
    )

    print("Fetching tracks feature data.")
    track_feature_data = dechunk(
        # iterate over that list of chunks, hitting the spotify api for the track feature data in each chunk
        [populator.sp.audio_features(chunk) for chunk in chunk(new_tracks, 100)]
    )

    print("Inserting new tracks into database.")
    for data, features in zip(track_data, track_feature_data):
        populator.add_track(track_data=data, track_features=features)

    populator.db.commit()

    new_artist_ids = populator.get_new_artists(track_data)

    print(f'Found {len(new_artist_ids)} new artists.')

    if len(new_artist_ids) > 0:
        print("Fetching artist data.")
        artist_data = dechunk(
            [populator.sp.artists(artist_chunk)
             for artist_chunk in chunk(new_artist_ids)]
        )

        print("Inserting new artists into database.")
        for artist in artist_data:
            populator.add_artist(artist_data=artist)

        populator.db.commit()

    new_album_ids = populator.get_new_albums(track_data)

    print(f'Found {len(new_album_ids)} new albums.')

    if len(new_album_ids) > 0:
        print("Fetching album data.")
        album_data = dechunk(
            [populator.sp.albums(album_chunk)
             for album_chunk in chunk(new_album_ids, 20)]
        )

        print("Inserting new albums into database.")
        for album in album_data:
            populator.add_album(album_data=album)

        populator.db.commit()

    print("All done!")

    return


if __name__ == '__main__':
    populator = Populator('settings.yaml')

    main(populator)
