-- Parent-child connection records are private to the child's bound parent and device.
-- Rollback, if required before use: DROP TABLE family_connection_entries; DROP TABLE family_connections.
-- Once records exist, preserve them and use a new corrective migration instead.
CREATE TABLE family_connections (
    id BIGSERIAL PRIMARY KEY,
    child_profile_key VARCHAR(180) NOT NULL REFERENCES child_profiles(profile_key) ON DELETE CASCADE,
    parent_app_user_id VARCHAR(180) NOT NULL,
    kind VARCHAR(24) NOT NULL CHECK (kind IN ('special_time', 'listen', 'reconnect', 'meeting')),
    title VARCHAR(160) NOT NULL,
    intent VARCHAR(24) NOT NULL DEFAULT '' CHECK (intent IN ('', 'share', 'comfort', 'ideas')),
    status VARCHAR(24) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'scheduled', 'trial', 'completed', 'cancelled')),
    scheduled_at TIMESTAMPTZ,
    review_at TIMESTAMPTZ,
    trial_plan VARCHAR(500) NOT NULL DEFAULT '',
    request_id UUID NOT NULL,
    created_by VARCHAR(8) NOT NULL CHECK (created_by IN ('child', 'parent')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (child_profile_key, parent_app_user_id, request_id)
);
CREATE INDEX idx_family_connections_parent ON family_connections(parent_app_user_id, updated_at DESC);
CREATE INDEX idx_family_connections_child ON family_connections(child_profile_key, updated_at DESC);

CREATE TABLE family_connection_entries (
    id BIGSERIAL PRIMARY KEY,
    connection_id BIGINT NOT NULL REFERENCES family_connections(id) ON DELETE CASCADE,
    author_role VARCHAR(8) NOT NULL CHECK (author_role IN ('child', 'parent')),
    entry_type VARCHAR(24) NOT NULL CHECK (entry_type IN ('message', 'feeling', 'hope', 'proposal', 'reflection')),
    content VARCHAR(500) NOT NULL,
    request_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (connection_id, request_id)
);
CREATE INDEX idx_family_connection_entries_thread ON family_connection_entries(connection_id, created_at, id);
