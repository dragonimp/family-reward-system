ALTER TABLE genealogy_people
    ADD COLUMN gender VARCHAR(12) NOT NULL DEFAULT '' CHECK (gender IN ('', 'male', 'female', 'other')),
    ADD COLUMN birth_year SMALLINT,
    ADD COLUMN birth_month SMALLINT,
    ADD COLUMN birth_day SMALLINT,
    ADD CONSTRAINT ck_genealogy_birth_parts CHECK (
        (birth_year IS NULL OR birth_year BETWEEN 1 AND 9999)
        AND (birth_month IS NULL OR birth_year IS NOT NULL AND birth_month BETWEEN 1 AND 12)
        AND (CASE
            WHEN birth_day IS NULL THEN TRUE
            WHEN birth_year IS NULL OR birth_month IS NULL THEN FALSE
            WHEN birth_year NOT BETWEEN 1 AND 9999 OR birth_month NOT BETWEEN 1 AND 12 THEN FALSE
            ELSE birth_day BETWEEN 1 AND EXTRACT(DAY FROM
                make_date(birth_year, birth_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')
        END)
    );
