"""Every lucide icon the hub and the lib name must be on the qustah sheet (else it shows as an old line icon).

    python3 tests/icons_check.py HUB.lua LIB_ROOT     (LIB_ROOT: the qustah-ui-lib folder)

Any quoted string that is a lucide icon name counts, so icons passed through helpers (category(..., "user-round"))
are found too.
"""
import glob, os, re, sys

hub, lib = sys.argv[1], sys.argv[2]
lucide = set(re.findall(r'"([a-z0-9\-]+)",\d+', open(os.path.join(lib, "src", "icons_lucide.lua")).read()))
sheet = set(re.search(r'Names = "([^"]*)"', open(os.path.join(lib, "src", "icons_qustah.lua")).read()).group(1).split(","))


def names(path):
    return {s for s in re.findall(r'"([a-z][a-z0-9\-]*)"', open(path).read()) if s in lucide}


sources = {"hub": names(hub), "lib": set()}
for f in glob.glob(os.path.join(lib, "src", "*.lua")) + glob.glob(os.path.join(lib, "src", "elements", "*.lua")):
    if not os.path.basename(f).startswith("icons_"):
        sources["lib"] |= names(f)
failed = 0
for where, used in sources.items():
    missing = sorted(used - sheet)
    if missing:
        failed += len(missing)
        print(f"  FAIL {where}: not on the qustah sheet (line icons): {', '.join(missing)}")
print(f"[icons] {sum(len(u) for u in sources.values()) - failed} on the sheet, {failed} missing")
sys.exit(1 if failed else 0)
