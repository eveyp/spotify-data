library(dplyr)
library(spotifyr)
library(RSQLite)

source("api_keys.R")

source("connect_to_db.R")

spotify_auth_code = get_spotify_authorization_code(client_id = spotify_client_id, client_secret = spotify_client_secret, scope = "user-read-recently-played")


query = paste("SELECT MAX(timestamp) FROM api_tracks_played")

latest_timestamp = unlist(dbGetQuery(db, query))

get_recent_tracks = function(authorization = spotify_auth_code) {
  response = NULL
  try(response <- get_my_recently_played(limit = 50, authorization = authorization, after = latest_timestamp))
  if (is.data.frame(response)) {
    recent_tracks = response %>% 
      select(timestamp = played_at, spotify_id = track.id, track_name = track.name)
    
    dbAppendTable(db, "api_tracks_played", recent_tracks)
    
    latest_timestamp <<- max(recent_tracks$timestamp)
  }
  
  later::later(get_recent_tracks, 300)
  
  message(paste0(lubridate::now("UTC"), ": last recorded timestamp: ", latest_timestamp))
}

get_recent_tracks()
