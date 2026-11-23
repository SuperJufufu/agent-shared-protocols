#!/usr/bin/env sh
# claim.sh — 建议性认领表，配合 single-writer-shared-data 使用。
# 只依赖 POSIX sh + coreutils（date 的 GNU/BSD 差异自动探测）。
set -u

prog=$(basename "$0")
die() { printf '%s: %s\n' "$prog" "$*" >&2; exit 5; }

usage() {
  cat <<EOF
usage:
  $prog list    <contract.md>
  $prog check   <contract.md> <target>
  $prog claim   <contract.md> <target> --agent <name> [--ttl <minutes>] [--note <text>]
  $prog release <contract.md> <target> [--agent <name>]
  $prog reap    <contract.md> [--dry-run]

  target 形如 'shared/state.md#端口'
  exit: 0 ok · 3 no matching claim · 4 occupied · 5 usage/contract error
EOF
}

frontmatter() {
  awk 'NR == 1 { if ($0 !~ /^---[ \t]*$/) exit 1; next }
            /^---[ \t]*$/ { exit 0 }
            { print }' "$1"
}

field() {
  frontmatter "$1" | awk -v k="$2" '
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      print v; exit
    }'
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

plus_minutes() {
  if date -u -d "+$1 minutes" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; then
    :
  else
    date -u -v+"$1"M +%Y-%m-%dT%H:%M:%SZ
  fi
}

claim_file=""
load_contract() {
  [ -f "$1" ] || die "contract not found: $1"
  cdir=$(cd "$(dirname "$1")" && pwd)
  rel=$(field "$1" claim_file)
  [ -n "$rel" ] || die "no claim_file in $1"
  case "$rel" in
    /*) claim_file=$rel ;;
    *)  claim_file=$cdir/$rel ;;
  esac
  [ -f "$claim_file" ] || die "claim file missing: $claim_file"
}

cmd_list() {
  load_contract "$1"
  awk '/^[ \t]*\|/ { print }' "$claim_file"
}

cmd_check() {
  load_contract "$1"
  target=$2
  now=$(now_utc)
  awk -F'|' -v t="$target" -v now="$now" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*\|/ {
      a = trim($2); b = trim($3); e = trim($5)
      if (a == "" || a == "agent" || a ~ /^-+$/) next
      if (b == t && e > now) { printf "occupied by %s (until %s)\n", a, e; hit = 1 }
    }
    END { exit hit ? 4 : 0 }' "$claim_file"
}

cmd_claim() {
  contract=$1; target=$2; shift 2
  agent=""; ttl=30; note="-"
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) [ $# -ge 2 ] || die "--agent needs a value"; agent=$2; shift 2 ;;
      --ttl)   [ $# -ge 2 ] || die "--ttl needs a value";   ttl=$2;   shift 2 ;;
      --note)  [ $# -ge 2 ] || die "--note needs a value";  note=$2;  shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  [ -n "$agent" ] || die "claim needs --agent <name>"
  case "$ttl" in ''|*[!0-9]*) die "--ttl must be a whole number of minutes" ;; esac
  case "$note" in *'|'*) die "note must not contain a '|' character" ;; esac

  load_contract "$contract"

  if ! cmd_check "$contract" "$target"; then
    printf 'refusing to claim: target is held\n' >&2
    exit 4
  fi

  start=$(now_utc)
  exp=$(plus_minutes "$ttl")
  # 表末尾必须有换行，否则追加会粘到最后一行
  if [ -n "$(tail -c 1 "$claim_file" 2>/dev/null)" ]; then
    printf '\n' >> "$claim_file"
  fi
  printf '| %s | %s | %s | %s | %s |\n' "$agent" "$target" "$start" "$exp" "$note" >> "$claim_file"
  printf 'claimed %s by %s until %s\n' "$target" "$agent" "$exp"
}

cmd_release() {
  contract=$1; target=$2; shift 2
  agent=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) [ $# -ge 2 ] || die "--agent needs a value"; agent=$2; shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  load_contract "$contract"
  tmp="$claim_file.tmp.$$"
  awk -F'|' -v t="$target" -v ag="$agent" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      drop = 0
      if ($0 ~ /^[ \t]*\|/) {
        a = trim($2); b = trim($3)
        if (b == t && (ag == "" || a == ag) && a != "agent" && a !~ /^-+$/) drop = 1
      }
      if (drop) { printf "released %s (was held by %s)\n", t, a > "/dev/stderr"; n++; next }
      print
    }
    END { exit n ? 0 : 3 }' "$claim_file" > "$tmp"

  if [ $? -ne 0 ]; then
    rm -f "$tmp"
    printf '%s: no matching claim for %s\n' "$prog" "$target" >&2
    exit 3
  fi
  mv "$tmp" "$claim_file"
}

cmd_reap() {
  contract=$1; shift
  dry=0
  if [ "${1:-}" = "--dry-run" ]; then dry=1; shift; fi
  [ $# -eq 0 ] || die "reap takes only --dry-run"

  load_contract "$contract"
  now=$(now_utc)
  tmp="$claim_file.tmp.$$"
  awk -F'|' -v now="$now" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      drop = 0
      if ($0 ~ /^[ \t]*\|/) {
        a = trim($2); b = trim($3); e = trim($5)
        if (a != "" && a != "agent" && a !~ /^-+$/ && e != "" && e <= now) {
          drop = 1
          printf "reaped %s (held by %s, expired %s)\n", b, a, e > "/dev/stderr"
        }
      }
      if (!drop) print
    }' "$claim_file" > "$tmp"

  if [ "$dry" -eq 1 ]; then
    rm -f "$tmp"
  else
    mv "$tmp" "$claim_file"
  fi
}

[ $# -ge 1 ] || { usage; exit 5; }
cmd=$1; shift

case "$cmd" in
  list)    [ $# -eq 1 ] || die "list needs <contract.md>";              cmd_list "$1" ;;
  check)   [ $# -eq 2 ] || die "check needs <contract.md> <target>";    cmd_check "$1" "$2" ;;
  claim)   [ $# -ge 2 ] || die "claim needs <contract.md> <target>";    cmd_claim "$@" ;;
  release) [ $# -ge 2 ] || die "release needs <contract.md> <target>";  cmd_release "$@" ;;
  reap)    [ $# -ge 1 ] || die "reap needs <contract.md>";              cmd_reap "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 5 ;;
esac
