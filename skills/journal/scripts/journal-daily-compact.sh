#!/bin/bash
# 每天 23:50 journal 精炼（AI 提炼版）

# 加载环境变量（包含 MINIMAX_API_KEY）
if [ -f /home/xiwang/.openclaw/.env ]; then
    set -a
    source /home/xiwang/.openclaw/.env
    set +a
fi

JOURNAL_ROOT="/home/xiwang/.openclaw/workspace"
LOG="$JOURNAL_ROOT/logs/journal-compact.log"
PYTHON_SCRIPT="$JOURNAL_ROOT/scripts/journal_compact.py"

TARGET_DATE=$(date +%Y-%m-%d)

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始处理 $TARGET_DATE（AI版）" >> "$LOG"
cd "$JOURNAL_ROOT"
python3 "$PYTHON_SCRIPT" --date "$TARGET_DATE" >> "$LOG" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 完成" >> "$LOG"
