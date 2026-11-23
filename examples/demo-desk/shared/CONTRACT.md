---
contract: demo-desk/shared
# 相对本文件解析：本文件在 shared/ 里，所以写 claims.md 而不是 shared/claims.md
authority: state.md
claim_file: claims.md
append_only:
  - changelog.md
freshness_field: last_updated
writers:
  - claude-code
  - codex
  - dsh
  - hermes
sections:
  - "## 服务"
  - "## 端口"
---

# demo-desk 共享数据契约

`shared/state.md` 是这台（虚构）机器服务状态的**唯一**真相。

- **冻结**：`## 机器`（硬件信息，只读）
- **可写**：`## 服务`、`## 端口`
- **认领**：默认 TTL 30 分钟；批量迁移拆成多次认领，不要一次占四小时
- **冲突**：比 `last_updated`，新的那份为准；新的和旧的同时存在时，旧的立刻改成指针
- **禁止**：整文件覆盖；改 `shared/changelog.md` 的旧行；认领 note 里写 `|`
- **收尾**：回读 `[ok]` → 追加变更 → 释放认领

## 谁在写

| agent | 典型任务 |
|---|---|
| claude-code | 服务登记、文档维护 |
| codex | 端口调整、脚本改动 |
| dsh | 巡检、回读校验 |
| hermes | 定时任务相关 |
