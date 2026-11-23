#!/usr/bin/env sh
# tests/run.sh — 两个 skill 的脚本冒烟测试。只用 POSIX sh + coreutils。
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

claim="$root/skills/single-writer-shared-data/scripts/claim.sh"
verify="$root/skills/single-writer-shared-data/scripts/verify-readback.sh"
routing="$root/skills/read-when-index/scripts/check-routing.sh"

pass=0
fail=0

check() { # 描述 期望码 实际码
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
    printf '  ok    %s\n' "$1"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s（期望 %s，实际 %s）\n' "$1" "$2" "$3"
  fi
}

fresh() {
  rm -rf "$tmp/d"
  cp -R "$root/examples/demo-desk" "$tmp/d"
}

line_n() { wc -l < "$1" | tr -d ' '; }

echo "== check-routing.sh =="

fresh
"$routing" "$tmp/d/INDEX.md" >/dev/null 2>&1
check "干净的 demo-desk 通过" 0 $?

fresh
cp "$tmp/d/02-备份与恢复.md" "$tmp/d/04-未登记.md"
"$routing" "$tmp/d/INDEX.md" >/dev/null 2>&1
check "未登记的子文档被抓到" 1 $?

fresh
rm "$tmp/d/02-备份与恢复.md"
"$routing" "$tmp/d/INDEX.md" >/dev/null 2>&1
check "索引指向不存在的文件被抓到" 1 $?

fresh
sed -i.tmp 's/^read_when:.*/read_when: 任何与备份有关的时候/' "$tmp/d/02-备份与恢复.md"
"$routing" "$tmp/d/INDEX.md" >/dev/null 2>&1
check "read_when 含禁词被抓到" 1 $?

fresh
sed -i.tmp 's/^scope:.*/scope:/' "$tmp/d/02-备份与恢复.md"
"$routing" "$tmp/d/INDEX.md" >/dev/null 2>&1
check "缺字段被抓到" 1 $?

fresh
sed -i.tmp 's/^last_updated:.*/last_updated: 2026-11-23/' "$tmp/d/02-备份与恢复.md"
"$routing" "$tmp/d/INDEX.md" >/dev/null 2>&1
check "last_updated 格式错误被抓到" 1 $?

echo "== claim.sh =="

fresh
c="$tmp/d/shared/CONTRACT.md"
t='shared/state.md#端口'

"$claim" check "$c" "$t" >/dev/null 2>&1
check "过期的认领不算占用" 0 $?

before=$(line_n "$tmp/d/shared/claims.md")
"$claim" claim "$c" "$t" --agent dsh --ttl 5 --note '冒烟测试' >/dev/null 2>&1
check "空闲目标可以认领" 0 $?
after=$(line_n "$tmp/d/shared/claims.md")
check "认领表多了一行" "$((before + 1))" "$after"

"$claim" check "$c" "$t" >/dev/null 2>&1
check "被占用时 check 返回 4" 4 $?

"$claim" claim "$c" "$t" --agent codex --ttl 5 >/dev/null 2>&1
check "重复认领被拒（4）" 4 $?

"$claim" release "$c" "$t" --agent dsh >/dev/null 2>&1
check "释放成功" 0 $?

"$claim" release "$c" "$t" --agent dsh >/dev/null 2>&1
check "重复释放返回 3" 3 $?

"$claim" reap "$c" --dry-run 2>&1 | grep -q reaped
check "reap 能列出过期认领" 0 $?

"$claim" claim "$c" "$t" --agent dsh --ttl 5 --note 'a|b' >/dev/null 2>&1
check "note 里的竖线被拒（5）" 5 $?

echo "== verify-readback.sh =="

fresh
s="$tmp/d/shared/state.md"
pre="$tmp/state.pre"
cp "$s" "$pre"

"$verify" "$s" --pre-copy "$pre" --section '## 端口' >/dev/null 2>&1
check "完全没改动返回 3" 3 $?

sed -i.tmp 's/| 8090 | 演示网页 |/| 8091 | 演示网页 |/' "$s"
"$verify" "$s" --pre-copy "$pre" --section '## 端口' >/dev/null 2>&1
check "只改声明的节 → ok" 0 $?

cp "$s" "$tmp/state.pre2"
sed -i.tmp '/^## 机器/a - 偷偷加的一行' "$s"
"$verify" "$s" --pre-copy "$tmp/state.pre2" --section '## 端口' >/dev/null 2>&1
check "改了声明之外的节 → 4" 4 $?

printf '# 只有标题\n' > "$tmp/broken.md"
"$verify" "$tmp/broken.md" >/dev/null 2>&1
check "没有 frontmatter 也照常结构检查通过" 0 $?

printf -- '---\ntitle: 没闭合\n' > "$tmp/broken2.md"
"$verify" "$tmp/broken2.md" >/dev/null 2>&1
check "frontmatter 未闭合 → 2" 2 $?

: > "$tmp/empty.md"
"$verify" "$tmp/empty.md" >/dev/null 2>&1
check "空文件 → 2" 2 $?

echo
printf '通过 %s · 失败 %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
