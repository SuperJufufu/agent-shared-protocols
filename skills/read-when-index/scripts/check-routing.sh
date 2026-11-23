#!/usr/bin/env sh
# check-routing.sh — 校验 read_when 索引与子文档是否自洽。
# 只依赖 POSIX sh + coreutils + grep。
set -u

prog=$(basename "$0")
die() { printf '%s: %s\n' "$prog" "$*" >&2; exit 2; }

usage() {
  cat <<EOF
usage: $prog <index.md> [--docs-dir <dir>]

检查项：
  1. 索引里链接的子文档都存在
  2. 磁盘上的 .md 子文档都已在索引登记
  3. 每份子文档六字段齐全（doc_id/title/scope/read_when/authority/last_updated）
  4. read_when 非空、不含无判别力的禁词
  5. authority 为 self 或指向存在的文件
  6. last_updated 形如 YYYY-MM-DD HH:MM
  7. doc_id 不重复

exit: 0 全部通过 · 1 有失败项 · 2 参数/文件错误
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

fails=0
fail() { printf '[fail] %s\n' "$*"; fails=$((fails + 1)); }
ok()   { printf '[ok] %s\n' "$*"; }

valid_date() {
  printf '%s' "$1" | grep -Eq \
    '^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]$'
}

bad_read_when() {
  case "$1" in
    *任何*|*相关*|*所有*|*一切*|*全部*|*随便*) return 0 ;;
  esac
  case " $1 " in
    *" all "*|*" any "*|*" everything "*|*"*"*) return 0 ;;
  esac
  return 1
}

# 打印索引正文里的 markdown 链接目标（只保留 .md，去掉 #锚点）
list_links() {
  awk '{
    line = $0
    while ((i = index(line, "](")) > 0) {
      rest = substr(line, i + 2)
      j = index(rest, ")")
      if (j == 0) break
      u = substr(rest, 1, j - 1)
      sub(/#.*$/, "", u)
      if (u ~ /\.md$/ && u !~ /^https?:/) print u
      line = substr(rest, j + 1)
    }
  }' "$1"
}

index=""
docs_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    --docs-dir) [ $# -ge 2 ] || die "--docs-dir needs a value"; docs_override=$2; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         usage; exit 2 ;;
    *)          [ -z "$index" ] || die "more than one index given"; index=$1; shift ;;
  esac
done

[ -n "$index" ] || { usage; exit 2; }
[ -f "$index" ] || die "no such index: $index"

idir=$(cd "$(dirname "$index")" && pwd)
ibase=$(basename "$index")

if [ -n "$docs_override" ]; then
  case "$docs_override" in
    /*) docs_dir=$docs_override ;;
    *)  docs_dir=$(cd "$docs_override" 2>/dev/null && pwd) || die "no such dir: $docs_override" ;;
  esac
else
  rel=$(field "$index" docs_dir)
  [ -n "$rel" ] || rel="."
  case "$rel" in
    /*) docs_dir=$rel ;;
    *)  docs_dir=$idir/$rel ;;
  esac
fi
[ -d "$docs_dir" ] || die "docs_dir not found: $docs_dir"

# --- 索引自身 ---
for k in doc_id title scope last_updated; do
  if [ -z "$(field "$index" "$k")" ]; then
    fail "索引缺字段 $k"
  fi
done
lu=$(field "$index" last_updated)
if [ -n "$lu" ] && ! valid_date "$lu"; then
  fail "索引 last_updated 格式不对：$lu（要 YYYY-MM-DD HH:MM）"
fi

# --- 索引链接 → 磁盘 ---
tmp=$(mktemp)
list_links "$index" | sed 's#^\./##' | sort -u > "$tmp"
n_links=$(wc -l < "$tmp" | tr -d ' ')
[ "$n_links" -gt 0 ] || fail "索引里没有任何 .md 链接"

tmp_ids=$(mktemp)

while read -r link; do
  [ -n "$link" ] || continue
  doc="$docs_dir/$link"
  if [ ! -f "$doc" ]; then
    fail "索引指向的子文档不存在：$link"
    continue
  fi

  for k in doc_id title scope read_when authority last_updated; do
    if [ -z "$(field "$doc" "$k")" ]; then
      fail "$link 缺字段 $k"
    fi
  done

  did=$(field "$doc" doc_id)
  if [ -n "$did" ]; then
    if grep -qx "$did" "$tmp_ids"; then
      fail "doc_id 重复：$did（$link）"
    else
      printf '%s\n' "$did" >> "$tmp_ids"
    fi
  fi

  rw=$(field "$doc" read_when)
  if [ -n "$rw" ]; then
    if bad_read_when "$rw"; then
      fail "$link 的 read_when 含无判别力的词：$rw"
    fi
  fi

  auth=$(field "$doc" authority)
  if [ -n "$auth" ] && [ "$auth" != "self" ]; then
    [ -f "$docs_dir/$auth" ] || fail "$link 的 authority 指向不存在的文件：$auth"
  fi

  dlu=$(field "$doc" last_updated)
  if [ -n "$dlu" ] && ! valid_date "$dlu"; then
    fail "$link 的 last_updated 格式不对：$dlu"
  fi
done < "$tmp"

# --- 磁盘 → 索引（双向对齐）---
for f in "$docs_dir"/*.md; do
  [ -f "$f" ] || continue
  b=$(basename "$f")
  [ "$b" = "$ibase" ] && continue
  case "$b" in
    README.md|CHANGELOG.md) continue ;;
  esac
  if ! grep -qxF "$b" "$tmp" && ! grep -qxF "./$b" "$tmp"; then
    fail "子文档未在索引登记：$b"
  fi
done

rm -f "$tmp" "$tmp_ids"

if [ "$fails" -gt 0 ]; then
  printf '\n%d 项失败\n' "$fails" >&2
  exit 1
fi

printf '[ok] %s 项全部通过（%s 份子文档，docs_dir=%s）\n' \
  "索引链接与子文档一致性" "$n_links" "$docs_dir"
exit 0
