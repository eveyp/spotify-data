import argparse
import inflect
from helpers import get_db_session, get_spotify_api
from models import Album, Artist, Scrobble, Track, Genre


def create_genre(genre_name):
    genre = Genre(
        name=genre_name
    )

    return genre

class Scrobbler():
    def __init__(self, settings_file):
        self.db = get_db_session(settings_file=settings_file)

        self.sp = get_spotify_api(settings_file=settings_file)

        return

    def add_album(self, album_id=None, album_data=None):
        if album_id is None and album_data is None:
            raise Exception

        if album_data is None:
            album_data = self.sp.album(album_id)

        if album_id is None:
            album_id = album_data['id']

        try:
            cover_url = album_data['images'][0]['url']
        except IndexError:
            cover_url = None
        
        # initialize the album object
        album = Album(
            spotify_id=album_id,
            name=album_data['name'],
            lead_artist_id=album_data['artists'][0]['id'],
            cover_url=cover_url,
            label=album_data.get('label'),
            popularity=album_data.get('popularity'),
            release_date=album_data.get('release_date'),
            type=album_data.get('type')
        )

        # gather list of artist's genre objects or empty list if no genres
        genres = self.process_genres(album_data.get('genres'))

        # add the genres to the album object
        album.genres = genres        

        # add the album to the database
        self.db.add(album)

        return
    
    def process_genres(self, genres):
        if genres is not None:
            return [self.get_genre(genre) for genre in genres]
        else:
            return []            
    
    def get_genre(self, genre_name):
        genre = self.db.query(Genre).filter(Genre.name == genre_name).one_or_none()

        if genre is None:
            genre = create_genre(genre_name)
        
        return genre    


    def add_artist(self, artist_id=None, artist_data=None):
        if artist_id is None and artist_data is None:
            raise Exception

        if artist_data is None:
            artist_data = self.sp.artist(artist_id)

        if artist_id is None:
            artist_id = artist_data['id']

        try:
            image_url = artist_data['images'][0]['url']
        except IndexError:
            image_url = None

        # initialize the artist object
        artist = Artist(
            spotify_id=artist_id,
            name=artist_data['name'],
            popularity=artist_data.get('popularity'),
            image_url=image_url
        )

        # gather list of artist's genre objects or empty list if no genres
        genres = self.process_genres(artist_data.get('genres'))

        # add the genres to the artist object
        artist.genres = genres

        # add the artist to the database
        self.db.add(artist)
        
        return

    def add_track(self, track_id=None, track_data=None, track_features=None):
        if track_id is None and (track_data is None or track_features is None):
            raise Exception

        if track_data is None:
            track_data = self.sp.track(track_id)

        if track_features is None:
            track_features = self.sp.audio_features(track_id)[0]

        if track_id is None:
            track_id = track_data['id']

        track = Track(
            spotify_id=track_id,
            lead_artist_id=track_data['artists'][0]['id'],
            album_id=track_data['album']['id'],
            name=track_data['name'],
            length_ms=track_data.get('duration_ms'),
            explicit=track_data.get('explicit'),
            popularity=track_data.get('popularity'),
            track_number=track_data.get('track_number'),
            acousticness=track_features.get('acousticness'),
            danceability=track_features.get('danceability'),
            energy=track_features.get('energy'),
            instrumentalness=track_features.get('instrumentalness'),
            key=track_features.get('key'),
            liveness=track_features.get('liveness'),
            mode=track_features.get('mode'),
            speechiness=track_features.get('speechiness'),
            tempo=track_features.get('tempo'),
            valence=track_features.get('valence'),
            time_signature=track_features.get('time_signature')
        )

        self.db.add(track)

        return

    def get_latest_timestamp(self):
        return self.db.query(Scrobble.timestamp).order_by(Scrobble.timestamp.desc()).first()

    def parse_play(self, play_data):
        return {
            'track_id': play_data['track']['id'],
            'timestamp': play_data['played_at'],
            'track_name': play_data['track']['name'],
            'lead_artist_id': play_data['track']['artists'][0]['id'],
            'album_id': play_data['track']['album']['id']
        }

    def get_new_plays(self):
        latest_timestamp = self.get_latest_timestamp()

        result = self.sp.current_user_recently_played(after=latest_timestamp)

        raw_plays = result.get('items')

        if raw_plays is not None:
            return [self.parse_play(play) for play in raw_plays]
        else:
            return None

    def add_scrobble(self, play_data):
        scrobble = Scrobble(
            timestamp=play_data['timestamp'],
            spotify_id=play_data['track_id'],
            track_name=play_data.get('track_name')
        )

        self.db.add(scrobble)

        return

    def process_scrobble(self, play_data):
        # check if a scrobble with that timestamp already exists
        scrobble = (
            self.db.query(Scrobble)
            .filter(Scrobble.timestamp == play_data['timestamp'])
            .one_or_none()
        )

        # if the scrobble does exist we don't have to do anything and just return
        if scrobble is not None:
            return

        # check if the track exists
        track = (
            self.db.query(Track)
            .filter(Track.spotify_id == play_data['track_id'])
            .one_or_none()
        )

        # if the track exists, we know that we have the artist and album, so just add the scrobble and return
        if track is not None:
            self.add_scrobble(play_data)

            self.db.commit()

            return

        # check if the artist exists
        artist = (
            self.db.query(Artist)
            .filter(Artist.spotify_id == play_data['lead_artist_id'])
            .one_or_none()
        )

        # if the artist doesn't exist, add them
        if artist is None:
            self.add_artist(artist_id=play_data['lead_artist_id'])

        # check if the album exists
        album = (
            self.db.query(Album)
            .filter(Album.spotify_id == play_data['album_id']).
            one_or_none()
        )

        # if the album doesn't exist, add it
        if album is None:
            self.add_album(album_id=play_data['album_id'])

        # add the track
        self.add_track(track_id=play_data['track_id'])

        # add the scrobble
        self.add_scrobble(play_data)

        self.db.commit()

        return


def main():
    parser = argparse.ArgumentParser(description="spotify scrobbler")
    parser.add_argument('-s', '--settings_file',
                        metavar='SETTINGS_FILE',
                        type=str,
                        help="the settings file in yaml format with database location and spotify credentials",
                        default="settings.yaml"
                        )
    args = parser.parse_args()

    p = inflect.engine()

    sc = Scrobbler(args.settings_file)

    new_plays = sc.get_new_plays()

    scrobbled_tracks = 0
    if new_plays is not None:
        for play in new_plays:
            sc.process_scrobble(play)

        scrobbled_tracks = len(new_plays)

    print(
        f"Scrobbled {scrobbled_tracks} {p.plural('track', scrobbled_tracks)}.")


if __name__ == "__main__":
    main()
