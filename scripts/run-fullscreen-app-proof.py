"""Dedicated hosted-only app driver; capture from the runner, not the app."""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

assert os.environ.get("GITHUB_ACTIONS") == "true"
assert os.environ.get("OURO_NATIVE_PREFERENCE_PROOF") == "1"
root = Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=True)


def capture_arguments(request):
    destination = Path(request["destination"]).resolve()
    assert destination.is_relative_to(root)
    if request["kind"] == "window":
        assert str(request["window"]).isdigit()
        return ["-x", "-o", "-l", str(request["window"]), str(destination)]
    assert request["kind"] == "region"
    assert re.fullmatch(r"-?\d+,-?\d+,\d+,\d+", request["region"])
    return ["-x", "-R", request["region"], str(destination)]


# Exercise the protocol once before supervising the actual app requests.
assert capture_arguments({"kind": "window", "window": 42,
                          "destination": str(root / "smoke.png")}) == [
    "-x", "-o", "-l", "42", str(root / "smoke.png")]
application = subprocess.Popen([
    "/usr/bin/open", "-n", "-W",
    "--env", "GITHUB_ACTIONS=true", "--env", "OURO_FULLSCREEN_PROBE=1",
    "--env", f"OURO_FULLSCREEN_OUTPUT={root}",
    "--env", f"OURO_FULLSCREEN_INPUT={Path('.build/fullscreen-input.md').resolve()}",
    "--stdout", str(root / "app.stdout.log"), "--stderr", str(root / "app.stderr.log"),
    ".build/FullscreenProof.app",
])
last_request = None
owned_pid = None
try:
    deadline = time.monotonic() + 900
    while application.poll() is None:
        if time.monotonic() > deadline:
            raise TimeoutError("Actual fullscreen app did not finish")
        try:
            request = json.loads((root / "capture-request.json").read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            time.sleep(0.05)
            continue
        if request["id"] == last_request:
            time.sleep(0.05)
            continue
        owned_pid = int(request["pid"])
        result = subprocess.run(["/usr/sbin/screencapture", *capture_arguments(request)],
                                capture_output=True, text=True, timeout=30)
        response = {"id": request["id"], "status": result.returncode,
                    "stderr": result.stderr}
        (root / "capture-response.json").write_text(json.dumps(response))
        last_request = request["id"]
    rows = json.loads((root / "measurements.json").read_text())
    assert not any("error" in row for row in rows), rows[-1]
    assert len([row for row in rows if "state" in row]) == 24
finally:
    if application.poll() is None:
        if owned_pid is not None:
            try:
                os.kill(owned_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        application.terminate()
        application.wait(timeout=10)
