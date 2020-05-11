library(tidyverse)
library(rvest)
library(furrr)

all_scrobbles = read_csv("scrobbles_as_of_2020-05-05.csv")

page %>% 
  html_node(".resource-external-link--spotify") %>% 
  html_attr("href") %>% 
  stringr::str_extract("(?<=/)[[:alnum:]]*$")

scrape_spotify_id = function(url) {
  read_html(url) %>% 
    html_node(".resource-external-link--spotify") %>% 
    html_attr("href") %>% 
    stringr::str_extract("(?<=/)[[:alnum:]]*$")
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
  plan(multiprocess)
  future_map_dfr(urls, .progress = TRUE, function(url) {
    spotify_id = scrape_spotify_id(url)
    tibble(url, spotify_id)
  })
}

save_ids = function(id_set) {
  name_stub = deparse(substitute(id_set))
  write_csv(id_set, file.path(paste0(name_stub, ".csv")))
}