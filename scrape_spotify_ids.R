library(tidyverse)
library(rvest)
library(furrr)

all_scrobbles = read_csv("scrobbles_as_of_2020-05-05.csv")

unique_new_tracks = anti_join(all_scrobbled_tracks, all_scrobbled_tracks_55, by = "timestamp") %>% 
  select(url) %>% 
  distinct()

"https://www.last.fm/music/(Sandy)+Alex+G/_/Hope"

page %>% 
  html_node(".resource-external-link--spotify") %>% 
  html_attr("href") %>% 
  stringr::str_extract("(?<=/)[[:alnum:]]*$")

scrape_spotify_id = function(url) {
  default = NA
  try(default <- read_html(RETRY("GET", url)) %>% 
    html_node(".play-this-track-playlink--spotify") %>% 
    html_attr("href") %>% 
    stringr::str_extract("(?<=/)[[:alnum:]]*$"), 
    silent = TRUE)
  return(default)
} 

scrape_spotify_ids = function(urls) {
  pb = progress::progress_bar$new(total = length(urls), format = "  track :current of :total [:bar] :percent")
  map_dfr(urls, function(url) {
    pb$tick()
    spotify_id = scrape_spotify_id(url)
    tibble(url, spotify_id)
  })
}

pscrape_spotify_ids = function(urls) {
  #plan(multiprocess)
  future_map_dfr(urls, .progress = TRUE, function(url) {
    spotify_id = scrape_spotify_id(url)
    tibble(url, spotify_id)
  })
}

save_ids = function(id_set) {
  name_stub = deparse(substitute(id_set))
  write_csv(id_set, file.path(paste0(name_stub, ".csv")))
}