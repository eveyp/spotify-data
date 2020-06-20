library(tidyverse)
library(spotifyr)

source("api_keys.R")

spotify_token = get_spotify_access_token(client_id = spotify_client_id, client_secret = spotify_client_secret)


spotify_ids = read_csv("spotify_ids.csv") %>% 
  filter(!is.na(spotify_id))

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

track_data = get_all_tracks(spotify_ids$spotify_id, authorization = spotify_token)

track_features = get_all_track_features(spotify_ids$spotify_id, authorization = spotify_token)
