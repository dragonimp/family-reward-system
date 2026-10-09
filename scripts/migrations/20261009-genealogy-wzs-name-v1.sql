-- One-time correction requested by the owner of the 翁氏家族 genealogy.
-- Preconditions are deliberately exact; an unexpected record must stop the deployment.
-- Recovery: restore the pre-migration backup, or add a new audited corrective migration.
DO $migration$
BEGIN
    IF (SELECT count(*) FROM genealogy_people
        WHERE id = 1 AND tree_id = 1 AND claimed_by = 'wzsparent' AND display_name = 'wzs') <> 1 THEN
        RAISE EXCEPTION 'Expected genealogy person 1 in tree 1 with the original wzs name';
    END IF;

    UPDATE genealogy_people
    SET display_name = '翁志山', updated_at = CURRENT_TIMESTAMP
    WHERE id = 1 AND tree_id = 1 AND claimed_by = 'wzsparent' AND display_name = 'wzs';
END
$migration$;
