-- Private genealogy spaces are separate from reward circles and household notes.
-- Rollback before use: drop the four genealogy tables in dependency order.
-- After user content exists, preserve it and use a new corrective migration.
CREATE TABLE genealogy_trees (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    surname VARCHAR(30) NOT NULL DEFAULT '',
    description VARCHAR(500) NOT NULL DEFAULT '',
    created_by VARCHAR(180) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE genealogy_tree_users (
    tree_id BIGINT NOT NULL REFERENCES genealogy_trees(id) ON DELETE CASCADE,
    app_user_id VARCHAR(180) NOT NULL,
    role VARCHAR(12) NOT NULL CHECK (role IN ('owner', 'member')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (tree_id, app_user_id)
);
CREATE INDEX idx_genealogy_tree_users_user ON genealogy_tree_users(app_user_id, tree_id);

CREATE TABLE genealogy_people (
    id BIGSERIAL PRIMARY KEY,
    tree_id BIGINT NOT NULL REFERENCES genealogy_trees(id) ON DELETE CASCADE,
    display_name VARCHAR(80) NOT NULL,
    generation_label VARCHAR(40) NOT NULL DEFAULT '',
    branch_name VARCHAR(80) NOT NULL DEFAULT '',
    note VARCHAR(500) NOT NULL DEFAULT '',
    claimed_by VARCHAR(180),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tree_id, id)
);
CREATE UNIQUE INDEX ux_genealogy_people_claim ON genealogy_people(tree_id, claimed_by) WHERE claimed_by IS NOT NULL;
CREATE INDEX idx_genealogy_people_name ON genealogy_people(tree_id, lower(display_name));

CREATE TABLE genealogy_relationships (
    id BIGSERIAL PRIMARY KEY,
    tree_id BIGINT NOT NULL REFERENCES genealogy_trees(id) ON DELETE CASCADE,
    from_person_id BIGINT NOT NULL,
    to_person_id BIGINT NOT NULL,
    kind VARCHAR(12) NOT NULL CHECK (kind IN ('parent', 'spouse')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (from_person_id <> to_person_id),
    CHECK (kind <> 'spouse' OR from_person_id < to_person_id),
    UNIQUE (tree_id, from_person_id, to_person_id, kind),
    FOREIGN KEY (tree_id, from_person_id) REFERENCES genealogy_people(tree_id, id) ON DELETE CASCADE,
    FOREIGN KEY (tree_id, to_person_id) REFERENCES genealogy_people(tree_id, id) ON DELETE CASCADE
);
CREATE INDEX idx_genealogy_relationships_to ON genealogy_relationships(tree_id, to_person_id);

CREATE TABLE genealogy_join_requests (
    id BIGSERIAL PRIMARY KEY,
    tree_id BIGINT NOT NULL REFERENCES genealogy_trees(id) ON DELETE CASCADE,
    app_user_id VARCHAR(180) NOT NULL,
    account_name VARCHAR(160) NOT NULL,
    display_name VARCHAR(80) NOT NULL,
    message VARCHAR(300) NOT NULL DEFAULT '',
    status VARCHAR(12) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    decided_by VARCHAR(180),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    decided_at TIMESTAMPTZ,
    UNIQUE (tree_id, id)
);
CREATE UNIQUE INDEX ux_genealogy_pending_request ON genealogy_join_requests(tree_id, app_user_id) WHERE status = 'pending';
CREATE INDEX idx_genealogy_requests_tree_status ON genealogy_join_requests(tree_id, status, created_at);
