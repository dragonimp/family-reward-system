-- Once-only schema migration; account values are written only by authenticated user actions.
CREATE TABLE account_module_preferences (
 owner_id TEXT PRIMARY KEY,
 sections JSONB NOT NULL CHECK(jsonb_typeof(sections)='object'),
 version BIGINT NOT NULL DEFAULT 1 CHECK(version>0),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
