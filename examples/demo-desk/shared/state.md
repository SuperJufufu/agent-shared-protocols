---
doc_id: demo-state
title: demo-desk 状态
last_updated: 2026-11-23 22:40
---

# demo-desk 状态

## 机器

- 主机名：`demo-host`
- 系统：Linux，用户目录 `/home/user/desk`
- 外置盘：通过 junction 挂到 `backup/`，**没插盘就没有 backup**

## 服务

| 服务 | 启动命令 | 工作目录 | 自启动 |
|---|---|---|---|
| 演示网页 | `python3 -m http.server 8090` | `/home/user/desk/site` | 是 |
| 任务队列 | `./work/queue.sh` | `/home/user/desk` | 是 |

## 端口

| 端口 | 服务 | 备注 |
|---|---|---|
| 8090 | 演示网页 | 2026-11-23 从 8080 改过来 |
| 5432 | 本地数据库 | 不对外监听 |
