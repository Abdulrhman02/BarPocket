from pathlib import Path
import subprocess
import platform
import tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='barpocket-image-test-') as folder:
    binary=Path(folder)/'test'
    subprocess.run(['xcrun','swiftc','-target',f'{platform.machine()}-apple-macosx14.0','-framework','AppKit','-framework','ScreenCaptureKit',str(root/'IconSnapshots.swift'),str(root/'Tests/IconSnapshots/main.swift'),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
