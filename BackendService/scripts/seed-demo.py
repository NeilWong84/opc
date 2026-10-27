"""Run from BackendService: .venv/Scripts/python.exe scripts/seed-demo.py."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.demo_seed import main  # noqa: E402

if __name__ == "__main__":
    main()
