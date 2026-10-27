"""Reject integration-test entrypoints and test credentials in a normal debug APK."""
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--test-defines", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    # Debug kernels embed SDK source comments. A broad "package:flutter_test/"
    # search falsely matches Flutter's @docImport examples in ordinary SDK files.
    # Check actual test implementation URIs and our concrete test entrypoints.
    markers = [b"package:integration_test/", b"package:flutter_test/src/", b"flutter_test/lib/src/binding.dart",
               b"IntegrationTestWidgetsFlutterBinding", b"provider_claim_flow_test.dart",
               b"real_api_smoke_test.dart", b"OPC_E2E_ADMIN_TOKEN"]
    if args.test_defines:
        config = json.loads(args.test_defines.read_text(encoding="utf-8"))
        markers.extend(str(value).encode() for key, value in config.items()
                       if key.startswith("OPC_E2E_") and isinstance(value, str) and value)
    with ZipFile(args.apk) as archive:
        kernel = archive.read("assets/flutter_assets/kernel_blob.bin")
        if any(marker in kernel for marker in markers):
            raise SystemExit("REJECTED: APK contains an integration entrypoint or test credentials")
        if b"package:opc_app/main.dart" not in kernel:
            raise SystemExit("REJECTED: ordinary application entrypoint not found")
    with args.apk.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    result = {"apk": str(args.apk.resolve()), "size": args.apk.stat().st_size,
              "sha256": digest,
              "normal_entrypoint": True, "test_markers_absent": True}
    if args.output:
        args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
