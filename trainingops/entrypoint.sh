#!/usr/bin/env sh
set -eu

# Wait for MySQL (using PyMySQL - already in requirements)
python - <<'PY'
import os, time, urllib.parse
import pymysql

url = os.environ.get("DATABASE_URL", "").strip()
if not url:
    raise SystemExit("DATABASE_URL missing")

# SQLAlchemy style: mysql+pymysql://user:pass@host:port/db?params
if url.startswith("mysql+pymysql://"):
    url2 = "mysql://" + url[len("mysql+pymysql://"):]
else:
    url2 = url

p = urllib.parse.urlparse(url2)
host = p.hostname or "mysql"
port = p.port or 3306
user = urllib.parse.unquote(p.username or "root")
password = urllib.parse.unquote(p.password or "")
db = (p.path or "").lstrip("/") or None

deadline = time.time() + 120
last_err = None
while time.time() < deadline:
    try:
        conn = pymysql.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            database=db,
            connect_timeout=3,
            read_timeout=3,
            write_timeout=3,
        )
        conn.close()
        print("MySQL is reachable.")
        break
    except Exception as e:
        last_err = e
        print(f"Waiting for MySQL at {host}:{port} ({type(e).__name__}: {e})")
        time.sleep(2)
else:
    raise SystemExit(f"MySQL not reachable: {last_err}")
PY

# Initialize DB schema + seed (idempotent)
python manage.py init-db || true

# Start app
exec gunicorn -w 4 -b 0.0.0.0:8000 "wsgi:app" --access-logfile - --error-logfile - --capture-output
