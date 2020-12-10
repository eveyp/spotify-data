library(tidyverse)
library(httr)
library(progress)
library(spotifyr)
library(rvest)
library(furrr)
library(RSQLite)
library(dbplyr)

#### downloading scrobbles from last.fm

# makes api request to last.fm for scrobble data
get_scrobble_page = function(lastfm_api_key, user = "ip4589", page = NULL, limit = 200, from = NULL) {
  # url prefix for last.fm api
  base_url = "http://ws.audioscrobbler.com/2.0/"
  # build the query and submit to the api, limit means number of scrobbles to return (max: 200)
  response = RETRY("GET", base_url, query = list(method = "user.getrecenttracks", user = user, api_key = lastfm_api_key, format = "json", limit = limit, page = page, from = from))
  # check to see if we got a good response, if not stop the program
  if (response$status_code != 200) {
    stop(paste("bad response status code:", response$status_code))
  }
  # return the response
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
           timestamp = date$uts) %>% 
    # only want the cleaned names, mbids, urls, and timestamps
    select(artist_name, album_name, track_name = name, artists_mbid, album_mbid, track_mbid = mbid, url, timestamp)
  return(tracks)
}

# downloads the entire scrobble history
get_all_scrobbles = function(lastfm_api_key, user = "ip4589", from = NULL) {
  # grab the first page of scrobbles from the api and parse
  first_page_response = get_scrobble_page(lastfm_api_key, user = user, page = 1, from = from) %>% 
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
  if (!is.null(from)) {
    all_tracks = filter(all_tracks, as.numeric(timestamp) > from)
  }
  return(all_tracks)
}

#### getting the spotify ids for the scrobbled tracks

# searching spotify by artist, album, track using their api
find_spotify_id = function(artist = NULL, album = NULL, track = NULL, authorization = NULL) {
  # building the search query (format is: artist:<artist name> album:<album name> track:<track name>)
  query = paste(
    if_else(!is.na(artist), paste0("artist:", artist), NULL),
    if_else(!is.na(album), paste0("album:", album), NULL),
    if_else(!is.na(track), paste0("track:", track), NULL))
  
  # hit the spotify search api
  result = search_spotify(query, type = "track", authorization = authorization)
  
  # return a row of NAs if nothing comes back
  if (nrow(result) == 0) {
    id = tibble(artist, album, track, spotify_id = NA)
  }
  # otherwise return the first result
  else {
    id = tibble(artist, album, track, spotify_id = result$id[1])
  }
  # increment the progress bar
  pb$tick()
  return(id)
}

# scraping the spotify id from a last.fm track page
scrape_spotify_id = function(url) {
  # setting the default result as NA (this gets returned if we don't find anything or there's an error)
  default = NA
  # try scraping the page, first sending a GET and retrying automatically on error
  try(default <- read_html(RETRY("GET", url)) %>% 
        # narrow down on the part of the page with the link to spotify
        html_node(".play-this-track-playlink--spotify") %>% 
        # narrowing down to the link itself
        html_attr("href") %>% 
        # extracting the spotify id from the link
        stringr::str_extract("(?<=/)[[:alnum:]]*$"), 
      silent = TRUE)
  # returning either the spotify id or NA
  return(default)
} 

# scraping a set of tracks from their last.fm pages
scrape_spotify_ids = function(urls) {
  # setup the progress bar
  pb = progress::progress_bar$new(total = length(urls), format = "  track :current of :total [:bar] :percent")
  # iterate over the vector of urls
  map_dfr(urls, function(url) {
    # increment the progress bar
    pb$tick()
    # scrape the url
    spotify_id = scrape_spotify_id(url)
    # return the url and spotify id as a row
    tibble(url, spotify_id)
  })
}

# parallelizing scraping a set of tracks from their last.fm pages
pscrape_spotify_ids = function(urls) {
  # setup the parallelization plan
  plan(multiprocess)
  # iterate over the vector of urls
  future_map_dfr(urls, .progress = TRUE, function(url) {
    # scrape the url
    spotify_id = scrape_spotify_id(url)
    # return the url and spotify id as a row
    tibble(url, spotify_id)
  })
}

#### getting the track metadata from spotify

# splitting tracks up into chunks of 50 (spotify api limit)
id_chunker = function(ids, chunk_size = 50) {
  split(ids, ceiling(seq_along(ids) / chunk_size)) 
}

# downloading the track data
get_all_tracks = function(ids, authorization, chunk_size = 50) {
  # split the ids into groups
  id_chunks = id_chunker(ids, chunk_size = chunk_size)
  # iterate over the groups and hit the api for the set of tracks in each group
  map_dfr(id_chunks, ~ get_tracks(.x, authorization = authorization))
}

# downloading the track music data features
get_all_track_features = function(ids, authorization, chunk_size = 50) {
  # split the ids into groups
  id_chunks = id_chunker(ids, chunk_size = chunk_size)
  # iterate over the groups and hit the api for the set of tracks in each group
  map_dfr(id_chunks, ~ get_track_audio_features(.x, authorization = authorization))
}

# convert last.fm timestamps (milliseconds since 1970-01-01 00:00:00.000, ie. unix timestamps) to spotify timestamps (format: YYYY-MM-DDTHH-MM-SS.MMMZ)
lastfm_ts_to_spotify = function(raw_timestamp) {
  # add 0.1 to the timestamp to avoid rounding issues and divide by 1000 b/c R interprets this as seconds since orgin, not milliseconds
#  timestamp_decimal = (as.numeric(raw_timestamp) + 0.1) / 1000
  # convert to a date-time object, time zone is GMT, time is seconds since origin (1970-01-01 00:00:00)
  timestamp_posix = as.POSIXct(as.numeric(raw_timestamp), tz = "GMT", origin = "1970-01-01")
  # convert the date-time object to a string
  timestamp_chr = as.character(timestamp_posix)
  # replace the space between the date and time with a "T" as spotify does
  timestamp_chr = str_replace(timestamp_chr, " ", "T")
  # put a "Z" at the end as spotify does
  timestamp_spotify = paste0(timestamp_chr, ".000Z")
  # and we're done!
  return(timestamp_spotify)
}
