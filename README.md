# agent-shared-protocols

Two installable [agent skills](https://docs.anthropic.com/en/docs/claude-code/skills) for a team of agents that share files — and share a context budget with themselves.

| Skill | Failure it prevents |
|---|---|
| **`single-writer-shared-data`** | Four agents edit one authoritative file. A reads it, B edits it, A writes the whole file back — B's edit is gone. |
| **`read-when-index`** | A 6,000-word must-read background is re-read in full every session — and half of it is stale. |

Each skill is a directory bundle (`SKILL.md` + `references/` + `scripts/`) with no runtime, no network and no build step.

---

## 两个坏味道，两套协议

**① 共享数据的写入协议。** 一份事实只有一份权威副本；同一时刻只让一个 agent 写；写完回读确认；历史只追加。落地物是项目里一份 `CONTRACT.md`（权威路径、可写节、认领表、只追加面、freshness 字段）+ 两个脚本：认领、回读校验。

真正难的不是"加锁"——文件系统给不了锁。难的是承认它给不了，于是把写入做成**小、原子、可回读、可合并**：改节不改全文，临时文件 rename 覆盖，写完拿 pre-copy 差分确认只碰了声明的那一节，冲突时按 freshness 合并而不是整段覆盖。

**② 长背景的读取协议。** 一份必读文档拆成"只放路由的主索引 + N 份带 `read_when` 的子文档"。索引只回答「这个任务该读哪份」，子文档才承载事实。agent 每次 grep 定位、只读命中那一份、引用时带 `doc_id` 与 `last_updated`；改完回写子文档、更新 freshness、在变更存档追加一行，索引不搬正文。

关键是 `read_when` 的写法：必须是「任务动词 + 对象」（"要开服务、查端口"），不能是「关于什么」（"服务相关"）。写泛了，路由就退化成全读，等于没拆。

## 安装

```sh
git clone https://github.com/SuperJufufu/agent-shared-protocols
cd agent-shared-protocols

./install.sh                                  # 软链到 ~/.dsh/skills（改仓库即时生效）
./install.sh --dir ~/.agents/skills --copy    # 复制到跨工具目录（Claude Code / Codex 也读）
./install.sh --dir /path/to/repo/.dsh/skills  # 只给某一个项目装
```

装完按描述命中即可，也可以直接点名：

> 「两个 agent 在改同一份配置，别互相覆盖」→ `single-writer-shared-data`
> 「这份背景文档太长了，每次都得全读」→ `read-when-index`

## 仓库结构

```text
agent-shared-protocols/
├── skills/
│   ├── single-writer-shared-data/
│   │   ├── SKILL.md
│   │   ├── references/   contract-template.md · claim-ledger.md · failure-modes.md
│   │   └── scripts/      claim.sh · verify-readback.sh
│   └── read-when-index/
│       ├── SKILL.md
│       ├── references/   index-template.md · subdoc-frontmatter.md · split-playbook.md
│       └── scripts/      check-routing.sh
├── examples/demo-desk/   虚构开发机：索引 + 3 份子文档 + 共享状态 + 认领表 + 变更存档
├── tests/run.sh          两套协议的正反用例
└── install.sh
```

## 示例

`examples/demo-desk/` 是一台**虚构**开发机（`/home/user/desk`、`demo-host:8090`）的桌面规划，同时用上两套协议：

- `INDEX.md` 是主索引，3 份子文档各带 `read_when`；
- `shared/CONTRACT.md` 声明权威状态文件、认领表与只追加的变更存档；
- `shared/state.md` 是端口表（权威数据，01 文档的 `authority` 指向它），`shared/claims.md` 是认领表，`shared/changelog.md` 只追加。

`tests/run.sh` 会验证：路由对账通过、缺 `read_when` 时报警、认领互斥、过期认领可回收、回读能抓出「改了声明之外的节」。全部只依赖 POSIX sh 与 coreutils。

## 设计取舍

- **认领是建议性的，不假装有锁。** 两个 agent 仍可能在同一毫秒进同一个写窗口。所以协议的重点不是"抢到锁"，而是"写小、写原子、写完回读、冲突可合并"。一个假装有锁的方案比没有锁更危险。
- **索引不放正文。** 索引一旦承载事实，就变成第二份真相，而且是最先过时的那份。
- **不引数据库。** 这类共享通常发生在"一台机器上几个 agent 改几个 md"，引 SQLite 只会把门槛抬到没人用。
- **脚本只依赖 POSIX sh + coreutils。** Windows 下用 Git Bash 或 WSL 跑；`date` 的 GNU/BSD 差异已在脚本里探测。

## 许可

MIT。示例中的路径、主机名、端口均为虚构。
