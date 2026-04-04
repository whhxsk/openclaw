#!/bin/bash
# douyin-cdp: 用 Chromium 远程调试法下载抖音视频
# 用法: bash download.sh "<douyin_url>"
set -e

DOUYIN_URL="$1"
MEDIA_DIR="/home/xiwang/.openclaw/media"
WORK_DIR="/home/xiwang/.openclaw/workspace"
TMP_DIR="/tmp/douyin-cdp-$$"

if [ -z "$DOUYIN_URL" ]; then
  echo "用法: $0 <douyin_url>"
  exit 1
fi

mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "[douyin-cdp] 启动 Chromium..."
killall -9 chrome chromium 2>/dev/null || true
sleep 2

/snap/bin/chromium "$DOUYIN_URL" \
  --disable-gpu \
  --no-sandbox \
  --disable-dev-shm-usage \
  --remote-debugging-port=9222 \
  --user-data-dir="$TMP_DIR/chromium-profile" \
  > /tmp/douyin-cdp-chromium.log 2>&1 &

echo "[douyin-cdp] 等待浏览器启动..."
sleep 8

# 检查端口是否就绪
for i in $(seq 1 10); do
  if curl -s http://127.0.0.1:9222/json > /dev/null 2>&1; then
    echo "[douyin-cdp] CDP 端口就绪"
    break
  fi
  echo "[douyin-cdp] 等待端口... ($i/10)"
  sleep 2
done

# 用 node + playwright 提取 video src
echo "[douyin-cdp] 提取视频直链..."

node - << 'NODEEOF'
const { chromium } = require('playwright');

(async () => {
  let browser;
  try {
    browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
    const ctx = browser.contexts()[0];
    const pages = ctx.pages();
    const page = pages.find(p => p.url().includes('douyin.com/video')) || pages[0];

    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(4000);

    const videoUrl = await page.evaluate(() => {
      const v = document.querySelector('video');
      if (!v) return null;
      const src = v.querySelector('source[src]');
      return src ? src.src : (v.currentSrc || v.src);
    });

    if (videoUrl) {
      console.log('VIDEO_URL=' + videoUrl);
    } else {
      console.log('VIDEO_URL=');
      console.log('ERROR=未能提取到视频直链');
    }

    await browser.close();
  } catch(e) {
    console.log('ERROR=' + e.message);
    if (browser) await browser.close().catch(() => {});
    process.exit(1);
  }
})();
NODEEOF

VIDEO_URL=$(grep "VIDEO_URL=" /dev/stdin | tail -1 | sed 's/VIDEO_URL=//')

if [ -z "$VIDEO_URL" ]; then
  echo "[douyin-cdp] 提取失败，尝试备用等待..."
  sleep 5
  # retry once
  node - << 'NODEEOF2'
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
  const ctx = browser.contexts()[0];
  const pages = ctx.pages();
  const page = pages.find(p => p.url().includes('douyin.com/video')) || pages[0];
  await page.bringToFront();
  await page.waitForTimeout(3000);
  const videoUrl = await page.evaluate(() => {
    const v = document.querySelector('video');
    if (!v) return null;
    return v.currentSrc || v.src || null;
  });
  console.log('VIDEO_URL=' + (videoUrl || ''));
  await browser.close();
})();
NODEEOF2
fi

# 杀掉 chromium
killall -9 chrome chromium 2>/dev/null || true

# 下载视频
FILENAME="douyin_$(date +%Y%m%d_%H%M%S).mp4"
DEST="$MEDIA_DIR/$FILENAME"

echo "[douyin-cdp] 下载视频到 $DEST ..."

if curl -L -o "$DEST" "$VIDEO_URL" 2>&1 | tail -2; then
  SIZE=$(stat -c%s "$DEST" 2>/dev/null || echo "0")
  echo "[douyin-cdp] 下载完成，大小: $SIZE bytes"
  echo "OUTPUT_FILE=$DEST"
else
  echo "[douyin-cdp] 下载失败"
  exit 1
fi

rm -rf "$TMP_DIR"
