#!/usr/bin/env python3
"""Isolated PostgreSQL + HTTP smoke test for bound-watch connection flows."""
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
DB = f"family_connection_test_{uuid.uuid4().hex[:12]}"
TOKEN = f"connection-test-{uuid.uuid4()}"
OTHER_TOKEN = f"connection-test-{uuid.uuid4()}"


def command(*args, env=None, input_text=None):
    return subprocess.run(args, cwd=ROOT, env=env, input=input_text, text=True, check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def sql(statement):
    return command("psql", "-X", "-v", "ON_ERROR_STOP=1", "-d", DB, "-c", statement)


def call(port, path, token=None, body=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["X-Watch-Device-Token"] = token
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}",
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers=headers, method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def main():
    command("createdb", DB)
    api = None
    try:
        with tempfile.TemporaryDirectory(prefix="family-connection-test-") as temp:
            backup = Path(temp) / "before.dump"
            pg_dump = "/opt/homebrew/opt/postgresql@18/bin/pg_dump"
            if not Path(pg_dump).exists():
                pg_dump = "pg_dump"
            command(pg_dump, "-d", DB, "-f", str(backup))
            env = os.environ.copy()
            env["FAMILY_REWARD_DB_DSN"] = f"dbname={DB}"
            env["FAMILY_REWARD_DB_BACKUP"] = str(backup)
            command("bash", "scripts/run-db-migrations.sh", "scripts/migrations", env=env)
            command("bash", "scripts/run-db-migrations.sh", "scripts/migrations", env=env)
            if command("psql", "-X", "-At", "-d", DB, "-c", "SELECT COUNT(*) FROM family_reward_schema_migrations").strip() != "3":
                raise AssertionError("migration did not record all three immutable IDs exactly once")
            sql("""
                INSERT INTO family_groups(id,name,created_by) VALUES (900001,'test-family','test-parent');
                INSERT INTO child_profiles(profile_key,name) VALUES ('test-child-a','A'),('test-child-b','B');
                INSERT INTO children(id,family_group_id,name,profile_key) VALUES
                  (900001,900001,'A','test-child-a'),(900002,900001,'B','test-child-b');
                INSERT INTO child_user_bindings(parent_app_user_id,child_profile_key,child_id) VALUES
                  ('test-parent','test-child-a',900001),('test-parent','test-child-b',900002);
            """)
            for child_id, key, token in ((900001, "test-child-a", TOKEN), (900002, "test-child-b", OTHER_TOKEN)):
                sql(f"""INSERT INTO watch_device_bindings(child_id,family_group_id,child_profile_key,parent_app_user_id,device_token_hash)
                        VALUES({child_id},900001,'{key}','test-parent','{hashlib.sha256(token.encode()).hexdigest()}')""")
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                port = sock.getsockname()[1]
            env["PGDATABASE"] = DB
            env["FAMILY_REWARD_API_URLS"] = f"http://127.0.0.1:{port}"
            env.pop("FAMILY_REWARD_DB_DSN", None)
            api = subprocess.Popen(["dotnet", "FamilyReward.Api/bin/Debug/net10.0/FamilyReward.Api.dll"],
                                   cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            for _ in range(80):
                try:
                    if call(port, "/health")[0] == 200:
                        break
                except OSError:
                    time.sleep(.2)
            else:
                raise AssertionError("API did not start: " + api.stderr.read().decode()[-1200:])
            assert call(port, "/api/watch/family-connections")[0] == 401
            assert call(port, "/api/family-connections")[0] == 401
            assert call(port, "/api/family-connections", body={"childId": 900001, "kind": "listen", "title": "unauthorized", "intent": "share", "requestId": str(uuid.uuid4())})[0] == 401
            for expected_count, kind in enumerate(("special_time", "listen", "reconnect", "meeting"), 1):
                body = {"kind": kind, "title": f"test {kind}", "intent": "comfort" if kind == "listen" else "",
                        "requestId": str(uuid.uuid4())}
                status, payload = call(port, "/api/watch/family-connections", TOKEN, body)
                assert status == 200, (kind, status, payload)
                assert len(payload["threads"]) == expected_count
                assert call(port, "/api/watch/family-connections", TOKEN, body)[0] == 200
                assert call(port, "/api/watch/family-connections", TOKEN, {**body, "title": "different title"})[0] == 409
                thread = next(row for row in payload["threads"] if row["kind"] == kind)
                assert call(port, f"/api/watch/family-connections/{thread['id']}/entries", OTHER_TOKEN,
                            {"type": "message", "content": "cross family", "requestId": str(uuid.uuid4())})[0] == 404
                entry_type = "feeling" if kind == "reconnect" else "proposal" if kind == "meeting" else "message"
                assert call(port, f"/api/watch/family-connections/{thread['id']}/entries", TOKEN,
                            {"type": entry_type, "content": "my thought", "requestId": str(uuid.uuid4())})[0] == 200
            assert len(call(port, "/api/watch/family-connections", OTHER_TOKEN)[1]["threads"]) == 0
            sql("UPDATE watch_device_bindings SET revoked_at=CURRENT_TIMESTAMP WHERE child_profile_key='test-child-a'")
            assert call(port, "/api/watch/family-connections", TOKEN)[0] == 401
            print("PASS: migrations repeat safely; four kinds; parent/watch authentication, idempotency, child isolation and revocation")
    finally:
        if api is not None:
            api.terminate()
            api.wait(timeout=10)
        command("dropdb", DB)


if __name__ == "__main__":
    main()
