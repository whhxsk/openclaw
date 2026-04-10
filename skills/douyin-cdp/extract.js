/**
 * douyin-cdp-extract.js
 * 通过 Chromium CDP 远程调试提取抖音视频直链
 * 等待 video 元素完全加载后再提取，确保拿到完整视频而非预览片段
 */
const { chromium } = require('playwright');

async function main() {
  let browser;
  try {
    browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
    const contexts = browser.contexts();
    if (!contexts.length) {
      console.log('ERROR=没有浏览器上下文');
      process.exit(1);
    }

    const pages = contexts[0].pages();
    const page = pages.find(p => /douyin\.com\/video/.test(p.url())) || pages[0];

    if (!page) {
      console.log('ERROR=没找到抖音视频页面');
      process.exit(1);
    }

    await page.bringToFront();
    await page.waitForLoadState('domcontentloaded');

    // 等待 video 元素出现（最多等15秒）
    try {
      await page.waitForSelector('video', { timeout: 15000 });
    } catch(e) {
      console.log('ERROR=视频元素未出现');
      await browser.close();
      process.exit(1);
    }

    // 等待视频加载完成：检测 duration 和 readyState
    // duration > 1 表示不是预览片段；readyState >= 3 表示至少数据已加载
    let videoInfo = null;
    for (let i = 0; i < 10; i++) {
      videoInfo = await page.evaluate(() => {
        const v = document.querySelector('video');
        if (!v) return null;
        return {
          src: v.currentSrc || v.src || null,
          duration: v.duration,
          readyState: v.readyState
        };
      });
      if (videoInfo && videoInfo.src && videoInfo.duration > 1 && videoInfo.readyState >= 3) {
        break;
      }
      await page.waitForTimeout(1500);
    }

    if (videoInfo && videoInfo.src) {
      console.log(videoInfo.src);
    } else {
      console.log('ERROR=未能提取到视频直链');
      process.exit(1);
    }

    await browser.close();
  } catch(e) {
    console.log('ERROR=' + e.message);
    if (browser) await browser.close().catch(() => {});
    process.exit(1);
  }
}

main();
