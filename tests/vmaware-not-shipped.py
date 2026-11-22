import pathlib
import re
import sys

DERIVATION = re.compile(rb"/nix/store/[0-9a-z]{32}-[0-9A-Za-z+._?=-]+\.drv")

toplevel, shipped, name = sys.argv[1:4]
seen = {toplevel}
pending = [toplevel]
while pending:
    for match in DERIVATION.findall(pathlib.Path(pending.pop()).read_bytes()):
        path = match.decode()
        if path not in seen:
            seen.add(path)
            pending.append(path)

if shipped not in seen:
    raise SystemExit(
        f"vmaware-not-shipped: the system's derivation closure lacks {shipped}, the QEMU it ships, so the walk proves nothing"
    )
named = re.compile(rf"/nix/store/[0-9a-z]{{32}}-{re.escape(name)}-[^/]*\.drv")
found = sorted(path for path in seen if named.fullmatch(path))
if found:
    raise SystemExit(
        f"vmaware-not-shipped: {found} is in the system's derivation closure, so VMAware reaches a shipped closure"
    )
print(f"vmaware-not-shipped: {len(seen)} derivations walked, none is {name}")
