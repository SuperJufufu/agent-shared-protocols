# 认领表

`claims.md` 是一张 markdown 表，`claim.sh` 按列解析。默认放 `shared/claims.md`。

```markdown
| agent | target | started (UTC) | expires (UTC) | note |
|---|---|---|---|---|
| dsh | shared/state.md#端口 | 2026-11-23T15:31:00Z | 2026-11-23T16:01:00Z | 加 9090 |
```

## 列

| 列 | 规则 |
|---|---|
| `agent` | 写入者标识，和 `CONTRACT.md` 的 `writers` 对得上 |
| `target` | `<文件>#<节标题>`，节标题原样抄（含 `##`） |
| `started` | UTC、ISO-8601、秒级 |
| `expires` | 同上；字典序 = 时间序，脚本就靠这个比较，所以格式必须一致 |
| `note` | 一句话；**不要写 `|`**，要分隔就用 `/` |

## 规则

- 默认 TTL 30 分钟。改一节几行 → 30；重写几百行 → 90；批量迁移 → **拆成多次认领**，不要一次占四小时。
- 续期 = 再 `claim` 一次（新增一行，旧行过期后 `reap` 掉）。
- 过期不等于没人写：`reap` 之前先看一眼文件是否还在变。
- 认领表**本身是可变的**（不是只追加文件）：`release` / `reap` 会删行。
- 不要手工删别人的行 —— 用 `claim.sh reap`，它会打印回收了谁。
- 表必须放在文件末尾：`claim` 是往文件尾部追加行的。

## 命令

```sh
scripts/claim.sh list    shared/CONTRACT.md
scripts/claim.sh check   shared/CONTRACT.md 'shared/state.md#端口'
scripts/claim.sh claim   shared/CONTRACT.md 'shared/state.md#端口' --agent dsh --ttl 30 --note '加 9090'
scripts/claim.sh release shared/CONTRACT.md 'shared/state.md#端口' --agent dsh
scripts/claim.sh reap    shared/CONTRACT.md --dry-run
```

退出码：

| 码 | 含义 |
|---|---|
| 0 | 可以写 / 操作成功 |
| 3 | `release` 时没有匹配的认领 |
| 4 | 目标被占（未过期） |
| 5 | 参数或契约有问题 |

## 为什么用建议性认领而不是锁

文件系统没有跨进程写锁。能做的是：让「谁正在写什么」对所有人可见，并把写入窗口压到最短。认领过期是特性不是缺陷 —— 它保证崩溃的 agent 不会永久占住一节。代价是理论上仍可能交错，所以每一步都要有回读兜底（见 `failure-modes.md` 第 2 条）。
