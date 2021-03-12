from sqlalchemy import and_, create_engine
from sqlalchemy.orm import sessionmaker
from spotipy.oauth2 import SpotifyOAuth
from spotipy import Spotify
import yaml


def get_spotify_api_keys(key_file):
    with open(key_file) as file:
        keys = yaml.full_load(file)

    keys = {
        'client_secret': keys['spotify']['client secret'],
        'client_id': keys['spotify']['client id']
    }

    return keys


def get_spotify_api(
        keys=None,
        settings_file=None,
        scope='user-read-recently-played',
        redirect_uri='http://localhost:1410/'):

    if keys is None and settings_file is None:
        raise Exception

    if keys is None:
        keys = get_spotify_api_keys(settings_file)

    sp = Spotify(auth_manager=SpotifyOAuth(
        scope=scope,
        client_secret=keys['client_secret'],
        client_id=keys['client_id'],
        redirect_uri=redirect_uri)
    )

    return sp


def get_db_path(file):
    with open(file) as file:
        keys = yaml.full_load(file)

    db_path = keys['db location']

    return db_path


def get_db_session(settings_file=None, db_path=None):
    if settings_file is None and db_path is None:
        raise Exception

    if db_path is None:
        db_path = get_db_path(settings_file)

    engine = create_engine(f"sqlite:///{db_path}")
    Session = sessionmaker(bind=engine)
    session = Session()

    return session
