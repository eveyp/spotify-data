library(RSQLite)

db = dbConnect(RSQLite::SQLite(), "\\\\192.168.1.198\\sambashare\\databases\\scrobbles.sqlite")
