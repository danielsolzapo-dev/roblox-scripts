"""Run policy and mocked lifecycle with an official Luau CLI; no Roblox execution."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
compiler = sys.argv[2] if len(sys.argv) > 2 else str(Path(luau).with_name("luau-compile"))
for optimization in ("-O0", "-O1"):
    result = subprocess.run(
        [compiler, optimization, "--null", str(root / "RobloxUILibrary/Standalone.client.luau")],
        capture_output=True, text=True,
    )
    if result.returncode or "CompileError" in result.stderr or "SyntaxError" in result.stderr:
        raise SystemExit(result.stdout + result.stderr)
    print("Standalone compilation passed: " + optimization)
subprocess.run([sys.executable, str(root / "scripts/sync_kaitun.py"), "--check"], check=True)
subprocess.run([luau, str(root / "tests/kaitun_planner.luau")], check=True)
text = (root / "RobloxUILibrary/Standalone.client.luau").read_text()
start = text.index("    function kaitunRuntime.Init()")
end = text.index("    kaitunRuntime.API=kaitunRuntime.Init()", start)
fixture = (root / "tests/kaitun_lifecycle.luau").read_text()
fixture = fixture.replace("-- INSERT ACTUAL COORDINATOR", text[start:end])
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "kaitun_lifecycle.luau"
    path.write_text(fixture)
    subprocess.run([luau, str(path)], check=True)
