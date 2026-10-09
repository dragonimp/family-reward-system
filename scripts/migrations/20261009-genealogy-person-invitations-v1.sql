-- One-time, person-bound invitation records. Raw tokens are never stored.
-- Rollback: restore the pre-migration database backup if no invitations were issued;
-- otherwise revoke active invitations and retain the audit/history table.
CREATE TABLE genealogy_person_invitations (
    id BIGSERIAL PRIMARY KEY,
    tree_id BIGINT NOT NULL,
    person_id BIGINT NOT NULL,
    token_hash CHAR(64) NOT NULL UNIQUE,
    created_by VARCHAR(180) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    accepted_by VARCHAR(180),
    accepted_at TIMESTAMPTZ,
    FOREIGN KEY (tree_id, person_id) REFERENCES genealogy_people(tree_id, id) ON DELETE CASCADE,
    CHECK ((accepted_by IS NULL) = (accepted_at IS NULL))
);
CREATE INDEX idx_genealogy_person_invitations_person ON genealogy_person_invitations(tree_id, person_id, created_at DESC);
