CREATE TABLE dining_gatherings (
    id uuid PRIMARY KEY,
    host_id text NOT NULL,
    join_code uuid NOT NULL UNIQUE,
    restaurant_id text NOT NULL,
    restaurant_name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    ended_at timestamptz
);

CREATE TABLE dining_gathering_members (
    gathering_id uuid NOT NULL REFERENCES dining_gatherings(id),
    user_id text NOT NULL,
    joined_at timestamptz NOT NULL DEFAULT now(),
    confirmed_at timestamptz,
    PRIMARY KEY (gathering_id, user_id)
);

CREATE INDEX dining_gathering_member_history
    ON dining_gathering_members (user_id, joined_at DESC);
