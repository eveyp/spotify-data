library(RSQLite)

db = dbConnect(RSQLite::SQLite(), "./scrobbles.sqlite")
