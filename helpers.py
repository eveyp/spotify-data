from sqlalchemy import and_, create_engine
from sqlalchemy.orm import sessionmaker
from spotipy.oauth2 import SpotifyOAuth
from spotipy import Spotify
import yaml


def get_spotify_api_keys(key_file):
    with open(key_file) as file:
        keys = yaml.full_load(file)

    client_secret = keys['spotify']['client secret']
    client_id = keys['spotify']['client id']

    return client_secret, client_id


def get_spotify_api(
        client_secret=None,
        client_id=None,
        settings_file=None,
        scope='user-read-recently-played',
        redirect_uri='http://localhost:1410/'):

    if (client_secret is None or client_id is None) and settings_file is None:
        raise ValueError("Must specify a client secret, client id pair or a settings file.")

    if (client_secret is not None or client_id is not None) and settings_file is not None:
        raise ValueError(
            "Specify either a client secret, client id pair or a settings file, not both.")

    if settings_file is not None:
        client_secret, client_id = get_spotify_api_keys(settings_file)

    sp = Spotify(auth_manager=SpotifyOAuth(
        scope=scope,
        client_secret=client_secret,
        client_id=client_id,
        redirect_uri=redirect_uri)
    )

    return sp


def get_db_path(file):
    with open(file) as file:
        keys = yaml.safe_load(file)

    db_path = keys['db string']

    return db_path


def get_db_session(settings_file=None, db_path=None, include_engine=False):
    if settings_file is None and db_path is None:
        raise ValueError("Must specify a settings file or database path.")

    if settings_file is not None and db_path is not None:
        raise ValueError("Specify a settings file or database path, not both.")

    if db_path is None:
        db_path = get_db_path(settings_file)

    engine = create_engine(db_path)
    Session = sessionmaker(bind=engine)
    session = Session()

    if not include_engine:
        return session
    else:
        return session, engine