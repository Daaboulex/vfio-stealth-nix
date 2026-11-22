''
  _stealth_die() {
    echo "[FAIL] $1"
    exit 1
  }

  anchor_count() {
    local n
    n=$(grep -cE -- "$2" "$1") || n=0
    printf '%s' "$n"
  }

  exactly_one() {
    local n
    n=$(anchor_count "$1" "$2")
    [ "$n" = 1 ] || _stealth_die "$3 -- expected exactly 1 match of /$2/ in $1, found $n. Re-aim this anchor before it edits the wrong place."
  }

  landed() {
    grep -qF -- "$2" "$1" || _stealth_die "$3 -- the edit did not apply to $1 (expected to find: $2). The upstream anchor moved; re-aim this edit."
    echo "[OK] $3"
  }

  gone() {
    local n
    n=$(grep -cF -- "$2" "$1") || n=0
    [ "$n" = 0 ] || _stealth_die "$3 -- the edit did not replace $n occurrence(s) in $1 (still present: $2). The upstream anchor moved; re-aim this edit."
    echo "[OK] $3"
  }

  landed_soft() {
    if grep -qF -- "$2" "$1"; then
      echo "[OK] $3"
    else
      echo "[WARN] $3 -- optional edit did not apply to $1"
    fi
  }
''
