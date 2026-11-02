"""Keep the standalone policy identical to its independently tested source."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
source = (root / "RobloxUILibrary/KaitunPlanner.luau").read_text().strip()
path = root / "RobloxUILibrary/Standalone.client.luau"
text = path.read_text()
begin = "        -- BEGIN GENERATED KAITUN POLICY\n"
end = "        -- END GENERATED KAITUN POLICY"
start = text.index(begin) + len(begin)
finish = text.index(end, start)
body = "        local choose = (function()\n" + "\n".join("            " + line for line in source.splitlines()) + "\n        end)()\n"
updated = text[:start] + body + text[finish:]
if "--check" in sys.argv:
    if updated != text:
        raise SystemExit("Kaitun policy is out of sync")
    print("Kaitun policy synchronized")
else:
    path.write_text(updated)
