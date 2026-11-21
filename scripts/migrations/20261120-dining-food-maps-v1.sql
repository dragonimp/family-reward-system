CREATE TABLE dining_food_maps (
    id uuid PRIMARY KEY,
    owner_id text NOT NULL,
    name text NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
    latitude double precision NOT NULL CHECK (latitude BETWEEN 0 AND 60),
    longitude double precision NOT NULL CHECK (longitude BETWEEN 70 AND 140),
    data_version bigint NOT NULL DEFAULT 0
);
CREATE TABLE dining_food_map_follows (
    map_id uuid NOT NULL REFERENCES dining_food_maps(id),
    user_id text NOT NULL,
    PRIMARY KEY(map_id,user_id)
);
CREATE TABLE dining_food_map_places (
    id uuid PRIMARY KEY,
    map_id uuid NOT NULL REFERENCES dining_food_maps(id),
    owner_id text NOT NULL,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    name text NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
    category text NOT NULL CHECK (length(category) BETWEEN 1 AND 80),
    location_text text NOT NULL CHECK (length(location_text) BETWEEN 1 AND 200),
    description text NOT NULL DEFAULT '' CHECK (length(description) <= 1000),
    version bigint NOT NULL
);
CREATE INDEX dining_food_map_places_version ON dining_food_map_places(map_id,version);
CREATE TABLE dining_food_map_visits (
    place_id uuid NOT NULL REFERENCES dining_food_map_places(id),
    user_id text NOT NULL,
    PRIMARY KEY(place_id,user_id)
);
CREATE TABLE dining_food_map_reviews (
    place_id uuid NOT NULL REFERENCES dining_food_map_places(id),
    user_id text NOT NULL,
    stars smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
    note text NOT NULL DEFAULT '' CHECK (length(note) <= 1000),
    PRIMARY KEY(place_id,user_id)
);
