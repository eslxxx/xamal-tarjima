/**
 * 真实视口截图工具 —— 用 CDP 设备模拟驱动本机 Chrome。
 *
 * Edge/Chrome 无头模式在 Windows 上有 ~500px 最小窗口宽度,
 * --window-size=412 会被强制拉宽到 504+, 根本测不了手机布局。
 * puppeteer-core 的 setViewport 走 Emulation.setDeviceMetricsOverride,
 * 不受窗口最小值限制, 才是可信的手机渲染。
 *
 * 用法:
 *   node shot.js <url> <输出.png> [宽] [高] [dark] [fullpage]
 *   宽高默认 412x1750; dark=1 模拟深色模式; fullpage=1 截整页
 * 输出 scrollWidth 到 stdout —— 大于视口宽就是真溢出。
 */
const puppeteer = require('puppeteer-core');

const CHROME = 'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe';

(async () => {
  const [url, out, w = '412', h = '1750', dark = '0', full = '0'] = process.argv.slice(2);
  if (!url || !out) {
    console.error('用法: node shot.js <url> <输出.png> [宽] [高] [dark] [fullpage]');
    process.exit(1);
  }

  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    args: ['--disable-gpu', '--hide-scrollbars'],
  });
  try {
    const page = await browser.newPage();
    await page.setViewport({
      width: +w,
      height: +h,
      deviceScaleFactor: 1,
      isMobile: true,
      hasTouch: true,
    });
    if (dark === '1') {
      await page.emulateMediaFeatures([
        { name: 'prefers-color-scheme', value: 'dark' },
      ]);
    }
    await page.goto(url, { waitUntil: 'networkidle0', timeout: 45000 });
    await new Promise((r) => setTimeout(r, 600));
    await page.screenshot({ path: out, fullPage: full === '1' });
    const sw = await page.evaluate(() => document.documentElement.scrollWidth);
    console.log(`scrollWidth=${sw} viewport=${w} ${sw > +w ? '!! 有水平溢出 !!' : '无水平溢出'}`);
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
