---
name: single-writer-shared-data
description: "多 agent 共用一份权威数据时的写入协议：先落 CONTRACT.md（权威路径、可写节、认领表、只追加面、freshness 字段），写入走 认领 → 改节不改全文 → 原子替换 → 写后回读 → 只追加留痕，用租约与回读把并发写收敛成可审计的串行写。当两个以上 agent（Claude Code / Codex / DSH / Hermes）会改同一份文件，或用户提到认领、抢占、写冲突、被覆盖、只追加、写后回读、交接时使用。/ Shared authoritative data across agents: claim, single writer, section-only edits, atomic replace, read-after-write, append-only history."
whenToUse: "≥2 个 agent 可能写同一份事实文件，或用户说「别覆盖」「谁先改」「认领」「写冲突」「交接」时。单个 agent 改一份普通文档、或只是只读引用时不要用。"
---

# 单写者共享数据

## 0. 一句话

同一份事实只有一份权威副本；同一时刻只让一个 agent 写它；写完必须回读确认；历史只追加。

## 1. 什么时候用 / 不用

用：

- 两个以上 agent（不同厂商、不同会话、不同机器）会改同一份文件或同一张表
- 文件没有锁，只能靠约定
- 改动需要能追溯「谁在什么时候改了哪一节」

不用：

- 只有一个写入者
- 只读引用 —— 那不需要认领，直接读并带上 revision
- 已经有数据库事务或版本控制分支在保证并发安全

## 2. 先找契约，没有就建

按顺序找：

1. 项目根的 `CONTRACT.md`
2. `.agents/shared-data.md`
3. 用户指定的路径

都没有 → 用 `references/contract-template.md` 建一份，先问清三件事：**权威文件是哪个、哪些节允许写、认领表放哪**。

契约里脚本要读的字段（名字不要改）：

| 字段 | 含义 |
|---|---|
| `authority` | 权威数据文件，相对契约所在目录 |
| `claim_file` | 认领表 |
| `append_only` | 只追加、不许改旧行的文件 |
| `freshness_field` | 判断新旧的字段名，默认 `last_updated` |
| `writers` | 允许写入的 agent 名单 |
| `sections` | 允许改的节标题 |

## 3. 读：带 revision 引用

- 每条事实连同 `last_updated` 一起引用，例如「端口 8080（`state.md`，2026-11-23 21:10）」。
- 不凭记忆改路径、端口、文件名；不确定就回原文件核对。
- 读之前先看认领表：有人正在改你要读的那节，你读到的可能是半成品 —— 标注出来，或等对方释放。

## 4. 写：七步

1. **认领**

   ```sh
   scripts/claim.sh claim shared/CONTRACT.md 'shared/state.md#端口' --agent dsh --ttl 30 --note '加 9090'
   ```

   退出码 4 = 已被占。等、换一节、或跟对方分工，**不要硬抢**。

2. **备份 pre-copy**（第 5 步的回读要用）

   ```sh
   cp shared/state.md /tmp/state.md.pre.$$
   ```

3. **改节不改全文**：只替换目标节内的文本，其它节一个字节不动。整文件重写是被禁止的 —— 那是上一轮别人改动消失的地方。

4. **原子替换**：写到临时文件，校验没问题再 `mv` 覆盖（同一文件系统内 rename 是原子的，不会留下半截文件）。

   ```sh
   awk '...' shared/state.md > /tmp/state.md.new.$$ && mv /tmp/state.md.new.$$ shared/state.md
   ```

5. **写后回读**

   ```sh
   scripts/verify-readback.sh shared/state.md \
     --pre-copy /tmp/state.md.pre.$$ --section '## 端口'
   ```

   期望 `[ok]`。`[fail]` 就回滚（把 pre-copy 覆盖回去），不要继续往下走。

6. **留痕**：在契约里 `append_only` 的文件顶部加一行：`2026-11-23 21:40 · dsh · shared/state.md#端口 · 加 9090`。旧条目不动。

7. **释放**

   ```sh
   scripts/claim.sh release shared/CONTRACT.md 'shared/state.md#端口' --agent dsh
   ```

## 5. 冲突裁决

| 情形 | 做法 |
|---|---|
| 认领被占且未过期 | 等 / 换节 / 分工，不硬抢 |
| 认领已过期（孤儿） | `claim.sh reap`，回收要在 note 里写明「回收 <agent> 的过期认领」 |
| 回读发现别人改了其它节 | 保留对方改动，只重放自己那节；**不要**整段覆盖 |
| 两份副本改了同一节 | 以 `freshness_field` 较新者为准合并；判断不了就停下来问人 |
| 写到一半失败 | 用 pre-copy 回滚 → 释放认领 → 在留痕里记一笔 |

## 6. 检查清单

- [ ] 只改了契约里声明的节
- [ ] 回读是 `[ok]`，不是「应该没问题」
- [ ] 只追加文件只在顶部/尾部加了行，旧行没动
- [ ] `freshness_field` 已更新
- [ ] 认领已释放（`claim.sh list` 里没有自己）
- [ ] 改动写进了留痕文件

## 7. 反面模式

- 读完 → 想了很久 → 整文件写回：这中间别人的改动全没了。
- 用文件修改时间当锁：`mtime` 会被任何写操作刷新，表达不了「谁在写」。
- 认领了不释放：下一个 agent 只能干等到过期。
- 在只追加文件里删行改行：历史就不再是证据。
- 回读只看「文件还在」：结构坏了、别的节被覆盖，一样发现不了。

## 8. 脚本

| 脚本 | 用途 |
|---|---|
| `scripts/claim.sh` | `list` / `check` / `claim` / `release` / `reap`，读 CONTRACT.md 的 frontmatter |
| `scripts/verify-readback.sh` | 结构检查 + pre-copy 差分，确认只改了声明的那节 |

两个都只依赖 POSIX sh + coreutils；Windows 下用 Git Bash 或 WSL。

细节见 `references/`：契约模板、认领表规则、六种失败模式与对策。
