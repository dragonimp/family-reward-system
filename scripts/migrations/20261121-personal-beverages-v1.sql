CREATE TABLE beverage_profiles (
    owner_id text NOT NULL,
    id uuid NOT NULL,
    identity_key text NOT NULL,
    favorite boolean NOT NULL DEFAULT false,
    body jsonb NOT NULL,
    PRIMARY KEY (owner_id, id),
    UNIQUE (owner_id, identity_key)
);

CREATE TABLE beverage_consumptions (
    owner_id text NOT NULL,
    id uuid NOT NULL,
    beverage_id uuid NOT NULL,
    consumed_on date NOT NULL,
    body jsonb NOT NULL,
    PRIMARY KEY (owner_id, id),
    FOREIGN KEY (owner_id, beverage_id) REFERENCES beverage_profiles(owner_id, id)
);

CREATE INDEX beverage_consumptions_profile
    ON beverage_consumptions (owner_id, beverage_id, consumed_on DESC, id);
