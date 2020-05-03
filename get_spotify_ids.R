library(tidyverse)
library(spotifyr)
library(musicbrainz)

source(api_keys.R)

spotify_token = get_spotify_access_token(client_id = spotify_client_id, spotify_client_secret = client_secret)

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
    return(NA_character_)
  }
  else {
    id = unlist(result$id[1])
  }
  return(id)
}

spotify_ids = pmap_chr(unique_songs, find_spotify_id, authorization = spotify_token) 

unique_songs = unique_songs %>% 
  bind_cols(tibble(spotify_id = spotify_ids))
