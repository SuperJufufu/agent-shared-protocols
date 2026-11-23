# CONTRACT.md 模板

复制到项目根，把尖括号里的内容换成真的。**字段名不要改** —— 两个脚本按名字解析。

```yaml
---
contract: <项目名>/shared
authority: shared/state.md
claim_file: shared/claims.md
append_only:
  - shared/changelog.md
freshness_field: last_updated
writers:
  - claude-code
  - codex
  - dsh
  - hermes
sections:
  - "## 端口"
  - "## 启动方式"
---
```

## 字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `contract` | 是 | 契约标识，给人和日志看 |
| `authority` | 是 | 权威数据文件；同一事实**不许**在别处再抄一份 |
| `claim_file` | 是 | 认领表；脚本会往里追加/删除行 |
| `append_only` | 否 | 只追加文件列表；这些文件不许改旧行 |
| `freshness_field` | 否 | 默认 `last_updated`；冲突时比大小 |
| `writers` | 否 | 允许写入的 agent；名单外的人只读 |
| `sections` | 是 | **允许改的节标题**，原样抄含 `##` |

相对路径按**契约所在目录**解析。

## 正文写什么

1. **谁是唯一真相**：为什么是这份文件；别处的副本一律视为缓存，过期即弃。
2. **冻结面**：哪些节不许动（例如"## 机器信息"里贴了硬件序列号）。
3. **认领规则**：默认 TTL（30 分钟），哪些操作例外（大迁移要拆成多次认领）。
4. **冲突裁决**：以 `freshness_field` 新者为准；判断不了就停手问人。
5. **明令禁止**：整文件覆盖、删只追加文件的行、在认领 note 里写 `|`。

## 一个填好的例子

```markdown
---
contract: demo-desk/shared
authority: shared/state.md
claim_file: shared/claims.md
append_only:
  - shared/changelog.md
freshness_field: last_updated
writers: [claude-code, codex, dsh, hermes]
sections:
  - "## 端口"
  - "## 启动方式"
---

# demo-desk 共享数据契约

`shared/state.md` 是这台机器服务状态的唯一真相。

- 冻结：`## 机器信息`（硬件序列号，只读）
- 认领：默认 30 分钟；批量迁移拆成多次
- 冲突：比 `last_updated`，新的那份为准，旧的立刻修
- 禁止：整文件覆盖；改 `shared/changelog.md` 的旧行；note 里写 `|`
```

## 没有契约会怎样

脚本会直接退出（`no claim_file in ...`）。这不是要你跳过认领，而是提醒：**共享写入的约定必须落地成文件** —— 写在聊天记录里的约定，第三个 agent 读不到。
