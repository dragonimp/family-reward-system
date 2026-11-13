CREATE TABLE dining_buddy_consents (
    owner_id text NOT NULL,
    buddy_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (owner_id, buddy_id),
    CHECK (owner_id <> buddy_id)
);
CREATE TABLE dining_circle_posts (
    id uuid PRIMARY KEY,
    author_id text NOT NULL,
    restaurant_id text NOT NULL,
    restaurant_name text NOT NULL,
    note text NOT NULL,
    visibility text NOT NULL CHECK (visibility IN ('private', 'buddies', 'selected')),
    selected_buddy_ids text[] NOT NULL DEFAULT '{}',
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX dining_circle_posts_author_created ON dining_circle_posts(author_id, created_at DESC);
CREATE TABLE dining_circle_actions (
    post_id uuid NOT NULL REFERENCES dining_circle_posts(id) ON DELETE CASCADE,
    user_id text NOT NULL,
    kind text NOT NULL CHECK (kind IN ('like', 'save', 'want')),
    PRIMARY KEY (post_id, user_id, kind)
);
CREATE TABLE dining_gathering_invitations (
    gathering_id uuid NOT NULL REFERENCES dining_gatherings(id),
    inviter_id text NOT NULL,
    invitee_id text NOT NULL,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined')),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (gathering_id, invitee_id),
    CHECK (inviter_id <> invitee_id)
);
CREATE INDEX dining_gathering_invitations_recipient ON dining_gathering_invitations(invitee_id, created_at DESC);
CREATE TABLE dining_circle_comments (
    id uuid PRIMARY KEY,
    post_id uuid NOT NULL REFERENCES dining_circle_posts(id) ON DELETE CASCADE,
    author_id text NOT NULL,
    body text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX dining_circle_comments_post_created ON dining_circle_comments(post_id, created_at DESC);
