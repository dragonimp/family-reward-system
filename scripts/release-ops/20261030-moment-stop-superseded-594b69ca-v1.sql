-- Scope: only the superseded old-identity TestFlight attempt from this task.
-- Backup and transaction/checksum receipt: atlas-apply-sql-migration.py.
-- Rollback: new explicit operation after confirming user intent; never reset/replay this upload.
CREATE TEMP TABLE moment_stop_guard (ok INTEGER CHECK (ok = 1));
INSERT INTO moment_stop_guard SELECT count(*) FROM apple_publishing_attempts
WHERE lower(id) = '594b69ca-bad3-4387-a60b-483cbdf30827'
  AND lower(app_id) = 'e79872cf-01de-5209-a591-32465da15155'
  AND bundle_id = 'net.impx.happylife.parent' AND version = '1.2.57' AND build_number = '66'
  AND artifact_sha256 = '369b52532d39b1eedbf84bfd4bdd67d8fd75646e7cd5736591b58aa751505bf3'
  AND status IN ('upload_pending', 'apple_processing');
UPDATE apple_publishing_attempts SET status = 'cancelled',
  error_code = 'Superseded by user instruction: publish new application ID within the same Atlas project; do not distribute this old-ID build.',
  updatedat = strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE lower(id) = '594b69ca-bad3-4387-a60b-483cbdf30827';
DROP TABLE moment_stop_guard;
