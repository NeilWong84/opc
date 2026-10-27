"""Collect actual cloud APP screens on an explicitly selected disposable emulator.

Credentials stay in memory; only non-login screenshots are retained. This tool
does not submit requirements, accept terms, or change project business data.
"""
from pathlib import Path
import json
import os
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / 'Website/test_artifacts/android'
TARGET.mkdir(parents=True, exist_ok=True)
SERIAL = 'emulator-5570'


def adb(*args):
    return subprocess.run(['adb', '-s', SERIAL, *args], check=True, capture_output=True).stdout


def tap(x, y):
    adb('shell', 'input', 'tap', str(x), str(y))
    time.sleep(0.6)


def tree():
    adb('shell', 'uiautomator', 'dump', '/sdcard/opc-website.xml')
    return ET.fromstring(adb('shell', 'cat', '/sdcard/opc-website.xml'))


def snapshot(name):
    (TARGET / (name + '.png')).write_bytes(adb('exec-out', 'screencap', '-p'))
    (TARGET / (name + '.xml')).write_bytes(ET.tostring(tree()))
    print('Captured ' + name)


if __name__ == '__main__':
    adb('shell', 'input', 'keyevent', '224')
    adb('shell', 'wm', 'dismiss-keyguard')
    adb('shell', 'settings', 'put', 'system', 'screen_off_timeout', '1800000')
    credentials = json.loads((ROOT / 'BackendService/.local/demo-credentials.json').read_text(encoding='utf-8-sig'))['accounts']['customer']
    # Locate fields on the login screen, never dump their values after input.
    fields = [n for n in tree().iter('node') if n.get('class') == 'android.widget.EditText']
    if len(fields) != 2:
        raise SystemExit('Expected an untouched login screen on the disposable emulator')
    import re
    for index, value in enumerate((credentials['email'], credentials['password'])):
        fields = [n for n in tree().iter('node') if n.get('class') == 'android.widget.EditText']
        field = fields[index]
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', field.get('bounds')))
        tap((x1 + x2)//2, (y1+y2)//2)
        adb('shell', 'input', 'keyevent', '123')
        adb('shell', 'input', 'keyevent', *(['67']*100))
        adb('shell', 'input', 'text', value)
        adb('shell', 'input', 'keyevent', '4')
        time.sleep(0.8)
    tap(500, 1650)
    time.sleep(6)
    snapshot('zh-home')
