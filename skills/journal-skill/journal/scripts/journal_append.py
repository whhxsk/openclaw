#!/usr/bin/env python3
"""
Append one chat message to session journal (JSONL).

Size-aware: texts > 1MB are written to a blob file, and the JSONL
record only stores the blob path (not the content itself).

Journal file naming: journals/current/YYYYMMDD.jsonl
一天一个文件，/reset 不影响，跨 session 都在同一天文件里。
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import sys
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
STATE_DIR = ROOT / '.openclaw' / 'journal-state'
CURRENT_DIR = ROOT / 'journals' / 'current'
INDEX_DIR = ROOT / 'journals' / 'index'
BLOBS_DIR = ROOT / 'journals' / 'blobs'

SIZE_THRESHOLD = 1 * 1024 * 1024  # 1 MB


def now_local_iso():
    return dt.datetime.now().astimezone().isoformat(timespec='seconds')


def today_id():
    return dt.datetime.now().astimezone().strftime('%Y%m%d')


def journal_path_by_date():
    """永远按当天日期写，不受 session 切换影响。"""
    CURRENT_DIR.mkdir(parents=True, exist_ok=True)
    INDEX_DIR.mkdir(parents=True, exist_ok=True)
    BLOBS_DIR.mkdir(parents=True, exist_ok=True)
    fname = f'{today_id()}.jsonl'
    return str((CURRENT_DIR / fname).relative_to(ROOT))


def extract_feishu_user_text(raw: str) -> str:
    """
    从飞书消息原始文本中提取真实用户消息。

    实际格式（OpenClaw 注入的 metadata 包装）：
    Conversation info (untrusted metadata):
    ```json
    {...}
    ```
    Sender (untrusted metadata):
    ```json
    {...}
    ```
    [message_id: om_xxx]
    徐枫: 实际消息文本
    """
    if not raw or len(raw.strip()) == 0:
        return raw

    # 匹配 [message_id: xxx]\n徐枫: 实际内容 格式（飞书标准消息）
    m = re.search(r'\[message_id:\s*[^\]]+\]\s*\n?徐枫:\s*(.+)$', raw, re.DOTALL)
    if m:
        text = m.group(1).strip()
        if text:
            return text

    # 兜底：如果 raw 是 JSON，尝试解析 content/text 字段
    if raw.lstrip().startswith('{'):
        try:
            obj = json.loads(raw)
            content = obj.get('content', '')
            if content:
                try:
                    inner = json.loads(content)
                    text = inner.get('text', '')
                    if text and text.strip():
                        return text.strip()
                except (json.JSONDecodeError, TypeError):
                    pass
            text = obj.get('text', '')
            if text and text.strip():
                return text.strip()
        except (json.JSONDecodeError, TypeError):
            pass

    # 无法识别，返回原始截断
    return raw[:500] if len(raw) > 500 else raw


def write_blob(text: str, msg_id: str) -> pathlib.Path:
    blob_path = BLOBS_DIR / f'{msg_id}.txt'
    blob_path.write_text(text, encoding='utf-8')
    return blob_path


def main():
    p = argparse.ArgumentParser(
        description='Append one chat message to session journal (JSONL).'
    )
    p.add_argument('--role', required=True, choices=['user', 'assistant', 'system', 'tool'])
    p.add_argument('--channel', default='feishu')
    p.add_argument('--session-id', default=None)  # 传入但忽略，保留兼容
    p.add_argument('--reply-to', default=None)
    p.add_argument('--meta-json', default=None)
    p.add_argument('--text-file', default=None)
    args = p.parse_args()

    if args.text_file:
        text = pathlib.Path(args.text_file).read_text(encoding='utf-8')
    else:
        text = sys.stdin.read()

    if not text:
        raise SystemExit('empty message text')

    # 对用户消息，提取真实文本（去掉飞书 metadata 包装）
    if args.role == 'user':
        text = extract_feishu_user_text(text)

    # journal 路径按日期，不跟踪 session
    journal_rel = journal_path_by_date()
    journal_path = ROOT / journal_rel

    # 读 state 只是为了拿 seq 编号，不做文件路由
    state_file = STATE_DIR / 'current-session.json'
    state_file.parent.mkdir(parents=True, exist_ok=True)
    if state_file.exists():
        with state_file.open('r', encoding='utf-8') as f:
            state = json.load(f)
    else:
        state = {'seq': 0}

    seq = int(state.get('seq', 0)) + 1
    state['seq'] = seq
    state['last_appended_at'] = now_local_iso()
    with state_file.open('w', encoding='utf-8') as f:
        json.dump(state, f, ensure_ascii=False, indent=2)

    msg_id = f"{args.role[0]}-{seq:06d}-{uuid.uuid4().hex[:8]}"
    meta = {}
    if args.meta_json:
        try:
            meta = json.loads(args.meta_json)
        except:
            pass

    text_bytes = text.encode('utf-8')
    text_size = len(text_bytes)
    text_value = text
    meta['size_bytes'] = text_size

    if text_size > SIZE_THRESHOLD:
        blob_path = write_blob(text, msg_id)
        blob_rel = str(blob_path.relative_to(ROOT))
        text_value = None
        meta['blob_path'] = blob_rel
        meta['blob_size_bytes'] = text_size
        meta['blob_sha256_prefix'] = hashlib.sha256(text_bytes).hexdigest()[:16]

    rec = {
        'ts': now_local_iso(),
        'session_id': state.get('session_id', 'unknown'),
        'channel': args.channel,
        'role': args.role,
        'msg_id': msg_id,
        'reply_to': args.reply_to,
        'text': text_value,
        'meta': meta,
    }

    with journal_path.open('a', encoding='utf-8') as f:
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')
        f.flush()
        os.fsync(f.fileno())

    print(json.dumps({
        'ok': True,
        'msg_id': msg_id,
        'journal_path': journal_rel,
    }))


if __name__ == '__main__':
    main()
