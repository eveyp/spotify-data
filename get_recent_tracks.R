library(tidyverse)
library(spotifyr)

source("api_keys.R")

spotify_auth_code = get_spotify_authorization_code(client_id = spotify_client_id, client_secret = spotify_client_secret, scope = "user-read-recently-played")

get_recent_tracks = function(limit = 50, authorization, ...) {
  get_my_recently_played(limit = limit,  authorization = authorization, ...) %>%
    mutate(timestamp = lubridate::ymd_hms(played_at))
}

recent_tracks = get_recent_tracks(authorization = spotify_auth_code)
