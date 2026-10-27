"""Load the application database secret only at process start, never in image layers."""
import os
import sys
from pathlib import Path
from urllib.parse import quote

password = Path('/run/secrets/pg-app').read_text().strip()
host = os.environ.get('OPC_PG_HOST', 'postgres')
name = os.environ.get('OPC_PG_DATABASE', 'opc_test')
os.environ['OPC_DATABASE_URL'] = f'postgresql://opc_app:{quote(password, safe="")}@{host}:5432/{name}'
os.execvp(sys.argv[1], sys.argv[1:])
