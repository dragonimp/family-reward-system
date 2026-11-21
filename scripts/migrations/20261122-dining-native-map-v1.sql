ALTER TABLE dining_food_maps ADD COLUMN coordinate_system text NOT NULL DEFAULT 'gcj02'
    CHECK (coordinate_system IN ('gcj02', 'wgs84'));
ALTER TABLE dining_food_map_places ADD COLUMN approved boolean NOT NULL DEFAULT true;
ALTER TABLE dining_food_map_places ALTER COLUMN approved SET DEFAULT false;
