const http = require('http');
const https = require('https');
const { EventEmitter } = require('events');
const { spawn } = require('child_process');
const crypto = require('crypto');

const WORKSPACE = process.env.OPENCLAW_JOURNAL_WORKSPACE || '/home/xiwang/.openclaw/workspace';
const JOURNAL_SCRIPT = `${WORKSPACE}/scripts/journal_append.py`;
const CHANNEL = process.env.OPENCLAW_JOURNAL_CHANNEL || 'feishu';
const LOG_FILE = process.env.OPENCLAW_JOURNAL_HOOK_LOG || `${WORKSPACE}/logs/journal-hook.log`;
const MAX_CACHE = 200;
const seen = new Map();
const seenInboundIds = new Set();

function ensureParentDir(path) {
  try {
    require('fs').mkdirSync(require('path').dirname(path), { recursive: true });
  } catch {}
}

function logLine(msg) {
  try {
    ensureParentDir(LOG_FILE);
    require('fs').appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${msg}\n`);
  } catch {}
}

function remember(hash) {
  seen.set(hash, Date.now());
  if (seen.size > MAX_CACHE) {
    const first = seen.keys().next();
    if (!first.done) seen.delete(first.value);
  }
}

function dedupe(text) {
  const hash = crypto.createHash('sha1').update(text).digest('hex');
  if (seen.has(hash)) return true;
  remember(hash);
  return false;
}

function appendMessage(role, text, meta = {}) {
  if (!text || !String(text).trim()) return;
  const normalized = String(text).trim();
  if (normalized === 'NO_REPLY' || normalized === 'HEARTBEAT_OK') return;
  if (role === 'assistant' && dedupe(normalized)) return;

  const args = [
    JOURNAL_SCRIPT,
    '--role', role,
    '--channel', CHANNEL,
    '--meta-json', JSON.stringify(meta),
  ];

  const child = spawn('python3', args, {
    stdio: ['pipe', 'ignore', 'ignore'],
    detached: false,
  });
  child.on('error', (err) => logLine(`spawn error: ${err.message}`));
  child.stdin.end(normalized);
}

function appendAssistant(text, meta = {}) {
  appendMessage('assistant', text, meta);
}

function appendUser(text, meta = {}) {
  const messageId = meta && meta.message_id;
  if (messageId) {
    if (seenInboundIds.has(messageId)) return;
    seenInboundIds.add(messageId);
    if (seenInboundIds.size > MAX_CACHE) {
      const first = seenInboundIds.values().next();
      if (!first.done) seenInboundIds.delete(first.value);
    }
  }
  appendMessage('user', text, meta);
}

function safeJsonParse(s) {
  try { return JSON.parse(s); } catch { return null; }
}

function extractFeishuText(payload) {
  if (!payload || typeof payload !== 'object') return null;
  const messageType = payload.msg_type || payload.msgType || payload.message_type;
  const contentRaw = payload.content;
  let content = contentRaw;

  if (typeof contentRaw === 'string') {
    const parsed = safeJsonParse(contentRaw);
    if (parsed) content = parsed;
  }

  if (messageType === 'text') {
    if (content && typeof content.text === 'string') return content.text;
    if (typeof contentRaw === 'string') return contentRaw;
  }

  if (messageType === 'post' && content && typeof content === 'object') {
    try {
      const parts = [];
      const zh = content.zh_cn || content.en_us || Object.values(content)[0];
      if (zh && Array.isArray(zh.content)) {
        for (const line of zh.content) {
          if (!Array.isArray(line)) continue;
          for (const item of line) {
            if (item && typeof item.text === 'string') parts.push(item.text);
          }
        }
      }
      if (parts.length) return parts.join('');
    } catch {}
  }

  if (messageType === 'interactive') {
    return '[interactive card]';
  }

  if (typeof contentRaw === 'string' && contentRaw.trim()) return contentRaw;
  return null;
}

function extractInboundEnvelope(obj) {
  if (!obj || typeof obj !== 'object') return null;

  const candidates = [];
  if (obj.event && typeof obj.event === 'object') candidates.push(obj.event);
  if (obj.message && typeof obj.message === 'object') candidates.push(obj);
  if (Array.isArray(obj.args)) candidates.push(...obj.args.filter((x) => x && typeof x === 'object'));

  for (const candidate of candidates) {
    const message = candidate.message || candidate;
    const sender = candidate.sender || message.sender || candidate.user || {};
    const header = obj.header || candidate.header || {};
    const eventType = header.event_type || obj.event_type || candidate.event_type || '';
    const messageId = message.message_id || message.messageId;
    const chatId = message.chat_id || message.chatId;
    const messageType = message.message_type || message.msg_type || message.msgType;
    const senderType = sender.sender_type || sender.senderType || '';
    const content = message.content;

    const looksLikeFeishuMessage = Boolean(messageId && chatId && content !== undefined);
    const isReceiveEvent = !eventType || String(eventType).includes('message.receive');
    const isAssistant = String(senderType).toUpperCase() === 'ASSISTANT';

    if (looksLikeFeishuMessage && isReceiveEvent && !isAssistant) {
      return {
        text: extractFeishuText({ message_type: messageType, content }),
        meta: {
          source: 'feishu-inbound-emit-hook',
          event_type: eventType || 'im.message.receive_v1',
          message_id: messageId,
          chat_id: chatId,
          message_type: messageType,
          sender_type: senderType || 'user',
        },
      };
    }
  }

  return null;
}

function patch(mod, scheme) {
  const original = mod.request;
  if (!original || original.__journalPatched) return;

  function wrappedRequest(...args) {
    const req = original.apply(this, args);

    try {
      const chunks = [];
      const origWrite = req.write;
      const origEnd = req.end;

      req.write = function (chunk, encoding, cb) {
        if (chunk) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, encoding));
        return origWrite.call(this, chunk, encoding, cb);
      };

      req.end = function (chunk, encoding, cb) {
        if (chunk) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, encoding));
        return origEnd.call(this, chunk, encoding, cb);
      };

      req.on('response', (res) => {
        try {
          const host = req.getHeader && req.getHeader('host') || req.host || req._headers?.host || '';
          const path = req.path || req._path || '';
          const method = (req.method || '').toUpperCase();
          const isFeishu = String(host).includes('open.feishu.cn') || String(host).includes('feishu.cn');
          const isSendApi = /\/open-apis\/im\/v1\/messages(\/[^/]+\/reply)?(\?|$)/.test(String(path));
          if (!isFeishu || !isSendApi || !['POST', 'PATCH'].includes(method)) return;

          const respChunks = [];
          res.on('data', (d) => respChunks.push(Buffer.isBuffer(d) ? d : Buffer.from(d)));
          res.on('end', () => {
            try {
              const body = Buffer.concat(chunks).toString('utf8');
              const payload = safeJsonParse(body);
              const responseBody = Buffer.concat(respChunks).toString('utf8');
              const responseJson = safeJsonParse(responseBody);
              const ok = res.statusCode && res.statusCode >= 200 && res.statusCode < 300 && (!responseJson || responseJson.code === 0 || responseJson.StatusCode === 0);
              if (!ok) return;

              const text = extractFeishuText(payload);
              if (!text) return;
              appendAssistant(text, {
                source: 'node-http-hook',
                scheme,
                path: String(path),
                method,
                status: res.statusCode,
              });
            } catch (err) {
              logLine(`response parse error: ${err.message}`);
            }
          });
        } catch (err) {
          logLine(`response hook error: ${err.message}`);
        }
      });
    } catch (err) {
      logLine(`request hook error: ${err.message}`);
    }

    return req;
  }

  wrappedRequest.__journalPatched = true;
  mod.request = wrappedRequest;
}

patch(http, 'http');
patch(https, 'https');

const originalEmit = EventEmitter.prototype.emit;
if (!originalEmit.__journalPatched) {
  EventEmitter.prototype.emit = function journalAwareEmit(eventName, ...args) {
    try {
      for (const arg of args) {
        const inbound = extractInboundEnvelope(arg);
        if (inbound && inbound.text) {
          appendUser(inbound.text, inbound.meta);
          break;
        }
      }
    } catch (err) {
      logLine(`emit hook error: ${err.message}`);
    }
    return originalEmit.call(this, eventName, ...args);
  };
  EventEmitter.prototype.emit.__journalPatched = true;
}

logLine('assistant+user journal hook loaded');
