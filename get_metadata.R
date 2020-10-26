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

# load functions
source("functions.R")

# connect to the database
source("connect_to_db.R")

plan(multiprocess)

# get spotify api authentication token
spotify_token = get_spotify_access_token(client_id = spotify_client_id, client_secret = spotify_client_secret)

# download scrobbles from last.fm
scrobbles = get_all_scrobbles(lastfm_api_key = lastfm_api_key)

# save the scrobbles w/o spotify ids to the database
copy_to(db, scrobbles, "scrobbles", temporary = FALSE, indexes = list("timestamp", "artist_name", "album_name", "track_name", "url"), overwrite = TRUE)

# get the unique tracks
unique_tracks = scrobbles %>%
  # just want artist, album, track, and last.fm url. also clean column names for later use
  select(artist = artist_name, album = album_name, track = track_name, url) %>% 
  # keep just the unique rows
  distinct() 

# set up a progress bar
pb = progress_bar$new(
  total = nrow(unique_tracks),
  format = "  track :current of :total [:bar] :percent")

# search via the spotify api for the spotify ids
spotify_ids_api = unique_tracks %>% 
  # drop the last.fm url since we don't need it for this
  select(-url) %>% 
  # loop over the tracks and return a tibble with artist, album, track, spotify_id
  pmap_dfr(find_spotify_id, authorization = spotify_token)

# merge the searched ids onto the table of unique tracks
unique_tracks_with_ids = unique_tracks %>% 
  left_join(spotify_ids_api, by = c("artist", "album", "track"))

# get a list of last.fm urls for tracks still missing spotify ids
missing_id_urls = unique_tracks_with_ids %>% 
  # filter for only tracks missing spotify id
  filter(is.na(spotify_id)) %>% 
  # only want the url column
  select(url) %>% 
  # get rid of any dupes
  distinct() %>% 
  # turn the column into a vector
  pull(url)

# scrape last.fm for the remaining spotify ids
scraped_ids = scrape_spotify_ids(missing_id_urls)

# merge the scraped ids onto the table of unique tracks
# start with the table after the ids from the api search were added
no_longer_missing_id_from_api = unique_tracks_with_ids %>% 
  # just keep the ones that didn't get an id from the api search
  filter(is.na(spotify_id)) %>% 
  # drop the id column b/c it's empty
  select(-spotify_id) %>% 
  # merge on the scraped ids
  left_join(scraped_ids, by = "url")

# put the api searched ids and the scraped ids together
# start with the list of all unique tracks after the api search
final_spotify_ids = unique_tracks_with_ids %>% 
  # drop the tracksw/o an id 
  filter(!is.na(spotify_id)) %>% 
  # append the tracks with scraped ids
  bind_rows(no_longer_missing_id_from_api)

# merge the ids on to the actual scrobble data
scrobbles_with_ids = scrobbles %>% 
  left_join(final_spotify_ids, by = c("artist_name" = "artist" , "album_name" = "album", "track_name" = "track", "url")) 

# write the scrobble data now with spotify ids to the database
copy_to(db, scrobbles_with_ids, "scrobbles", temporary = FALSE, indexes = list("timestamp", "artist_name", "album_name", "track_name", "spotify_id"), overwrite = TRUE)

# disconnect from the database
dbDisconnect(db)


