"""Export the actual installed route contract without requiring a database."""
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root))
from app.main import create_app  # noqa: E402
from app.config import Settings  # noqa: E402

schema = create_app(Settings(_env_file=None)).openapi()
target = root / "docs" / "openapi.json"
target.parent.mkdir(exist_ok=True)
target.write_text(json.dumps(schema, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
count = sum(len([m for m in item if m in {"get", "post", "put", "patch", "delete"}]) for item in schema["paths"].values())
print(f"Exported {len(schema['paths'])} paths / {count} operations to {target}")
