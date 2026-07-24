{ runCommand }:

runCommand "options-documented" { } ''
  module=${../module.nix}
  optionsDoc=${../docs/OPTIONS.md}

  missing=""
  for name in $(grep -oE '^[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]* = lib\.(mkOption|mkEnableOption)' \
    "$module" | awk '{ print $1 }' | sort -u); do
    grep -qF -- "$name" "$optionsDoc" || missing="$missing $name"
  done

  if [ -n "$missing" ]; then
    echo "::error::docs/OPTIONS.md does not mention:$missing"
    echo "Every myModules.vfio.stealth option must be documented; add a row for each."
    exit 1
  fi

  echo "options-documented: every module option appears in docs/OPTIONS.md"
  touch $out
''
