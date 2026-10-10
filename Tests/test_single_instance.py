"""Compile the production lock and verify cross-process exclusion and recovery."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temp:
    executable = str(pathlib.Path(temp) / 'lock-check')
    subprocess.run(['xcrun', 'swiftc', str(root / 'SingleInstance.swift'),
                    str(root / 'Tests/SingleInstance/main.swift'), '-o', executable], check=True)
    directory = str(pathlib.Path(temp) / 'application-support')
    first = subprocess.Popen([executable, directory, '20'], stdout=subprocess.PIPE, text=True)
    try:
        assert first.stdout.readline().strip() == 'acquired'
        second = subprocess.run([executable, directory, '0'], capture_output=True, text=True, timeout=5)
        assert second.returncode == 2 and second.stdout.strip() == 'busy', second
    finally:
        first.terminate()
        first.wait(timeout=5)
    restart = subprocess.run([executable, directory, '0'], capture_output=True, text=True, timeout=5)
    assert restart.returncode == 0 and restart.stdout.strip() == 'acquired', restart
    print('PASS: duplicate excluded; termination releases lock; restart succeeds.')
