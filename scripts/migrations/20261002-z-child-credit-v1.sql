-- Credit is separate from redeemable points. Existing children stay unopened.
CREATE TABLE child_credit_accounts (
    profile_key VARCHAR(180) PRIMARY KEY REFERENCES child_profiles(profile_key) ON DELETE CASCADE,
    score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
    version BIGINT NOT NULL DEFAULT 1,
    opened_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE child_commitments (
    id BIGSERIAL PRIMARY KEY,
    profile_key VARCHAR(180) NOT NULL REFERENCES child_credit_accounts(profile_key) ON DELETE CASCADE,
    owner_parent_app_user_id VARCHAR(180) NOT NULL,
    title VARCHAR(160) NOT NULL,
    due_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'pending', 'overdue', 'late_pending', 'completed')),
    completion_requested_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    request_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (profile_key, request_id)
);

CREATE INDEX idx_child_commitments_profile_created ON child_commitments(profile_key, created_at DESC);

CREATE TABLE child_credit_events (
    id BIGSERIAL PRIMARY KEY,
    profile_key VARCHAR(180) NOT NULL REFERENCES child_credit_accounts(profile_key) ON DELETE CASCADE,
    commitment_id BIGINT REFERENCES child_commitments(id) ON DELETE SET NULL,
    reason_code VARCHAR(40) NOT NULL,
    delta INTEGER NOT NULL,
    score_before INTEGER NOT NULL CHECK (score_before BETWEEN 0 AND 100),
    score_after INTEGER NOT NULL CHECK (score_after BETWEEN 0 AND 100),
    note VARCHAR(500) NOT NULL DEFAULT '',
    actor_user_id VARCHAR(180) NOT NULL,
    request_id UUID,
    reversal_of_event_id BIGINT UNIQUE REFERENCES child_credit_events(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (profile_key, request_id)
);

CREATE INDEX idx_child_credit_events_profile_created ON child_credit_events(profile_key, created_at DESC);

CREATE TABLE child_credit_disputes (
    id BIGSERIAL PRIMARY KEY,
    profile_key VARCHAR(180) NOT NULL REFERENCES child_credit_accounts(profile_key) ON DELETE CASCADE,
    event_id BIGINT NOT NULL UNIQUE REFERENCES child_credit_events(id),
    reason VARCHAR(500) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    parent_response VARCHAR(500) NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMPTZ
);

CREATE INDEX idx_child_credit_disputes_profile_status ON child_credit_disputes(profile_key, status, created_at DESC);
