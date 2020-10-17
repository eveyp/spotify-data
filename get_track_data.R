library(tidyverse)
library(spotifyr)

source("api_keys.R")

spotify_token = get_spotify_access_token(client_id = spotify_client_id, client_secret = spotify_client_secret)

spotify_ids = scrobbles_with_ids %>% 
  filter(!is.na(spotify_id)) %>% 
  select(spotify_id) %>% 
  distinct()

id_chunker = function(ids, chunk_size = 50) {
  split(ids, ceiling(seq_along(ids) / chunk_size)) 
}

get_all_tracks = function(ids, authorization, chunk_size = 50) {
  id_chunks = id_chunker(ids, chunk_size = chunk_size)
  map_dfr(id_chunks, ~ get_tracks(.x, authorization = authorization))
}

get_all_track_features = function(ids, authorization, chunk_size = 50) {
  id_chunks = id_chunker(ids, chunk_size = chunk_size)
  map_dfr(id_chunks, ~ get_track_audio_features(.x, authorization = authorization))
}

# connect to the scrobbles database
db = dbConnect(RSQLite::SQLite(), "./scrobbles.sqlite")

track_data = get_all_tracks(spotify_ids$spotify_id, authorization = spotify_token) %>% 
  select(spotify_id = id, explicit, popularity, release_date = album.release_date, isrc = external_ids.isrc)

copy_to(db, track_data, "track_data", temporary = FALSE, indexes = list("spotify_id"))

track_features = get_all_track_features(final_spotify_ids$spotify_id, authorization = spotify_token) %>% 
  rename(spotify_id = id)

copy_to(db, track_features, "track_features", temporary = FALSE, indexes = list("spotify_id"))

dbDisconnect(db)
