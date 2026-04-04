#!/bin/bash
# journal skill 一键安装脚本
# 用法: bash install.sh
# 自动完成：目录创建、systemd 注册、cron 注册、AGENTS.md 补丁

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE="${WORKSPACE:-$(cd "$SKILL_DIR/../../.." && pwd)}"

echo "========================================"
echo "  Journal Skill 安装脚本"
echo "========================================"
echo "  WORKSPACE: $WORKSPACE"
echo "  SKILL_DIR: $SKILL_DIR"
echo ""

# ---- 1. 创建目录 ----
echo "[1/5] 创建必要目录..."
mkdir -p "$WORKSPACE/journals/current"
mkdir -p "$WORKSPACE/journals/blobs"
mkdir -p "$WORKSPACE/journals/index"
mkdir -p "$WORKSPACE/.journal-state"
mkdir -p "$WORKSPACE/logs"
mkdir -p "$WORKSPACE/memory"
echo "      ✅ 目录创建完成"

# ---- 2. 注册 systemd service ----
echo ""
echo "[2/5] 注册 systemd user service..."

SERVICE_NAME="openclaw-journal-sync.service"
SERVICE_FILE="$HOME/.config/systemd/user/$SERVICE_NAME"

# 检查是否已有同名 service
if systemctl --user list-unit-files | grep -q "^$SERVICE_NAME"; then
    echo "      ℹ️  $SERVICE_NAME 已存在，跳过创建（可用 --force 强制重装）"
else
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=OpenClaw Journal Sync Daemon — real-time session to journal
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $WORKSPACE/scripts/journal-sync-daemon.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
Environment=OPENCLAW_JOURNAL_WORKSPACE=$WORKSPACE

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    echo "      ✅ service 文件已创建: $SERVICE_FILE"
fi

systemctl --user enable --now "$SERVICE_NAME" 2>/dev/null || true
if systemctl --user is-active --quiet "$SERVICE_NAME"; then
    echo "      ✅ daemon 已启动"
else
    echo "      ⚠️  daemon 启动失败，查看日志："
    echo "         journalctl --user -u $SERVICE_NAME -n 10"
fi

# ---- 3. 注册 cron 定时精炼 ----
echo ""
echo "[3/5] 注册每日 23:20 精炼任务..."

CRON_ENTRY="20 23 * * * bash $WORKSPACE/scripts/journal-daily-compact.sh >> $WORKSPACE/logs/journal-compact.log 2>&1"
CRON_CURRENT=$(crontab -l 2>/dev/null || true)

if echo "$CRON_CURRENT" | grep -q "journal-daily-compact"; then
    echo "      ℹ️  cron 任务已存在，跳过"
else
    (echo "$CRON_CURRENT"; echo "$CRON_ENTRY") | crontab -
    echo "      ✅ cron 已注册: 每天 23:20 精炼写入 memory"
fi

# ---- 4. 补丁 AGENTS.md ----
echo ""
echo "[4/5] 检查 AGENTS.md 进门必检路径..."

AGENTS="$WORKSPACE/AGENTS.md"
TRIGGER_LINE="scripts/trigger_check.sh"

if [ -f "$AGENTS" ]; then
    if grep -q "trigger_check" "$AGENTS"; then
        echo "      ℹ️  进门必检已配置，跳过"
    else
        # 查找 Message Processing 章节并追加
        if grep -q "Message Processing" "$AGENTS" || grep -q "进门必检" "$AGENTS"; then
            # 在进门必检章节下追加
            sed -i "s|触发检测路径：.*|触发检测路径：\`$TRIGGER_LINE\`|" "$AGENTS" 2>/dev/null || true
        fi
        echo "      ℹ️  请手动确认 AGENTS.md 中进门必检路径已指向: $TRIGGER_LINE"
    fi
else
    echo "      ⚠️  未找到 AGENTS.md，跳过"
fi

# ---- 5. 验证安装 ----
echo ""
echo "[5/5] 验证写入..."

TEST_MSG="journal-install-$(date +%s)"
RESULT=$(echo "$TEST_MSG" | python3 "$SCRIPT_DIR/journal_append.py" --role user --channel feishu 2>&1)
if echo "$RESULT" | grep -q '"ok": true'; then
    echo "      ✅ 写入测试通过"
else
    echo "      ⚠️  写入测试失败: $RESULT"
fi

# ---- 完成 ----
echo ""
echo "========================================"
echo "  安装完成！"
echo "========================================"
echo ""
echo "  状态摘要："
echo "  • daemon:   $(systemctl --user is-active --quiet "$SERVICE_NAME" && echo '运行中' || echo '未运行')"
echo "  • cron:     $(crontab -l 2>/dev/null | grep -q 'journal-daily-compact' && echo '已注册' || echo '未注册')"
echo "  • journal:  $WORKSPACE/journals/current/"
echo ""
echo "  卸载命令: bash $SCRIPT_DIR/uninstall.sh"
echo ""
