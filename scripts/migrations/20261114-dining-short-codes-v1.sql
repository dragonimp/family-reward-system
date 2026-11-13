CREATE TABLE dining_short_codes (
    code text PRIMARY KEY CHECK (code ~ '^[0-9]{6}$'),
    gathering_id uuid NOT NULL UNIQUE REFERENCES dining_gatherings(id),
    expires_at timestamptz NOT NULL
);
CREATE TABLE dining_code_attempts (
    owner_id text PRIMARY KEY,
    window_start timestamptz NOT NULL,
    attempts integer NOT NULL
);
