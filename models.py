from sqlalchemy import Column, Integer, String, ForeignKey, Table
from sqlalchemy.orm import relation, relationship, backref
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql.sqltypes import Float

Base = declarative_base()

# artist_album = Table(
#     "artists_albums",
#     Base.metadata,
#     Column("artist_id", String, ForeignKey("artists.spotify_id")),
#     Column("album_id", String, ForeignKey("albums.spotify_id"))
# )


artists_genres = Table(
    "artists_genres",
    Base.metadata,
    Column("artist_id", String, ForeignKey("artists.spotify_id")),
    Column("genre", String, ForeignKey("genres.name"))
)

albums_genres = Table(
    "albums_genres",
    Base.metadata,
    Column("album_id", String, ForeignKey("albums.spotify_id")),
    Column("genre", String, ForeignKey("genres.name"))
)


class Album(Base):
    __tablename__ = "albums"
    spotify_id = Column(String, primary_key=True)
    lead_artist_id = Column(String, ForeignKey("artists.spotify_id"))
    name = Column(String)
    popularity = Column(Integer)
    cover_url = Column(String)
    release_date = Column(String)
    type = Column(String)
    label = Column(String)

    artists = relationship('Artist', back_populates="albums")
    tracks = relationship('Track', back_populates="album")
    genres = relationship(
        'Genre', secondary='albums_genres', back_populates="albums")


class Artist(Base):
    __tablename__ = "artists"
    spotify_id = Column(String, primary_key=True)
    name = Column(String)
    popularity = Column(Integer)
    image_url = Column(String)

    albums = relationship('Album', back_populates="artists")
    tracks = relationship('Track', back_populates='lead_artist')
    genres = relationship(
        'Genre', secondary='artists_genres', back_populates='artists')


class Genre(Base):
    __tablename__ = "genres"
    id = Column(Integer, primary_key=True)
    name = Column(String)

    artists = relationship(
        'Artist', secondary='artists_genres', back_populates='genres')
    albums = relationship(
        'Album', secondary='albums_genres', back_populates='genres')


class Scrobble(Base):
    __tablename__ = "scrobbles"
    id = Column(Integer, primary_key=True)
    timestamp = Column(String)
    spotify_id = Column(String, ForeignKey("tracks.spotify_id"))
    track_name = Column(String)


class Track(Base):
    __tablename__ = "tracks"
    spotify_id = Column(String, primary_key=True)
    name = Column(String)
    lead_artist_id = Column(String, ForeignKey("artists.spotify_id"))
    album_id = Column(String, ForeignKey("albums.spotify_id"))
    length_ms = Column(Integer)
    explicit = Column(Integer)
    popularity = Column(Integer)
    track_number = Column(Integer)
    acousticness = Column(Float)
    danceability = Column(Float)
    energy = Column(Float)
    instrumentalness = Column(Float)
    key = Column(Integer)
    liveness = Column(Float)
    mode = Column(Integer)
    speechiness = Column(Float)
    tempo = Column(Float)
    valence = Column(Float)
    time_signature = Column(Float)

    album = relationship("Album", back_populates="tracks")
    lead_artist = relationship("Artist", back_populates="tracks")
    scrobbles = relationship("Scrobble")
