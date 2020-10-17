library(tidyverse)
library(httr)
library(progress)
library(RSQLite)

source("api_keys.R")

# makes api request to last.fm for scrobble data
get_scrobble_page = function(lastfm_api_key, user = "ip4589", page = NULL, limit = 200) {
  # url prefix for last.fm api
  base_url = "http://ws.audioscrobbler.com/2.0/"
  # build the query and submit to the api, limit means number of scrobbles to return (max: 200)
  response = GET(base_url, query = list(method = "user.getrecenttracks", user = user, api_key = lastfm_api_key, format = "json", limit = limit, page = page))
  if (response$status_code != 200) {
    stop(paste("bad response status code:", response$status_code))
  }
  return(response)
}

# parses the json response and returns the metadata in a list and the scrobbles in a messy data frame
parse_scrobbles_response = function(response) {
  # convert the json response to text
  text = content(response, as = "text", encoding = "UTF-8")
  # convert the json text to R objects (a list of a list of 2 lists)
  parsed <- jsonlite::fromJSON(text, simplifyVector = TRUE)
  # get rid of one extra level of lists and return a list of 2 lists
  return(parsed[[1]])
}

# extracts the scrobbles from the parsed response and cleans up the data
parse_scrobbled_tracks = function(parsed_response, time_zone = "US/Pacific") {
  # the scrobbles are in the second list of the parsed response so just grab that
  raw_tracks = parsed_response[[2]]
  # clean up the scrobbles
  tracks = raw_tracks %>% 
    # convert to a tibble
    as_tibble() %>% 
    # pull fields out of nested data frames
    mutate(artist_name = artist$`#text`,
           artists_mbid = artist$mbid,
           album_name = album$`#text`,
           album_mbid = album$mbid,
           # convert the text utc timestamp to numeric
           timestamp = as.numeric(date$uts),
           # convert the utc time to R datetime
           timestamp = lubridate::as_datetime(timestamp),
           # store the timestamp as text
           timestamp = as.character(timestamp)) %>% 
    # only want the cleaned names, mbids, urls, and timestamps
    select(artist_name, album_name, track_name = name, artists_mbid, album_mbid, track_mbid = mbid, url, timestamp)
  return(tracks)
}

# downloads the entire scrobble history
get_all_scrobbles = function(lastfm_api_key, user = "ip4589") {
  # grab the first page of scrobbles from the api and parse
  first_page_response = get_scrobble_page(lastfm_api_key, user = user, page = 1) %>% 
    parse_scrobbles_response()
  
  # find the total number of pages of scrobbles (contained in the metadata of the response)
  number_of_pages = first_page_response %>%
    # the metadata is the first list in the parsed response so grab it
    magrittr::extract2(1) %>% 
    # pull out the total pages field
    magrittr::use_series("totalPages") %>%
    # convert the total pages value from character to numeric
    as.numeric()
  # parse the tracks from the first page since we already have it
  first_page_tracks = parse_scrobbled_tracks(first_page_response)
  
  # intialize the progress bar
  pb = progress_bar$new(
    total = number_of_pages,
    format = "  page :current of :total [:bar] :percent")
  
  # show the progress bar at 1
  pb$tick(1)
  
  # loop over the number of pages and grab each page, parse it, and clean the scrobbles
  remaining_tracks = map_dfr(2:number_of_pages, function(page) {
    # update the progress bar
    pb$tick()
    # grab the next page of scrobbles
    get_scrobble_page(lastfm_api_key, user = user, page = page) %>% 
      # parse the response
      parse_scrobbles_response() %>% 
      # clean up the scrobbles
      parse_scrobbled_tracks()
  })
  # once we've got all the scrobbles combine the first page with the rest of the pages
  all_tracks = bind_rows(first_page_tracks, remaining_tracks)
  return(all_tracks)
}
  
all_scrobbled_tracks = get_all_scrobbles(lastfm_api_key)

db = dbConnect(RSQLite::SQLite(), "./scrobbles.sqlite")

copy_to(db, all_scrobbled_tracks, "scrobbles", temporary = FALSE, indexes = list("timestamp", "artist_name", "album_name", "track_name"))

dbDisconnect(db)


