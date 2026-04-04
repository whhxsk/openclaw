#!/bin/bash
# Journal message logger — 每条飞书消息自动写入 append-only JSONL
# 用法: message-log.sh user "消息文本"
ROLE="$1"
TEXT="$2"
CHANNEL="feishu"
# Detect workspace from script location: skills/journal/scripts/ -> workspace
JOURNAL_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
JOURNAL_SCRIPT="$JOURNAL_ROOT/scripts/journal_append.py"

if [ -z "$TEXT" ] || [ "$TEXT" = "NO_REPLY" ] || [ "$TEXT" = "HEARTBEAT_OK" ]; then
    exit 0
fi

echo "$TEXT" | python3 "$JOURNAL_SCRIPT" \
    --role "$ROLE" \
    --channel "$CHANNEL" \
    >/dev/null 2>&1
