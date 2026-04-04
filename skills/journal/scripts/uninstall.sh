#!/bin/bash
# journal skill 卸载脚本
# 用法: bash uninstall.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE="${WORKSPACE:-$(cd "$SKILL_DIR/../../.." && pwd)}"

echo "========================================"
echo "  Journal Skill 卸载"
echo "========================================"

# ---- 停止 daemon ----
SERVICE_NAME="openclaw-journal-sync.service"
if systemctl --user list-unit-files | grep -q "^$SERVICE_NAME"; then
    systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/$SERVICE_NAME"
    systemctl --user daemon-reload
    echo "  ✅ daemon 已停止并移除"
else
    echo "  ℹ️  daemon 未安装，跳过"
fi

# ---- 移除 cron ----
if crontab -l 2>/dev/null | grep -q "journal-daily-compact"; then
    crontab -l 2>/dev/null | grep -v "journal-daily-compact" | crontab -
    echo "  ✅ cron 任务已移除"
else
    echo "  ℹ️  cron 任务未注册，跳过"
fi

echo ""
echo "========================================"
echo "  卸载完成（数据文件保留）"
echo "========================================"
echo ""
echo "  如需彻底删除数据："
echo "    rm -rf $WORKSPACE/journals"
echo "    rm -rf $WORKSPACE/.journal-state"
echo ""
