import codecs
import pathlib
import re
import sys

raw = pathlib.Path(sys.argv[1]).read_bytes()
if raw.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
    text = raw.decode("utf-16")
else:
    text = raw.decode("utf-8-sig", errors="replace")

section = None
for line in text.splitlines():
    line = line.strip()
    heading = re.fullmatch(r"\[(.+)\]", line)
    if heading:
        section = heading.group(1).strip().lower()
        continue
    language = re.fullmatch(r"([A-Za-z]{2,3}(?:-[A-Za-z0-9]+)+)\s*=.*", line)
    if section == "available ui languages" and language:
        print(language.group(1))
        sys.exit(0)

sys.exit(
    f"sources/lang.ini of the installer ISO names no language under [Available UI Languages]; it reads: {text!r}"
)
