import hashlib
import argparse
import os
from pathlib import Path
import re
import subprocess
import shutil
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ADB = os.environ.get('OPC_ADB') or shutil.which('adb') or 'adb'
arguments = argparse.ArgumentParser(description='Only save uniquely named OPC preview verification fixtures.')
arguments.add_argument('--device', required=True)
device = arguments.parse_args().device

def adb(*args):
    return subprocess.run([ADB, '-s', device, *args], capture_output=True, timeout=15)

deadline = time.monotonic() + 300
while time.monotonic() < deadline:
    adb('shell', 'uiautomator', 'dump', '/data/local/tmp/opc-validation-save.xml')
    response = adb('shell', 'cat', '/data/local/tmp/opc-validation-save.xml')
    try:
        nodes = list(ET.fromstring(response.stdout).iter('node'))
    except ET.ParseError:
        time.sleep(1)
        continue
    filename = next((n.get('text') for n in nodes if re.fullmatch(r'OPC-preview-validation-\d+\.pdf', n.get('text', ''))), None)
    button = next((n for n in nodes if n.get('text') in ('SAVE', '保存', '保存する') and n.get('enabled') == 'true'), None)
    if filename and button is not None:
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', button.get('bounds')))
        adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
        original = (ROOT/'assets/references/workflow.pdf').read_bytes()
        target = ROOT/'test_artifacts'/filename
        for _ in range(30):
            time.sleep(1)
            result = adb('pull', '/sdcard/Download/'+filename, str(target))
            if result.returncode == 0 and target.is_file() and target.stat().st_size == len(original):
                same = hashlib.sha256(original).digest() == hashlib.sha256(target.read_bytes()).digest()
                print('PHONE_FILE_SHA256_MATCH='+str(same), 'bytes='+str(len(original)), flush=True)
                raise SystemExit(0 if same else 1)
        raise SystemExit('Phone export did not complete')
    time.sleep(1)
raise SystemExit('Expected OPC validation save chooser not found')
