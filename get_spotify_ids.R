library(tidyverse)
library(spotifyr)
library(musicbrainz)

source("api_keys.R")

spotify_token = get_spotify_access_token(client_id = spotify_client_id, client_secret = spotify_client_secret)

lastfm_history = read_csv("../../Downloads/scrobbles-ip4589-1586035171.csv")

unique_songs = lastfm_history %>% 
  mutate(track_mbid = if_else(is.na(track_mbid),
                              str_c(artist, album, track, sep = "-"),
                              track_mbid)) %>% 
  distinct(track_mbid, .keep_all = TRUE) %>% 
  select(artist, album, track)

search_spotify("artist:robyn album:honey track:in the music", type = "track", authorization = spotify_token) 

find_spotify_id = function(artist = NULL, album = NULL, track = NULL, authorization = NULL) {
  query = paste(
    if_else(!is.na(artist), paste0("artist:", artist), NULL),
    if_else(!is.na(album), paste0("album:", album), NULL),
    if_else(!is.na(track), paste0("track:", track), NULL))

  result = search_spotify(query, type = "track", authorization = authorization)
  if (nrow(result) == 0) {
    id = tibble(artist, album, track, spotify_id = NA)
  }
  else {
    id = tibble(artist, album, track, spotify_id = result$id[1])
  }
  return(id)
}

spotify_ids = pmap_chr(unique_songs, find_spotify_id, authorization = spotify_token) 

unique_songs = unique_songs %>% 
  bind_cols(tibble(spotify_id = spotify_ids))

new_tracks = new_tracks %>% 
  left_join(new_ids, by = "url")

na_new_tracks = new_tracks %>% 
  filter(is.na(spotify_id)) %>% 
  distinct(artist_name, album_name, track_name) %>% 
  select(artist = artist_name, album = album_name, track = track_name)

na_ids = pmap_dfr(na_new_tracks, find_spotify_id, authorization = spotify_token)

