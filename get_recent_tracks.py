from spotipy.oauth2 import SpotifyOAuth
import spotipy
import sqlite3
import yaml
import logging
import logging.handlers

# start logger
log_format = '%(asctime)s %(levelname)s: %(message)s'
log_date_format = 'spotify-logger:'
handler = [logging.handlers.SysLogHandler(address='/dev/log')]
logging.basicConfig(handlers=handler, level="INFO",
                    format=log_format, datefmt=log_date_format)

# read in api keys
with open('api_keys.yaml') as file:
    keys = yaml.full_load(file)

# connect to the spotify api
try:
    sp = spotipy.Spotify(auth_manager=SpotifyOAuth(scope='user-read-recently-played',
                                                   client_secret=keys['spotify']['client secret'],
                                                   client_id=keys['spotify']['client id'],
                                                   redirect_uri='http://localhost:1410/'))
except Exception as e:
    logging.exception("Could not connect to Spotify.")

# connect to the database
try:
    conn = sqlite3.connect(keys['db location'])
    db = conn.cursor()
except Exception as e:
    logging.exception("Could not connect to database.")

# get the timestamp of the latest record from the database
last_track_query = 'SELECT MAX(timestamp) FROM scrobbles;'
db.execute(last_track_query)
last_track_ts = db.fetchone()

# poll spotify for tracks played since the latest record in the database
try:
    results = sp.current_user_recently_played(after=last_track_ts)
except Exception as e:
    logging.exception("Error fetching recent tracks from Spotify.")

# prep results for writing to database
def parse_play_record(record):
    timestamp = record['played_at']
    spotify_id = record['track']['id']
    track_name = record['track']['name']

    # return a tuple that can be passed to the database
    return((timestamp, spotify_id, track_name))


# combine all of the new records into a list
try:
    tracks = [parse_play_record(i) for i in results['items']]
except Exception as e:
    logging.exception("Error parsing tracks.")

# write the new list to the database
try:
    insert_query = "INSERT INTO scrobbles ('timestamp', 'spotify_id', 'track_name') VALUES (?, ? ,?);"
    # execute the insert query
    db.executemany(insert_query, tracks)
    # write the result to the database
    conn.commit()
except Exception as e:
    logging.exception("Error writing to database.")

# disconnect from the database
conn.close()

# log how many tracks were recorded
logging.info("Scrobbled %d tracks.", len(tracks))
