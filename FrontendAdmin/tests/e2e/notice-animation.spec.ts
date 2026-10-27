import { expect, test, type Page } from '@playwright/test';
import { engagementId, installProtocol, loginProtocol, navigate, requestId } from './protocol-fixture';

type MotionFrame = { opacity: number; height: number; className: string; overflow: number };

// Sample actual rendered frames, including the leave interval while the DOM must remain mounted.
// A timeout is only a failure bound; animation progress never depends on a fixed sleep.
function sampleMotion(page: Page, selector: string, phase: 'enter' | 'leave') {
  return page.evaluate(({ selector, phase }) => new Promise<MotionFrame[]>((resolve, reject) => {
    const frames: MotionFrame[] = [];
    const started = performance.now();
    let element: Element | null = null;
    function sample() {
      element ||= document.querySelector(selector);
      if (element && !element.isConnected) return resolve(frames);
      if (element) {
        const opacity = Number(getComputedStyle(element).opacity);
        const className = element.getAttribute('class') || '';
        frames.push({ opacity, height: element.getBoundingClientRect().height, className,
          overflow: Math.max(document.documentElement.scrollHeight - innerHeight,
            document.documentElement.scrollWidth - innerWidth, Math.abs(scrollY)) });
        if (phase === 'enter' && opacity >= .999 && !className.includes('notice-fade-enter')) return resolve(frames);
      }
      if (performance.now() - started > 1800) return reject(new Error(`Notice ${phase} did not finish: ${selector}`));
      requestAnimationFrame(sample);
    }
    requestAnimationFrame(sample);
  }), { selector, phase });
}

function expectSmoothFrames(frames: MotionFrame[], phase: 'enter' | 'leave') {
  const moving = frames.filter(frame => frame.opacity > .01 && frame.opacity < .99);
  expect(moving.length, `${phase} must render intermediate opacity while still mounted`).toBeGreaterThan(0);
  expect(Math.max(...frames.map(frame => frame.height)) - Math.min(...frames.map(frame => frame.height)),
    `${phase} must animate occupied height as well as opacity`).toBeGreaterThan(5);
  expect(Math.max(...frames.map(frame => frame.overflow))).toBeLessThanOrEqual(1);
}

async function fixedDocument(page: Page) {
  await expect.poll(() => page.evaluate(() => Math.max(document.documentElement.scrollHeight - innerHeight,
    document.documentElement.scrollWidth - innerWidth, Math.abs(scrollY)))).toBeLessThanOrEqual(1);
}

test('页头警告真实淡入淡出，关闭过程释放模块高度且页面不滚动', async ({ page }) => {
  await page.setViewportSize({ width: 1920, height: 1080 });
  const backend = await installProtocol(page);
  backend.request.reviews = [];
  await loginProtocol(page);
  const selector = '#page-notices .notice-transition-shell[data-theme="warning"]';
  const entering = sampleMotion(page, selector, 'enter');
  await navigate(page, `/publishing?id=${requestId}`);
  expectSmoothFrames(await entering, 'enter');
  const notice = page.locator(selector);
  await expect(notice).toHaveText('当前版本尚未通过两项审核，不能发布。');
  const before = await page.locator('.page-module').evaluate(element => element.getBoundingClientRect().height);
  const leaving = sampleMotion(page, selector, 'leave');
  await notice.getByRole('button', { name: '关闭', exact: true }).click();
  expectSmoothFrames(await leaving, 'leave');
  await expect(notice).toHaveCount(0);
  const after = await page.locator('.page-module').evaluate(element => element.getBoundingClientRect().height);
  expect(after - before).toBeGreaterThan(20);
  await fixedDocument(page);
  expect(backend.unknown).toEqual([]);
});

test('弹窗校验支持键盘淡出、再次出现和离场途中重新校验', async ({ page }) => {
  await page.setViewportSize({ width: 1920, height: 1080 });
  const backend = await installProtocol(page);
  await loginProtocol(page, `/publishing?id=${requestId}`);
  await page.getByRole('button', { name: '发布 v1', exact: true }).click();
  const dialog = page.locator('.t-dialog:visible');
  const confirm = dialog.getByRole('button', { name: '确认', exact: true });
  const error = dialog.locator('.notice-transition-shell[data-theme="error"]');
  await confirm.click();
  await expect(error).toHaveText('请填写原因或审核备注。');
  await expect(error).toHaveCSS('opacity', '1');
  const selector = '.t-dialog .notice-transition-shell[data-theme="error"]';
  const leaving = sampleMotion(page, selector, 'leave');
  await error.getByRole('button', { name: '关闭', exact: true }).focus();
  await page.keyboard.press('Enter');
  expectSmoothFrames(await leaving, 'leave');
  await expect(error).toHaveCount(0);
  const entering = sampleMotion(page, selector, 'enter');
  await confirm.click();
  expectSmoothFrames(await entering, 'enter');

  // Trigger the same validation while the old instance is visibly leaving. The reset key
  // must cancel dismissal rather than letting its after-leave callback remove the new error.
  const opacityAtReopen = await error.getByRole('button', { name: '关闭', exact: true }).evaluate(button =>
    new Promise<number>((resolve, reject) => {
      const shell = button.closest('.notice-transition-shell')!;
      const dialog = button.closest('.t-dialog')!;
      const confirm = Array.from(dialog.querySelectorAll('button')).find(item => item.textContent?.trim() === '确认')!;
      const started = performance.now();
      (button as HTMLButtonElement).click();
      function reopen() {
        const opacity = Number(getComputedStyle(shell).opacity);
        if (opacity > .05 && opacity < .95) { confirm.click(); resolve(opacity); return; }
        if (performance.now() - started > 800) { reject(new Error('No visible leave interval to revalidate')); return; }
        requestAnimationFrame(reopen);
      }
      requestAnimationFrame(reopen);
    }));
  expect(opacityAtReopen).toBeGreaterThan(0);
  expect(opacityAtReopen).toBeLessThan(1);
  await expect(error).toHaveCount(1);
  await expect(error).toHaveCSS('opacity', '1');
  await expect(error).not.toHaveClass(/notice-fade-(enter|leave)/);
  await expect(page.locator('#page-notices .t-alert--error')).toHaveCount(0);
  await dialog.getByRole('button', { name: '取消', exact: true }).click();
  await fixedDocument(page);
  expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});

test('暗色日语通知条目淡出并更新计数，减少动态效果时立即关闭', async ({ page }) => {
  await page.setViewportSize({ width: 1536, height: 864 });
  await page.addInitScript(() => {
    localStorage.setItem('opc.admin.locale', 'ja-JP');
    localStorage.setItem('opc.admin.theme', 'dark');
  });
  const backend = await installProtocol(page);
  await loginProtocol(page, `/delivery?id=${engagementId}`);
  await page.locator('.notification-trigger').click();
  const center = page.locator('.notification-center');
  await expect(center.locator('.context-notification')).toHaveCount(2);
  const first = center.locator('.context-notification').first();
  const firstText = await first.innerText();
  await expect(center.locator('.notice-transition-shell').first()).toHaveCSS('opacity', '1');
  const leaving = sampleMotion(page, '.context-notification-list .notice-transition-shell', 'leave');
  await first.getByRole('button', { name: '閉じる', exact: true }).click();
  expectSmoothFrames(await leaving, 'leave');
  await expect(center.locator('.context-notification')).toHaveCount(1);
  await expect(center.locator('.context-notification')).not.toHaveText(firstText);
  await expect(center.locator('.t-tabs__nav-item').filter({ hasText: /^ページの説明/ })).toContainText('(1)');

  await page.emulateMedia({ reducedMotion: 'reduce' });
  const remaining = center.locator('.notice-transition-shell');
  await expect(remaining).toHaveCSS('transition-duration', '0s');
  await remaining.getByRole('button', { name: '閉じる', exact: true }).click();
  await expect(remaining).toHaveCount(0);
  await expect(center.locator('.t-tabs__nav-item').filter({ hasText: /^ページの説明/ })).toContainText('(0)');
  await expect(center.locator('.t-empty')).toBeVisible();
  await fixedDocument(page);
  expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});
