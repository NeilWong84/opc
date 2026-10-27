from contextlib import contextmanager
import psycopg
from psycopg.rows import dict_row


class Database:
    """One short transaction per request. Never silently fall back to a mock database."""

    def __init__(self, url: str):
        self.url = url

    @contextmanager
    def transaction(self, correlation_id: str = ""):
        with psycopg.connect(self.url, row_factory=dict_row, connect_timeout=3) as conn:
            conn.execute("SET LOCAL statement_timeout = '15s'")
            conn.execute("SET LOCAL lock_timeout = '5s'")
            conn.execute("SET LOCAL timezone = 'UTC'")
            conn.execute("SELECT set_config('opc.correlation_id', %s, true)", (correlation_id,))
            yield conn
