from spotipy.oauth2 import SpotifyOAuth
from spotipy import Spotify
import yaml

def get_spotify_api_keys(key_file):
    with open(key_file) as file:
        keys = yaml.full_load(file)

    client_secret = keys['spotify']['client secret']
    client_id = keys['spotify']['client id']

    return (client_secret, client_id)

def get_spotify_api(client_secret, client_id, scope='user-read-recently-played', redirect_uri='http://localhost:1410/'):
    sp = Spotify(auth_manager=SpotifyOAuth(scope=scope,
                                                   client_secret=client_secret,
                                                   client_id=client_id,
                                                   redirect_uri=redirect_uri))
    return sp

def get_db_path(file):
    with open(file) as file:
        keys = yaml.full_load(file)

    db_path = keys['db location']

    return db_path
