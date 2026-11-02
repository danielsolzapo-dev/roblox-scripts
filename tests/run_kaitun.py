"""Run policy and mocked lifecycle with an official Luau CLI; no Roblox execution."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
subprocess.run([sys.executable, str(root / "scripts/sync_kaitun.py"), "--check"], check=True)
subprocess.run([luau, str(root / "tests/kaitun_planner.luau")], check=True)
text = (root / "RobloxUILibrary/Standalone.client.luau").read_text()
start = text.index("    local function initKaitun()")
end = text.index("    local kaitun=initKaitun()", start)
fixture = (root / "tests/kaitun_lifecycle.luau").read_text()
fixture = fixture.replace("-- INSERT ACTUAL COORDINATOR", text[start:end])
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "kaitun_lifecycle.luau"
    path.write_text(fixture)
    subprocess.run([luau, str(path)], check=True)
