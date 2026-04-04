---
name: journal
description: 飞书消息实时记录系统。将每条用户/助手消息 append-only 写入 `journals/current/YYYYMMDD.jsonl`，按日期自动轮转，与 session reset 完全解耦，支持新会话查询历史。当用户询问"今天说了什么"、"查一下之前的对话"时激活。
---

# Journal — 飞书消息实时记录系统

## 功能

每条飞书消息（用户 + 助手）实时写入 `journals/current/YYYYMMDD.jsonl`，按日期自动轮转，reset 不丢数据，新会话可查询。

## 安装（两步完成）

### 第一步：安装 skill

**方式 A：clawhub 安装**
```bash
clawhub install ./journal.skill
```

**方式 B：从 GitHub 克隆**
```bash
git clone https://github.com/whhxsk/journal-skill.git
cd journal-skill/journal
```

---

### 第二步：一键初始化
```bash
cd journal-skill/journal
bash scripts/install.sh
```

---

## 使用方法

直接问我：
> "今天都说了什么？"
> "查一下今天的消息"
> "昨天聊了什么？"

---

## 文件结构

```
journal/
├── SKILL.md
└── scripts/
    ├── install.sh                 ← 一键安装
    ├── uninstall.sh               ← 卸载
    ├── journal-config.sh          ← ⚙️ 配置文件（可自定义保留天数）
    ├── journal_append.py          ← 核心写入
    ├── message-log.sh             ← 入口包装
    ├── trigger_check.sh           ← 进门必检
    ├── journal-daily-compact.sh   ← 每日精炼
    └── journal-sync-daemon.py     ← systemd daemon
```

---

## ⚙️ 自定义保留天数

打开 `scripts/journal-config.sh`，修改 `RETENTION_DAYS`：

| 值 | 效果 |
|----|------|
| `1`（默认）| 每天只保留当天的 journal |
| `7` | 保留最近 7 天 |
| `30` | 保留 30 天 |
| `0` | 不自动删除，保留所有 |

```bash
# 例：改成保留 7 天
sed -i 's/RETENTION_DAYS=1/RETENTION_DAYS=7/' scripts/journal-config.sh
```

---

## 定时任务

| 时间 | 任务 | 说明 |
|------|------|------|
| systemd 常驻 | journal-sync-daemon.py | ≤3 秒同步新消息 |
| 每天 23:20 | journal-daily-compact.sh | 精炼写入 memory + 清理过期 journal |

---

## 卸载
```bash
bash uninstall.sh
```
