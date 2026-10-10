ALTER TABLE household_members
    ADD CONSTRAINT uq_household_members_owner_id UNIQUE (owner_parent_app_user_id, id);

CREATE TABLE household_genealogy_links (
    owner_parent_app_user_id VARCHAR(180) NOT NULL,
    household_member_id INTEGER NOT NULL,
    tree_id BIGINT NOT NULL,
    person_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (household_member_id, tree_id),
    UNIQUE (owner_parent_app_user_id, tree_id, person_id),
    FOREIGN KEY (owner_parent_app_user_id, household_member_id)
        REFERENCES household_members(owner_parent_app_user_id, id) ON DELETE CASCADE,
    FOREIGN KEY (tree_id, person_id)
        REFERENCES genealogy_people(tree_id, id) ON DELETE CASCADE
);
CREATE INDEX idx_household_genealogy_links_owner ON household_genealogy_links(owner_parent_app_user_id, tree_id);
