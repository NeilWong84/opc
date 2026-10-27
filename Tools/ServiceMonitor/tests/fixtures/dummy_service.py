from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--message", default="ready")
    parser.add_argument("--spawn-child", action="store_true")
    parser.add_argument("--child", action="store_true")
    args = parser.parse_args()
    if args.child:
        print("child-ready", flush=True)
        while True:
            time.sleep(0.1)
    child = None
    if args.spawn_child:
        child = subprocess.Popen([sys.executable, __file__, "--child"])
        print(f"child_pid={child.pid}", flush=True)
    print(f"cwd={os.getcwd()}", flush=True)
    print(f"env={os.environ.get('DUMMY_VISIBLE', '')}", flush=True)
    print(args.message, flush=True)
    while True:
        time.sleep(0.1)


if __name__ == "__main__":
    main()

