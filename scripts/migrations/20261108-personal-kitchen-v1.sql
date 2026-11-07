-- Independent once-only migration. No application-start DDL or seed.
CREATE TABLE kitchen_personal_media (
 id UUID PRIMARY KEY, owner_id TEXT NOT NULL, purpose TEXT NOT NULL CHECK(purpose IN ('recipe','checkin')),
 mime TEXT NOT NULL CHECK(mime='image/jpeg'), content BYTEA NOT NULL CHECK(octet_length(content) BETWEEN 4 AND 8388608),
 sha256 CHAR(64) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(id,owner_id));
CREATE TABLE kitchen_personal_recipes (
 id UUID PRIMARY KEY, owner_id TEXT NOT NULL, body JSONB NOT NULL, original_media_id UUID,
 recognition_id UUID, source_text TEXT NOT NULL DEFAULT '', ai_result JSONB,
 version INTEGER NOT NULL DEFAULT 1, contribution_allowed BOOLEAN NOT NULL DEFAULT false,
 contribution_authorization JSONB NOT NULL DEFAULT '{}'::jsonb, review_state TEXT NOT NULL DEFAULT 'private',
 sync_state TEXT NOT NULL DEFAULT 'not_requested', created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), deleted_at TIMESTAMPTZ, UNIQUE(id,owner_id),
 FOREIGN KEY(original_media_id,owner_id) REFERENCES kitchen_personal_media(id,owner_id));
CREATE INDEX kitchen_personal_recipes_owner ON kitchen_personal_recipes(owner_id,updated_at DESC) WHERE deleted_at IS NULL;
CREATE TABLE kitchen_user_recipes (
 owner_id TEXT NOT NULL, recipe_id UUID NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('public','private')),
 favorite BOOLEAN NOT NULL DEFAULT false, starred BOOLEAN NOT NULL DEFAULT false,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(owner_id,recipe_id));
CREATE TABLE kitchen_cooking_checkins (
 id UUID PRIMARY KEY, owner_id TEXT NOT NULL, recipe_id UUID, kind TEXT CHECK(kind IN ('public','private')),
 cooked_on DATE NOT NULL, media_id UUID NOT NULL, note TEXT NOT NULL DEFAULT '', recipe_name TEXT NOT NULL DEFAULT '',
 request_hash CHAR(64) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), deleted_at TIMESTAMPTZ,
 FOREIGN KEY(media_id,owner_id) REFERENCES kitchen_personal_media(id,owner_id),
 CHECK((recipe_id IS NULL AND kind IS NULL) OR (recipe_id IS NOT NULL AND kind IS NOT NULL)));
CREATE INDEX kitchen_cooking_checkins_owner ON kitchen_cooking_checkins(owner_id,recipe_id,cooked_on DESC) WHERE deleted_at IS NULL;
CREATE TABLE kitchen_recognition_tasks (
 id UUID PRIMARY KEY, owner_id TEXT NOT NULL, username TEXT NOT NULL, media_id UUID NOT NULL,
 state TEXT NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','running','completed','failed')),
 result JSONB, error TEXT NOT NULL DEFAULT '', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 FOREIGN KEY(media_id,owner_id) REFERENCES kitchen_personal_media(id,owner_id));
CREATE INDEX kitchen_recognition_queue ON kitchen_recognition_tasks(created_at) WHERE state='queued';
