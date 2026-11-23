"""Three SQLAlchemy connection pools that reach PostgreSQL through a
proxy with a TCP idle timeout. Each pool runs a query, waits longer than
the idle timeout, and runs a second query. The query returns the process
ID of the PostgreSQL backend, so a new ID means a new connection.

Usage: python3 db_pool.py [database URL] [wait in seconds]
"""
import sys
import time

from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError

URL = (sys.argv[1] if len(sys.argv) > 1 else
       "postgresql+psycopg://shop:lab-only-password@127.0.0.1:15433/shop")
WAIT = float(sys.argv[2]) if len(sys.argv) > 2 else 4.0

POOLS = {
    "defaults": {},                                             # (1)
    "pool_pre_ping=True": {"pool_pre_ping": True},              # (2)
    "pool_recycle=2": {"pool_recycle": 2},                      # (3)
}


def backend_pid(engine):
    with engine.connect() as conn:
        return conn.execute(text("select pg_backend_pid()")).scalar()


for name, options in POOLS.items():
    engine = create_engine(URL, pool_size=1, **options)
    first = backend_pid(engine)
    time.sleep(WAIT)
    try:
        result = f"backend {first}, then backend {backend_pid(engine)}"
    except OperationalError as exc:                             # (4)
        result = "error: " + str(exc.orig).strip().splitlines()[0]
    print(f"{name:19} {result}")
    engine.dispose()
