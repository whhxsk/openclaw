#!/usr/bin/env node
/**
 * douyin-cdp-extract.js
 * 通过 Chromium CDP 远程调试提取抖音视频直链
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
    await page.waitForTimeout(4000);

    const videoUrl = await page.evaluate(() => {
      const v = document.querySelector('video');
      if (!v) return null;
      const src = v.querySelector('source[src]');
      return src ? src.src : (v.currentSrc || v.src || null);
    });

    if (videoUrl) {
      console.log(videoUrl);
    } else {
      // 重试一次，等更久
      await page.waitForTimeout(3000);
      const retry = await page.evaluate(() => {
        const v = document.querySelector('video');
        return v ? (v.currentSrc || v.src || null) : null;
      });
      console.log(retry || 'ERROR=未能提取到视频直链');
    }

    await browser.close();
  } catch (e) {
    console.log('ERROR=' + e.message);
    if (browser) await browser.close().catch(() => {});
    process.exit(1);
  }
}

main();
