library(tidyverse)
library(httr)
library(progress)
library(spotifyr)
library(rvest)
library(furrr)
library(RSQLite)
library(dbplyr)

# load api secrets
source("api_keys.R")

plan(multiprocess)

# get spotify api authentication token
spotify_token = get_spotify_access_token(client_id = spotify_client_id, client_secret = spotify_client_secret)

scrobbles = get_all_scrobbles(lastfm_api_key = lastfm_api_key) %>% 
  select(-ends_with("mbid")) %>% 
  rename(artist = artist_name, album = album_name, track = track_name)

# connect to the scrobbles database
db = dbConnect(RSQLite::SQLite(), "./scrobbles.sqlite")

copy_to(db, scrobbles, "scrobbles", temporary = FALSE, indexes = list("timestamp", "artist", "album", "track", "url"))

# get the unique tracks
unique_tracks = scrobbles %>%
  # just want artist, album, track, and last.fm url. also clean column names for later use
  select(artist, album, track, url) %>% 
  # keep just the unique rows
  distinct() %>% 
  # process the query
  collect()

# search via the spotify api for the spotify ids
spotify_ids_api = unique_tracks %>% 
  # drop the last.fm url since we don't need it for this
  select(-url) %>% 
  # loop over the tracks and return a tibble with artist, album, track, spotify_id
  pmap_dfr(find_spotify_id, authorization = spotify_token)

unique_tracks_with_ids = unique_tracks %>% 
  left_join(spotify_ids_api, by = c("artist", "album", "track"))

missing_id_urls = unique_tracks_with_ids %>% 
  filter(is.na(spotify_id)) %>% 
  select(url) %>% 
  distinct() %>% 
  pull(url)

scraped_ids = scrape_spotify_ids(missing_ids_urls)

no_longer_missing_id_from_api = unique_tracks_with_ids %>% 
  filter(is.na(spotify_id)) %>% 
  select(-spotify_id) %>% 
  left_join(scraped_ids, by = "url")

final_spotify_ids = unique_tracks_with_ids %>% 
  filter(!is.na(spotify_id)) %>% 
  bind_rows(no_longer_missing_id_from_api)

scrobbles_with_ids = scrobbles %>% 
  left_join(final_spotify_ids, by = c("artist", "album", "track", "url")) %>% 
  select(-url)

# connect to the scrobbles database
source("connect_to_db.R")

copy_to(db, scrobbles_with_ids, "scrobbles", temporary = FALSE, indexes = list("timestamp", "artist", "album", "track", "spotify_id"), overwrite = TRUE)

dbDisconnect(db)


