#!/usr/bin/env sh
# verify-readback.sh — 写后回读：结构是否完好，改动是否只在声明的那一节。
# 只依赖 POSIX sh + coreutils。
set -u

prog=$(basename "$0")
die() { printf '%s: %s\n' "$prog" "$*" >&2; exit 5; }

usage() {
  cat <<EOF
usage: $prog <file> [--pre-copy <path>] [--section '<heading>'] [--pre-hash <sha256>]

  --pre-copy   写之前的副本；用它做差分，确认只改了 --section 声明的那节
  --section    目标节标题，原样写，例如 '## 端口'
  --pre-hash   没存副本时，至少比对哈希，确认文件确实变了

exit: 0 ok · 2 structure problem · 3 nothing changed · 4 changed outside section
EOF
}

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    cksum "$1" | cut -d' ' -f1-2 | tr ' ' '-'
  fi
}

check_structure() {
  [ -s "$1" ] || { echo "[fail] 文件为空"; return 2; }
  case "$1" in
    *.md)
      if [ "$(head -n 1 "$1")" = "---" ]; then
        if ! awk 'NR > 1 && /^---[ \t]*$/ { found = 1 } END { exit found ? 0 : 1 }' "$1"; then
          echo "[fail] frontmatter 没有闭合的 ---"
          return 2
        fi
      fi
      ;;
  esac
  return 0
}

# 打印目标节在新文件里的行范围：start end
section_range() {
  awk -v h="$2" '
    function level(s,   i) { i = 0; while (substr(s, i + 1, 1) == "#") i++; return i }
    /^#{1,6}[ \t]/ {
      if (!found) {
        if ($0 == h) { found = 1; start = NR; lvl = level($0) }
      } else if (!done) {
        if (level($0) <= lvl) { print start, NR; done = 1; exit }
      }
    }
    END { if (found && !done) print start, NR }
  ' "$1"
}

# 从 unified diff 里取新文件侧被改到的行号
changed_lines() {
  diff -u "$1" "$2" | awk '
    /^@@/ {
      s = $0
      sub(/^.*\+/, "", s)
      sub(/[^0-9,].*$/, "", s)
      split(s, p, ",")
      start = p[1] + 0
      cnt = (2 in p) ? p[2] + 0 : 1
      if (cnt == 0) print start
      else for (i = 0; i < cnt; i++) print start + i
    }'
}

# 把每行改动映射到它所属的节，输出 "节名<TAB>行数"
owners_of() {
  awk -v cl="$2" '
    FNR == NR { mark[$1] = 1; next }
    /^#{1,6}[ \t]/ { cur = $0 }
    {
      if (FNR in mark) {
        if (cur == "") cur = "(文件头)"
        own[cur]++
      }
    }
    END { for (k in own) printf "%s\t%d\n", k, own[k] }
  ' "$2" "$1"
}

file=""
pre_copy=""
pre_hash=""
section=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pre-copy) [ $# -ge 2 ] || die "--pre-copy needs a path"; pre_copy=$2; shift 2 ;;
    --pre-hash) [ $# -ge 2 ] || die "--pre-hash needs a value"; pre_hash=$2; shift 2 ;;
    --section)  [ $# -ge 2 ] || die "--section needs a heading"; section=$2; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         usage; exit 5 ;;
    *)          [ -z "$file" ] || die "more than one file given"; file=$1; shift ;;
  esac
done

[ -n "$file" ] || { usage; exit 5; }
[ -f "$file" ] || die "no such file: $file"

check_structure "$file" || exit 2

h=$(hash_of "$file")

if [ -n "$pre_hash" ] && [ "$h" = "$pre_hash" ]; then
  echo "[fail] 文件哈希未变，写入没有生效"
  exit 3
fi

if [ -z "$pre_copy" ]; then
  if [ -n "$section" ]; then
    echo "[warn] 没有 --pre-copy，无法确认改动范围（只做了结构检查）"
  fi
  echo "[ok] 结构正常（sha ${h%"${h#????????}"}…）"
  exit 0
fi

[ -f "$pre_copy" ] || die "--pre-copy not found: $pre_copy"

if [ -n "$section" ]; then
  range=$(section_range "$file" "$section")
  [ -n "$range" ] || { echo "[fail] 找不到节：$section"; exit 2; }
fi

tmp=$(mktemp)
changed_lines "$pre_copy" "$file" > "$tmp"

if [ ! -s "$tmp" ]; then
  rm -f "$tmp"
  echo "[fail] pre-copy 与当前文件完全一致，写入没有生效"
  exit 3
fi

total=$(wc -l < "$tmp" | tr -d ' ')
owners=$(owners_of "$file" "$tmp")
rm -f "$tmp"

if [ -z "$section" ]; then
  echo "[ok] 共改动 $total 行，落在："
  printf '%s\n' "$owners" | while IFS="$(printf '\t')" read -r head cnt; do
    printf '  %s（%s 行）\n' "$head" "$cnt"
  done
  exit 0
fi

tmp2=$(mktemp)
printf '%s\n' "$owners" > "$tmp2"
msg=$(awk -v s="$section" '
  {
    n = index($0, "\t")
    if (n == 0) { head = $0; cnt = "" }
    else { head = substr($0, 1, n - 1); cnt = substr($0, n + 1) }
    if (head != s) { printf "[fail] 改到了 %s（%s 行），声明的是 %s\n", head, cnt, s; bad = 1 }
  }
  END { exit bad ? 4 : 0 }' "$tmp2")
status=$?
rm -f "$tmp2"

[ -n "$msg" ] && printf '%s\n' "$msg"

if [ "$status" -ne 0 ]; then
  exit 4
fi

echo "[ok] 共改动 $total 行，只落在「$section」（行 $range）"
exit 0
