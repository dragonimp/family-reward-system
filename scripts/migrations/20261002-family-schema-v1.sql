-- Immutable schema baseline extracted from the former application startup.
-- Historical data repairs and user-content seeding are intentionally excluded.

CREATE TABLE IF NOT EXISTS system_config (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    config_json JSONB NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS xiaotiancai_device_test_email_submissions (
    id SERIAL PRIMARY KEY,
    requested_by VARCHAR(160) NOT NULL,
    recipient VARCHAR(320) NOT NULL,
    sender VARCHAR(320) NOT NULL,
    device_model VARCHAR(20) NOT NULL,
    version_name VARCHAR(40) NOT NULL,
    version_code INTEGER NOT NULL,
    subject VARCHAR(500) NOT NULL,
    message_id VARCHAR(500),
    previous_message_id VARCHAR(500),
    attachment_manifest JSONB NOT NULL,
    status VARCHAR(20) NOT NULL,
    provider_response TEXT,
    error_message TEXT,
    sent_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_xiaotiancai_device_test_email_sending
ON xiaotiancai_device_test_email_submissions ((status))
WHERE status = 'sending';

CREATE TABLE IF NOT EXISTS family_groups (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    created_by VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS family_group_users (
    id SERIAL PRIMARY KEY,
    family_group_id INTEGER NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
    user_id VARCHAR(100) NOT NULL,
    role VARCHAR(30) DEFAULT 'member',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(family_group_id, user_id)
);

CREATE TABLE IF NOT EXISTS family_group_invites (
    id SERIAL PRIMARY KEY,
    family_group_id INTEGER NOT NULL UNIQUE REFERENCES family_groups(id) ON DELETE CASCADE,
    invite_code VARCHAR(8) NOT NULL UNIQUE,
    created_by VARCHAR(180) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMP NULL
);

CREATE TABLE IF NOT EXISTS app_user_profiles (
    id SERIAL PRIMARY KEY,
    unified_user_id VARCHAR(160) NOT NULL,
    username VARCHAR(160) NOT NULL,
    channel VARCHAR(20) NOT NULL DEFAULT 'pc',
    role VARCHAR(20) NOT NULL,
    app_user_id VARCHAR(180) NOT NULL,
    child_profile_key VARCHAR(180),
    child_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(unified_user_id, channel)
);

CREATE TABLE IF NOT EXISTS child_user_bindings (
    id SERIAL PRIMARY KEY,
    parent_app_user_id VARCHAR(180) NOT NULL,
    child_profile_key VARCHAR(180) NOT NULL,
    child_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(parent_app_user_id, child_profile_key)
);

CREATE TABLE IF NOT EXISTS household_members (
    id SERIAL PRIMARY KEY,
    owner_parent_app_user_id VARCHAR(180) NOT NULL,
    display_name VARCHAR(50) NOT NULL,
    role VARCHAR(30) NOT NULL DEFAULT 'guardian',
    note TEXT,
    is_current_user BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS child_profiles (
    profile_key VARCHAR(180) PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    note TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS child_auth_codes (
    id SERIAL PRIMARY KEY,
    child_id INTEGER NOT NULL,
    family_group_id INTEGER NOT NULL,
    child_profile_key VARCHAR(180) NOT NULL,
    parent_app_user_id VARCHAR(180) NOT NULL,
    code_hash VARCHAR(128) NOT NULL UNIQUE,
    expires_at TIMESTAMP NOT NULL,
    used_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS watch_device_bindings (
    id SERIAL PRIMARY KEY,
    child_id INTEGER NOT NULL,
    family_group_id INTEGER NOT NULL,
    child_profile_key VARCHAR(180) NOT NULL,
    parent_app_user_id VARCHAR(180) NOT NULL,
    device_token_hash VARCHAR(128) NOT NULL UNIQUE,
    device_name VARCHAR(240) NOT NULL DEFAULT '',
    platform VARCHAR(80) NOT NULL DEFAULT '',
    user_agent TEXT NOT NULL DEFAULT '',
    bound_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMP NULL
);

CREATE TABLE IF NOT EXISTS watch_device_unbind_codes (
    id SERIAL PRIMARY KEY,
    device_binding_id INTEGER NOT NULL REFERENCES watch_device_bindings(id) ON DELETE CASCADE,
    child_id INTEGER NOT NULL,
    family_group_id INTEGER NOT NULL,
    parent_app_user_id VARCHAR(180) NOT NULL,
    code_hash VARCHAR(128) NOT NULL UNIQUE,
    expires_at TIMESTAMP NOT NULL,
    used_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS watch_face_preferences (
    child_profile_key VARCHAR(180) PRIMARY KEY,
    watch_face VARCHAR(40) NOT NULL DEFAULT 'world',
    friend_leaderboard_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE watch_face_preferences ADD COLUMN IF NOT EXISTS friend_leaderboard_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS parent_warm_moments (
    id SERIAL PRIMARY KEY,
    parent_app_user_id VARCHAR(180) NOT NULL,
    child_profile_key VARCHAR(180) NOT NULL,
    child_id INTEGER NOT NULL,
    family_group_id INTEGER NOT NULL,
    household_member_id INTEGER REFERENCES household_members(id) ON DELETE SET NULL,
    parent_display_name VARCHAR(50) NOT NULL,
    content TEXT NOT NULL,
    input_method VARCHAR(20) NOT NULL DEFAULT 'text',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (input_method IN ('text', 'voice'))
);

CREATE INDEX IF NOT EXISTS idx_parent_warm_moments_owner_created ON parent_warm_moments(parent_app_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_parent_warm_moments_child_created ON parent_warm_moments(child_profile_key, created_at DESC);

CREATE TABLE IF NOT EXISTS growth_reports (
    id SERIAL PRIMARY KEY,
    parent_app_user_id VARCHAR(180) NOT NULL,
    child_profile_key VARCHAR(180),
    audience VARCHAR(20) NOT NULL,
    period_type VARCHAR(20) NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    praise TEXT NOT NULL,
    next_step TEXT NOT NULL,
    change_summary TEXT NOT NULL,
    source_refs JSONB NOT NULL DEFAULT '[]'::jsonb,
    generated_by VARCHAR(30) NOT NULL DEFAULT 'rules',
    generated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (audience IN ('child', 'parent')),
    CHECK (period_type IN ('daily', 'weekly', 'monthly')),
    UNIQUE (parent_app_user_id, child_profile_key, audience, period_type, period_start)
);

CREATE TABLE IF NOT EXISTS subscription_plan_features (
    product_code VARCHAR(80) NOT NULL,
    plan_code VARCHAR(80) NOT NULL,
    feature_code VARCHAR(80) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    updated_by VARCHAR(180) NOT NULL DEFAULT '',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (product_code, plan_code, feature_code)
);

CREATE TABLE IF NOT EXISTS app_user_subscriptions (
    unified_user_id VARCHAR(180) NOT NULL,
    product_code VARCHAR(80) NOT NULL,
    plan_code VARCHAR(80) NOT NULL,
    source_order_id VARCHAR(80) NOT NULL,
    status VARCHAR(30) NOT NULL,
    starts_at TIMESTAMP NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    last_event_id VARCHAR(180) NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (unified_user_id, product_code, plan_code)
);

CREATE TABLE IF NOT EXISTS app_user_business_statuses (
    unified_user_id VARCHAR(180) PRIMARY KEY,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    reason VARCHAR(500) NOT NULL DEFAULT '',
    updated_by VARCHAR(180) NOT NULL DEFAULT '',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS app_admin_audit_events (
    id SERIAL PRIMARY KEY,
    actor_unified_user_id VARCHAR(180) NOT NULL,
    action VARCHAR(80) NOT NULL,
    target VARCHAR(240) NOT NULL,
    detail_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS child_friend_codes (
    id SERIAL PRIMARY KEY,
    child_profile_key VARCHAR(180) NOT NULL,
    parent_app_user_id VARCHAR(180) NOT NULL,
    code_hash VARCHAR(128) NOT NULL UNIQUE,
    expires_at TIMESTAMP NOT NULL,
    used_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS child_friendships (
    id SERIAL PRIMARY KEY,
    child_profile_key_a VARCHAR(180) NOT NULL,
    child_profile_key_b VARCHAR(180) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_by_child_profile_key VARCHAR(180) NOT NULL,
    created_by_code_id INTEGER REFERENCES child_friend_codes(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (child_profile_key_a < child_profile_key_b),
    UNIQUE(child_profile_key_a, child_profile_key_b)
);

CREATE TABLE IF NOT EXISTS child_friend_notifications (
    id SERIAL PRIMARY KEY,
    parent_app_user_id VARCHAR(180) NOT NULL,
    child_profile_key VARCHAR(180) NOT NULL,
    friend_profile_key VARCHAR(180) NOT NULL,
    friendship_id INTEGER REFERENCES child_friendships(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    read_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS children (
    id SERIAL PRIMARY KEY,
    family_group_id INTEGER REFERENCES family_groups(id) ON DELETE RESTRICT,
    name VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'active',
    note TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(family_group_id, name)
);

ALTER TABLE children ADD COLUMN IF NOT EXISTS family_group_id INTEGER;

ALTER TABLE children ADD COLUMN IF NOT EXISTS profile_key VARCHAR(160);

DO $$
BEGIN
    ALTER TABLE children
    ADD CONSTRAINT fk_children_family_group
    FOREIGN KEY (family_group_id) REFERENCES family_groups(id) ON DELETE RESTRICT;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE family_groups DROP CONSTRAINT IF EXISTS family_groups_name_key;

CREATE UNIQUE INDEX IF NOT EXISTS ux_family_groups_created_by_name ON family_groups(created_by, name);

ALTER TABLE children DROP CONSTRAINT IF EXISTS children_name_key;

ALTER TABLE children DROP CONSTRAINT IF EXISTS children_family_group_id_name_key;

DROP INDEX IF EXISTS ux_children_family_group_name;

CREATE UNIQUE INDEX IF NOT EXISTS ux_children_family_group_profile ON children(family_group_id, profile_key) WHERE profile_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS accounts (
    id SERIAL PRIMARY KEY,
    child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    points NUMERIC(10,2) DEFAULT 0,
    cash_cny NUMERIC(10,2) DEFAULT 0,
    items_count INTEGER DEFAULT 0,
    items_detail TEXT,
    points_earned NUMERIC(10,2) DEFAULT 0,
    points_spent NUMERIC(10,2) DEFAULT 0,
    cash_earned NUMERIC(10,2) DEFAULT 0,
    cash_spent NUMERIC(10,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(child_id)
);

ALTER TABLE accounts ADD COLUMN IF NOT EXISTS profile_key VARCHAR(160);

ALTER TABLE accounts ALTER COLUMN points TYPE NUMERIC(10,2) USING points::numeric;

ALTER TABLE accounts ALTER COLUMN points_earned TYPE NUMERIC(10,2) USING points_earned::numeric;

ALTER TABLE accounts ALTER COLUMN points_spent TYPE NUMERIC(10,2) USING points_spent::numeric;

DROP INDEX IF EXISTS ux_accounts_profile_key;

CREATE UNIQUE INDEX IF NOT EXISTS ux_accounts_profile_key ON accounts(profile_key);

CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL,
    direction VARCHAR(10) NOT NULL,
    category VARCHAR(50),
    description TEXT,
    points NUMERIC(10,2) DEFAULT 0,
    cash_cny NUMERIC(10,2) DEFAULT 0,
    items TEXT,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (direction IN ('+', '-'))
);

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(64);

CREATE TABLE IF NOT EXISTS rules (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    category VARCHAR(50),
    points NUMERIC(10,2) DEFAULT 0,
    cash_cny NUMERIC(10,2) DEFAULT 0,
    description TEXT,
    owner_app_user_id VARCHAR(100),
    source_redline_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE rules ADD COLUMN IF NOT EXISTS owner_app_user_id VARCHAR(100);

ALTER TABLE rules ADD COLUMN IF NOT EXISTS source_redline_id INTEGER;

CREATE TABLE IF NOT EXISTS user_rule_templates (
    parent_app_user_id VARCHAR(100) PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS user_rule_template_items (
    parent_app_user_id VARCHAR(100) NOT NULL REFERENCES user_rule_templates(parent_app_user_id) ON DELETE CASCADE,
    rule_id INTEGER NOT NULL REFERENCES rules(id) ON DELETE CASCADE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (parent_app_user_id, rule_id)
);

CREATE TABLE IF NOT EXISTS watch_reward_requests (
    id SERIAL PRIMARY KEY,
    family_group_id INTEGER NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
    child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    rule_id INTEGER REFERENCES rules(id) ON DELETE SET NULL,
    title VARCHAR(120) NOT NULL,
    category VARCHAR(50),
    points NUMERIC(10,2) NOT NULL DEFAULT 0,
    note TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    requested_by VARCHAR(100),
    requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    review_note TEXT,
    transaction_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS redlines (
    id SERIAL PRIMARY KEY,
    order_num INTEGER,
    rule VARCHAR(200),
    proposer VARCHAR(50),
    description TEXT,
    penalty_points INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tx_child ON transactions(child_id);

CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date);

CREATE INDEX IF NOT EXISTS idx_tx_type ON transactions(type);

CREATE UNIQUE INDEX IF NOT EXISTS ux_tx_idempotency_key ON transactions(idempotency_key) WHERE idempotency_key IS NOT NULL AND idempotency_key <> '';

CREATE INDEX IF NOT EXISTS idx_rules_owner ON rules(owner_app_user_id);

CREATE UNIQUE INDEX IF NOT EXISTS ux_rules_source_redline ON rules(source_redline_id) WHERE source_redline_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_user_rule_template_items_order ON user_rule_template_items(parent_app_user_id, sort_order);

CREATE INDEX IF NOT EXISTS idx_children_family_group ON children(family_group_id);

CREATE INDEX IF NOT EXISTS idx_family_groups_created_by ON family_groups(created_by);

CREATE INDEX IF NOT EXISTS idx_family_group_users_user ON family_group_users(user_id);

CREATE INDEX IF NOT EXISTS idx_family_group_invites_code ON family_group_invites(invite_code) WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_app_user_profiles_unified ON app_user_profiles(unified_user_id);

CREATE INDEX IF NOT EXISTS idx_child_user_bindings_parent ON child_user_bindings(parent_app_user_id);

CREATE INDEX IF NOT EXISTS idx_child_user_bindings_child ON child_user_bindings(child_profile_key);

CREATE INDEX IF NOT EXISTS idx_household_members_owner ON household_members(owner_parent_app_user_id, created_at);

CREATE UNIQUE INDEX IF NOT EXISTS ux_household_members_current_user ON household_members(owner_parent_app_user_id) WHERE is_current_user;

CREATE INDEX IF NOT EXISTS idx_child_auth_codes_child ON child_auth_codes(child_id, expires_at DESC);

CREATE INDEX IF NOT EXISTS idx_watch_device_bindings_child ON watch_device_bindings(child_id, revoked_at);

CREATE INDEX IF NOT EXISTS idx_watch_device_bindings_parent ON watch_device_bindings(parent_app_user_id);

CREATE UNIQUE INDEX IF NOT EXISTS ux_watch_device_bindings_active_child ON watch_device_bindings(child_profile_key) WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_watch_device_unbind_codes_device ON watch_device_unbind_codes(device_binding_id, expires_at DESC);

CREATE INDEX IF NOT EXISTS idx_watch_reward_requests_family_child ON watch_reward_requests(family_group_id, child_id, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_watch_reward_requests_status ON watch_reward_requests(status);

CREATE INDEX IF NOT EXISTS idx_child_friend_codes_child ON child_friend_codes(child_profile_key, expires_at DESC);

CREATE INDEX IF NOT EXISTS idx_child_friendships_a ON child_friendships(child_profile_key_a);

CREATE INDEX IF NOT EXISTS idx_child_friendships_b ON child_friendships(child_profile_key_b);

CREATE INDEX IF NOT EXISTS idx_child_friend_notifications_parent ON child_friend_notifications(parent_app_user_id, read_at, created_at DESC);
