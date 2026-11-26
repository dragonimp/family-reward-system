ALTER TABLE kitchen_recognition_tasks
    ADD COLUMN task_kind text NOT NULL DEFAULT 'recipe'
    CHECK (task_kind IN ('recipe', 'beverage'));
