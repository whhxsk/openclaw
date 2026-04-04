#!/usr/bin/env python3
"""
OpenClaw Journal Sync Daemon
监控 session transcript 文件变化，有新内容时实时同步到 journal
"""
import json, time, os, subprocess, sys
from pathlib import Path
from datetime import datetime, timezone, timedelta

WORKSPACE = Path(os.environ.get('OPENCLAW_JOURNAL_WORKSPACE', '/home/xiwang/.openclaw/workspace'))
SESSIONS_DIR = Path(os.environ.get('OPENCLAW_JOURNAL_WORKSPACE', '/home/xiwang/.openclaw/workspace')).parent / 'agents/main/sessions'
SESSIONS_JSON = SESSIONS_DIR / 'sessions.json'
JOURNAL_CURRENT = WORKSPACE / 'journals' / 'current'
POLL_INTERVAL = 3  # 秒
LOG = WORKSPACE / 'logs' / 'journal-sync-daemon.log'

def log(msg):
    ts = datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S')
    txt = f"[{ts}] {msg}"
    print(txt)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    LOG.open('a').write(txt + '\n')

def get_current_session_uuid():
    try:
        with open(SESSIONS_JSON) as f:
            sessions = json.load(f)
        return sessions.get('agent:main:main', {}).get('sessionId', '')
    except:
        return ''

def get_session_file(uuid):
    if not uuid:
        return None
    p = SESSIONS_DIR / f'{uuid}.jsonl'
    return p if p.exists() else None

def get_journal_file():
    today = datetime.now().astimezone().strftime('%Y%m%d')
    return JOURNAL_CURRENT / f'{today}.jsonl'

def sync_messages(session_file, journal_file, session_uuid):
    seen_ids = set()
    if journal_file.exists():
        with open(journal_file) as f:
            for line in f:
                try:
                    seen_ids.add(json.loads(line).get('msg_id'))
                except:
                    pass

    new_entries = []
    try:
        with open(session_file) as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except:
                    continue
                if rec.get('type') != 'message':
                    continue
                msg = rec.get('message', {})
                role = msg.get('role')
                if role not in ('user', 'assistant'):
                    continue
                content = msg.get('content', '')
                if isinstance(content, list):
                    texts = [c.get('text', '') for c in content if c.get('type') == 'text']
                    text = ' '.join(texts)
                else:
                    text = str(content) if content else ''
                if not text or len(text.strip()) == 0:
                    continue
                if 'HEARTBEAT_OK' in text or text.startswith('Read HEARTBEAT.md'):
                    continue
                msg_internal_id = rec.get('id', '')
                if not msg_internal_id:
                    continue
                journal_msg_id = f"{role[0]}-{msg_internal_id}"
                if journal_msg_id in seen_ids:
                    continue
                ts = rec.get('timestamp', '')
                if ts:
                    try:
                        utc_dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
                        local_tz = timezone(timedelta(hours=8))
                        local_dt = utc_dt.astimezone(local_tz)
                        ts = local_dt.isoformat(timespec='seconds')
                    except:
                        pass
                size = len(text.encode('utf-8'))
                threshold = 1 * 1024 * 1024
                entry = {
                    'ts': ts,
                    'session_id': session_uuid,
                    'channel': 'feishu',
                    'role': role,
                    'msg_id': journal_msg_id,
                    'reply_to': None,
                    'text': text if size <= threshold else None,
                    'meta': {'size_bytes': size, 'source': 'session-sync-daemon'}
                }
                if size > threshold:
                    blob_dir = journal_file.parent / 'journals' / 'blobs'
                    blob_dir.mkdir(parents=True, exist_ok=True)
                    blob_path = blob_dir / f"{journal_msg_id}.txt"
                    with open(blob_path, 'w', encoding='utf-8') as bf:
                        bf.write(text)
                    entry['text'] = None
                    entry['meta']['blob_path'] = str(blob_path.relative_to(journal_file.parent.parent))
                    entry['meta']['blob_size_bytes'] = size
                    import hashlib
                    entry['meta']['blob_sha256_prefix'] = hashlib.sha256(text.encode()).hexdigest()[:16]
                new_entries.append(entry)
    except Exception as e:
        log(f'Error reading session: {e}')
        return 0

    if new_entries:
        journal_file.parent.mkdir(parents=True, exist_ok=True)
        with open(journal_file, 'a') as f:
            for e in new_entries:
                f.write(json.dumps(e, ensure_ascii=False) + '\n')
        log(f'Synced {len(new_entries)} new messages')
    return len(new_entries)

def main():
    log('Daemon started')
    last_uuid = ''
    last_mtime = 0
    last_sync_time = 0

    while True:
        try:
            uuid = get_current_session_uuid()
            session_file = get_session_file(uuid)

            if session_file and session_file.exists():
                current_mtime = session_file.stat().st_mtime

                # 检测到文件变化 且 距离上次同步超过3秒
                if (current_mtime != last_mtime or uuid != last_uuid) and (time.time() - last_sync_time) > 3:
                    journal_file = get_journal_file()
                    count = sync_messages(session_file, journal_file, uuid)
                    last_mtime = current_mtime
                    last_uuid = uuid
                    last_sync_time = time.time()

        except Exception as e:
            log(f'Poll error: {e}')

        time.sleep(POLL_INTERVAL)

if __name__ == '__main__':
    main()
