#!/usr/bin/env sh
# 把两个 skill 装进 agent 的 skills 目录。
#
#   ./install.sh                              # 软链到 ~/.dsh/skills
#   ./install.sh --dir ~/.agents/skills       # 换目录
#   ./install.sh --copy                       # 复制而不是软链
#   ./install.sh --uninstall                  # 卸载
set -eu

src=$(cd "$(dirname "$0")" && pwd)
target="$HOME/.dsh/skills"
mode=link

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)       [ $# -ge 2 ] || { echo "--dir needs a path" >&2; exit 2; }; target=$2; shift 2 ;;
    --copy)      mode=copy; shift ;;
    --uninstall) mode=remove; shift ;;
    -h|--help)   sed -n '2,8p' "$0"; exit 0 ;;
    *)           echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$target"

for s in single-writer-shared-data read-when-index; do
  dest="$target/$s"
  case "$dest" in
    "$target"/*) ;;
    *) echo "refusing to touch $dest" >&2; exit 1 ;;
  esac

  case "$mode" in
    link)
      rm -rf "$dest"
      ln -s "$src/skills/$s" "$dest"
      printf 'linked  %s -> %s\n' "$dest" "$src/skills/$s"
      ;;
    copy)
      rm -rf "$dest"
      cp -R "$src/skills/$s" "$dest"
      printf 'copied  %s\n' "$dest"
      ;;
    remove)
      rm -rf "$dest"
      printf 'removed %s\n' "$dest"
      ;;
  esac
done
