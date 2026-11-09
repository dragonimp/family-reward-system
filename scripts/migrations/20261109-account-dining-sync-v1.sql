-- Schema only. Existing device archives are imported by authenticated client sync.
CREATE TABLE account_dining_archives (
 owner_id TEXT PRIMARY KEY,
 archive JSONB NOT NULL CHECK(jsonb_typeof(archive)='object'),
 tombstones JSONB NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(tombstones)='object'),
 version BIGINT NOT NULL DEFAULT 1 CHECK(version>0),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE account_dining_sync_operations (
 owner_id TEXT NOT NULL REFERENCES account_dining_archives(owner_id),
 operation_id UUID NOT NULL,
 payload_sha256 CHAR(64) NOT NULL,
 completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(owner_id,operation_id)
);
