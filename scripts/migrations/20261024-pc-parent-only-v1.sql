-- One-time conversion of legacy PC child selections to parent profiles.
-- Precondition: only the pc channel is changed; watch profiles and child bindings remain intact.
-- Before execution: back up the database and review SELECT id, unified_user_id, username,
-- app_user_id, child_profile_key, child_id FROM app_user_profiles WHERE channel = 'pc' AND role = 'child'.
-- Recovery: restore the backup before new writes, or use a new audited corrective migration.
DO $migration$
BEGIN
    IF EXISTS (SELECT 1 FROM app_user_profiles WHERE channel = 'pc' AND role = 'child'
               AND (username IS NULL OR trim(username) = '')) THEN
        RAISE EXCEPTION 'PC child profile with missing username';
    END IF;

    UPDATE app_user_profiles
    SET role = 'parent',
        app_user_id = regexp_replace(trim(username), '[[:space:]]+', '', 'g') || 'parent',
        child_profile_key = NULL,
        child_id = NULL,
        updated_at = CURRENT_TIMESTAMP
    WHERE channel = 'pc' AND role = 'child';
END
$migration$;
