import { expect, test, type Page } from '@playwright/test';
import { writeFile } from 'node:fs/promises';
import { installProtocol, loginProtocol, navigate, requestId } from './protocol-fixture';

const viewports = [{ width: 1920, height: 1080 }, { width: 1536, height: 864 }];

async function dimensions(page: Page) {
  return page.evaluate(() => {
    const box = (selector: string) => {
      const element = document.querySelector(selector);
      if (!element) throw new Error('Missing measured element: ' + selector);
      const rect = element.getBoundingClientRect(), style = getComputedStyle(element);
      return { x: rect.x, y: rect.y, width: rect.width, height: rect.height, fontSize: style.fontSize };
    };
    const textRange = document.createRange();
    textRange.selectNodeContents(document.querySelector('.side-menu .nav-item-label')!);
    const textRect = textRange.getBoundingClientRect();
    const keyword = document.querySelector('.keyword-field')!.getBoundingClientRect();
    const nextField = document.querySelector('.table-toolbar .filter-field:not(.keyword-field)')!.getBoundingClientRect();
    const toolbar = document.querySelector('.table-toolbar')!.getBoundingClientRect();
    const cardBody = document.querySelector('.section-card .t-card__body')!.getBoundingClientRect();
    return {
      viewport: { width: innerWidth, height: innerHeight },
      document: { width: document.documentElement.clientWidth, scrollWidth: document.documentElement.scrollWidth },
      sidebar: box('.app-sidebar'), header: box('.app-header'), menu: box('.side-menu .t-menu__item'),
      button: box('.table-toolbar button[type="submit"]'), row: box('.t-table tbody tr'),
      input: box('.keyword-field .t-input'), renderedText: { width: textRect.width, height: textRect.height },
      spacing: { toolbarGap: nextField.x - keyword.right, cardPadding: toolbar.x - cardBody.x },
    };
  });
}

async function stableShell(page: Page) {
  await expect.poll(async () => {
    const sidebar = await page.locator('.app-sidebar').boundingBox();
    const header = await page.locator('.app-header').boundingBox();
    return sidebar && header ? Math.abs(header.x - sidebar.width) : Infinity;
  }).toBeLessThanOrEqual(1);
}

async function setScale(page: Page, scale: number) {
  await page.locator('.scale-select').click();
  await page.getByRole('listitem', { name: `${scale}%`, exact: true }).click();
  await expect(page.locator('html')).toHaveAttribute('data-admin-scale', String(scale / 100));
  await expect.poll(() => page.evaluate(() => localStorage.getItem('opc.admin.scale'))).toBe(String(scale));
  await stableShell(page);
}

async function noDocumentOverflow(page: Page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
}

async function installLongAudit(page: Page) {
  await page.route('**/api/v1/admin/audit-events?*', route => route.fulfill({
    headers: { 'access-control-allow-origin': '*' }, contentType: 'application/json',
    body: JSON.stringify({ items: Array.from({ length: 50 }, (_, index) => ({
      id: 1000 - index, occurred_at: '2026-10-22T01:00:00Z', application_actor_id: '10000000-0000-4000-8000-000000000001',
      correlation_id: 'scale-scroll-' + index, table_name: 'requests', operation: 'UPDATE',
      entity_key: { id: requestId, row: index }, changed_fields: ['intake_status'], details: {},
    })) }),
  }));
}

async function scrollList(page: Page, top: number) {
  const content = page.locator('.scroll-table .t-table__content').first();
  await expect.poll(() => content.evaluate(element => element.scrollHeight - element.clientHeight)).toBeGreaterThan(100);
  await content.evaluate((element, value) => { element.scrollTop = value; }, top);
  await expect.poll(() => content.evaluate(element => element.scrollTop)).toBeGreaterThan(top ? 0 : -1);
  expect(await page.evaluate(() => window.scrollY)).toBe(0);
}

async function fullViewport(page: Page, selector: string) {
  const viewport = page.viewportSize()!;
  const element = page.locator(selector).last();
  await expect(element).toBeVisible();
  await expect.poll(async () => {
    const bounds = await element.boundingBox();
    return bounds ? Math.max(Math.abs(bounds.x), Math.abs(bounds.y), Math.abs(bounds.width - viewport.width), Math.abs(bounds.height - viewport.height)) : Infinity;
  }).toBeLessThanOrEqual(1);
}

for (const viewport of viewports) for (const locale of ['zh-CN', 'ja-JP']) for (const theme of ['light', 'dark']) {
  test(`等比缩放 ${viewport.width}×${viewport.height} ${locale} ${theme}`, async ({ page }, testInfo) => {
    await page.setViewportSize(viewport);
    const backend = await installProtocol(page), errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(({ locale, theme }) => {
      localStorage.setItem('opc.admin.locale', locale);
      localStorage.setItem('opc.admin.theme', theme);
    }, { locale, theme });
    await loginProtocol(page, '/reviews');
    await expect(page.getByText('REQ-API-001', { exact: true }).first()).toBeVisible();
    await expect(page.locator('html')).toHaveAttribute('data-admin-scale', '0.8');
    await expect(page.locator('.scale-select')).toHaveAttribute('aria-label', locale === 'zh-CN' ? '界面缩放' : '表示倍率');
    await expect(page.locator('html')).toHaveAttribute('lang', locale);
    if (theme === 'dark') await expect(page.locator('html')).toHaveAttribute('theme-mode', 'dark');
    else await expect(page.locator('html')).not.toHaveAttribute('theme-mode', 'dark');

    await setScale(page, 100);
    const standard = await dimensions(page);
    await setScale(page, 80);
    const compact = await dimensions(page);
    for (const key of ['sidebar', 'header', 'menu', 'button', 'row', 'input'] as const) {
      const dimension = key === 'sidebar' ? 'width' : 'height';
      expect(Math.abs(compact[key][dimension] - standard[key][dimension] * 0.8), key + ' should scale by 80%').toBeLessThanOrEqual(1);
    }
    expect(Math.abs(compact.renderedText.height - standard.renderedText.height * 0.8)).toBeLessThanOrEqual(1);
    expect(Math.abs(compact.renderedText.width - standard.renderedText.width * 0.8)).toBeLessThanOrEqual(1);
    for (const key of ['toolbarGap', 'cardPadding'] as const) expect(Math.abs(compact.spacing[key] - standard.spacing[key] * 0.8), key).toBeLessThanOrEqual(1);
    expect(Math.abs(compact.sidebar.height - viewport.height)).toBeLessThanOrEqual(1);
    expect(Math.abs(compact.sidebar.x)).toBeLessThanOrEqual(1);
    expect(Math.abs(compact.sidebar.y)).toBeLessThanOrEqual(1);
    await noDocumentOverflow(page);
    const dimensionPath = testInfo.outputPath('dimensions-100-to-80.json');
    await writeFile(dimensionPath, JSON.stringify({ standard, compact }, null, 2));
    await testInfo.attach('dimensions-100-to-80', { path: dimensionPath, contentType: 'application/json' });
    await page.screenshot({ path: testInfo.outputPath('compact-reviews.png'), animations: 'disabled' });

    // Portal dropdown geometry is checked in screen coordinates, rather than in its CSS coordinate system.
    await page.locator('.locale-select').click();
    const popup = page.locator('.t-select__dropdown:visible');
    await expect(popup).toHaveCount(1);
    const popupGeometry = await page.evaluate(() => {
      const measure = (element: HTMLElement) => {
        const rect = element.getBoundingClientRect(), styles = getComputedStyle(element);
        return { tag: element.tagName, class: element.className, x: rect.x, y: rect.y, width: rect.width, height: rect.height,
          offsetWidth: element.offsetWidth, offsetHeight: element.offsetHeight, roundScaleX: Math.round(rect.width) / element.offsetWidth,
          roundScaleY: Math.round(rect.height) / element.offsetHeight, zoom: styles.zoom, position: styles.position, transform: styles.transform };
      };
      const trigger = document.querySelector('.locale-select') as HTMLElement;
      const popup = Array.from(document.querySelectorAll<HTMLElement>('.t-select__dropdown')).find(element => element.getBoundingClientRect().height > 0)!;
      return { trigger: measure(trigger), popup: measure(popup), popupOffsetParent: popup.offsetParent ? measure(popup.offsetParent as HTMLElement) : null,
        popupParent: popup.parentElement ? measure(popup.parentElement) : null, body: measure(document.body), root: measure(document.documentElement) };
    });
    await writeFile(testInfo.outputPath('popup-geometry.json'), JSON.stringify(popupGeometry, null, 2));
    await testInfo.attach('popup-geometry', { body: JSON.stringify(popupGeometry, null, 2), contentType: 'application/json' });
    await expect.poll(async () => {
      const trigger = await page.locator('.locale-select').boundingBox(), dropdown = await popup.boundingBox();
      return trigger && dropdown ? Math.abs(dropdown.x - trigger.x) : Infinity;
    }).toBeLessThanOrEqual(1);
    const trigger = (await page.locator('.locale-select').boundingBox())!, dropdown = (await popup.boundingBox())!;
    const gap = dropdown.y - (trigger.y + trigger.height);
    expect(gap).toBeGreaterThanOrEqual(-1);
    expect(gap).toBeLessThanOrEqual(20);
    await page.getByRole('listitem', { name: locale === 'ja-JP' ? '日本語' : '简体中文', exact: true }).click();

    // The real menu remains clickable after scaling and preserves navigation.
    await page.locator('.side-menu .t-menu__item').filter({ hasText: locale === 'ja-JP' ? '運営ダッシュボード' : '运营工作台' }).click();
    await expect(page).toHaveURL(/#\/dashboard$/);
    for (const route of ['/dashboard', '/reviews', `/technical?id=${requestId}`, `/publishing?id=${requestId}`]) {
      await navigate(page, route);
      await noDocumentOverflow(page);
      await expect(page.locator('html')).toHaveAttribute('data-admin-scale', '0.8');
      const sidebar = (await page.locator('.app-sidebar').boundingBox())!;
      expect(Math.abs(sidebar.height - viewport.height)).toBeLessThanOrEqual(1);
    }

    await page.getByRole('button', { name: locale === 'ja-JP' ? 'v1 を公開' : '发布 v1', exact: true }).click();
    const dialog = page.locator('.t-dialog:visible');
    await expect(dialog).toBeVisible();
    await fullViewport(page, '.t-dialog__mask:visible');
    await expect.poll(async () => {
      const bounds = await dialog.boundingBox();
      return bounds ? Math.abs(bounds.x + bounds.width / 2 - viewport.width / 2) : Infinity;
    }).toBeLessThanOrEqual(1);
    const dialogBounds = (await dialog.boundingBox())!;
    expect(dialogBounds.y).toBeGreaterThanOrEqual(0);
    expect(dialogBounds.y + dialogBounds.height).toBeLessThanOrEqual(viewport.height + 1);
    await dialog.locator('textarea').fill('缩放可操作性检查，仅取消，不写入服务端。');
    await expect(dialog.locator('textarea')).toHaveValue('缩放可操作性检查，仅取消，不写入服务端。');
    await page.screenshot({ path: testInfo.outputPath('compact-dialog.png'), animations: 'disabled' });
    await dialog.getByRole('button', { name: locale === 'ja-JP' ? 'キャンセル' : '取消', exact: true }).click();
    await expect(dialog).toHaveCount(0);

    await page.getByRole('button', { name: locale === 'ja-JP' ? '通知センター' : '通知中心', exact: true }).click();
    const drawer = page.locator('.t-drawer__content-wrapper:visible');
    await expect(drawer).toBeVisible();
    await fullViewport(page, '.t-drawer__mask:visible');
    await expect.poll(async () => {
      const bounds = await drawer.boundingBox();
      return bounds ? Math.max(Math.abs(bounds.x + bounds.width - viewport.width), Math.abs(bounds.y), Math.abs(bounds.height - viewport.height)) : Infinity;
    }).toBeLessThanOrEqual(1);
    await page.screenshot({ path: testInfo.outputPath('compact-drawer.png'), animations: 'disabled' });
    await page.locator('.t-drawer__close-btn:visible').click();
    await expect(drawer).toHaveCount(0);
    await noDocumentOverflow(page);

    // Auth remains memory-only, while display scale survives reload and is available on the login screen.
    await page.reload();
    await expect(page.locator('.login-card')).toBeVisible();
    await expect(page.locator('html')).toHaveAttribute('data-admin-scale', '0.8');
    await expect(page.locator('.scale-select')).toBeVisible();
    await noDocumentOverflow(page);
    expect(await page.evaluate(() => JSON.stringify({ local: { ...localStorage }, session: { ...sessionStorage } }))).not.toContain('protocol-token-memory-only');
    expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
    expect(errors).toEqual([]);
    expect(backend.unknown).toEqual([]);
  });
}

test('五档缩放均可选择并保存，刷新后恢复选择', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1920, height: 1080 });
  await installProtocol(page);
  await loginProtocol(page, '/reviews');
  await expect(page.getByText('REQ-API-001', { exact: true }).first()).toBeVisible();
  for (const scale of [75, 80, 85, 90, 100]) {
    await setScale(page, scale);
    await noDocumentOverflow(page);
    const sidebar = (await page.locator('.app-sidebar').boundingBox())!;
    expect(Math.abs(sidebar.width - 232 * scale / 100)).toBeLessThanOrEqual(1);
    expect(Math.abs(sidebar.height - 1080)).toBeLessThanOrEqual(1);
    await page.screenshot({ path: testInfo.outputPath('reviews-' + scale + '.png'), animations: 'disabled' });
  }
  await setScale(page, 85);
  await page.reload();
  await expect(page.locator('.login-card')).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('data-admin-scale', '0.85');
  await expect(page.locator('.scale-select input')).toHaveValue('85%');
  await page.evaluate(() => localStorage.setItem('opc.admin.scale', 'invalid-scale'));
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-admin-scale', '0.8');
  await expect(page.locator('.scale-select input')).toHaveValue('80%');
});

for (const viewport of viewports) {
  test(`列表内部滚动后日期弹层保持对齐 ${viewport.width}×${viewport.height}`, async ({ page }, testInfo) => {
    await page.setViewportSize(viewport);
    const backend = await installProtocol(page);
    await installLongAudit(page);
    await loginProtocol(page, '/audit');
    await expect(page.locator('.t-date-picker').first()).toBeVisible();
    // The audit body scrolls independently; the fixed filters remain in the
    // viewport and their teleported calendar still uses screen coordinates.
    const trigger = page.locator('.t-date-picker').first();
    await scrollList(page, 300);
    const initial = (await trigger.boundingBox())!;
    expect(initial.y).toBeGreaterThan(0);
    expect(initial.y + initial.height).toBeLessThanOrEqual(viewport.height);
    await trigger.click();
    const popup = page.locator('.t-popup:visible');
    await expect(popup).toHaveCount(1);
    async function checkPlacement() {
      await expect.poll(async () => {
        const a = await trigger.boundingBox(), b = await popup.boundingBox();
        return a && b ? Math.abs(a.x - b.x) : Infinity;
      }).toBeLessThanOrEqual(1);
      const a = (await trigger.boundingBox())!, b = (await popup.boundingBox())!;
      const gap = Math.min(Math.abs(b.y - a.y - a.height), Math.abs(a.y - b.y - b.height));
      expect(gap).toBeGreaterThanOrEqual(-1);
      expect(gap).toBeLessThanOrEqual(20);
      expect(b.y).toBeGreaterThanOrEqual(0);
      expect(b.x + b.width).toBeLessThanOrEqual(viewport.width + 1);
      expect(Math.abs(a.y - initial.y)).toBeLessThanOrEqual(1);
      return { trigger: a, popup: b, gap, scrollY: await page.evaluate(() => window.scrollY), tableScroll: await page.locator('.scroll-table .t-table__content').first().evaluate(element => element.scrollTop) };
    }
    const opened = await checkPlacement();
    await scrollList(page, 500);
    const scrolled = await checkPlacement();
    await testInfo.attach('scrolled-datepicker-geometry', { body: JSON.stringify({ opened, scrolled }, null, 2), contentType: 'application/json' });
    await page.screenshot({ path: testInfo.outputPath('scrolled-datepicker.png'), animations: 'disabled' });
    await popup.locator('.t-date-picker__cell:not(.t-date-picker__cell--additional):not(.t-date-picker__cell--disabled)').first().click();
    await expect(trigger.locator('input')).toHaveValue(/^\d{4}-\d{2}-\d{2}$/);
    await expect(popup).toHaveCount(0);
    await noDocumentOverflow(page);
    expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
    expect(backend.unknown).toEqual([]);
  });
}

test('折叠导航提示在缩放与列表滚动后仍贴合图标且可跳转', async ({ page }) => {
  await page.setViewportSize({ width: 1920, height: 1080 });
  const backend = await installProtocol(page);
  await installLongAudit(page);
  await loginProtocol(page, '/audit');
  await expect(page.locator('html')).toHaveAttribute('data-admin-scale', '0.8');
  const navigation = page.locator('.side-menu');
  expect(await navigation.innerHTML()).not.toContain('[object Object]');
  await expect(navigation.locator('[popperoptions]')).toHaveCount(0);
  await page.getByRole('button', { name: '收起 / 展开导航', exact: true }).click();
  await expect.poll(async () => (await page.locator('.app-sidebar').boundingBox())!.width).toBeCloseTo(51.2, 0);
  // The fixed sidebar stays in place while only the list content scrolls.
  const item = navigation.locator('.t-menu__item').filter({ hasText: '内部成员与权限' });
  await item.hover();
  const popup = page.locator('.t-popup:visible').filter({ hasText: '内部成员与权限' });
  await expect(popup).toHaveCount(1);
  for (const scrollTop of [0, 1000]) {
    await scrollList(page, scrollTop);
    await expect.poll(async () => {
      const trigger = await item.boundingBox(), tip = await popup.boundingBox();
      return trigger && tip ? Math.abs(trigger.y + trigger.height / 2 - tip.y - tip.height / 2) : Infinity;
    }).toBeLessThanOrEqual(1);
    const trigger = (await item.boundingBox())!, tip = (await popup.boundingBox())!;
    expect(tip.x - trigger.x - trigger.width).toBeGreaterThanOrEqual(-1);
    expect(tip.x - trigger.x - trigger.width).toBeLessThanOrEqual(20);
  }
  await item.click();
  await expect(page).toHaveURL(/#\/members$/);
  await expect(page.locator('.page-content h1')).toHaveText('内部成员与权限');
  await page.getByRole('button', { name: '收起 / 展开导航', exact: true }).click();
  expect(await navigation.innerHTML()).not.toContain('[object Object]');
  await expect(navigation.locator('[popperoptions]')).toHaveCount(0);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
  expect(backend.unknown).toEqual([]);
});

test('滚动后的日期面板月份与年份下拉保持对齐并可选择', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1536, height: 864 });
  await page.addInitScript(() => {
    localStorage.setItem('opc.admin.scale', '80');
    localStorage.setItem('opc.admin.locale', 'zh-CN');
  });
  const backend = await installProtocol(page), errors: string[] = [];
  await installLongAudit(page);
  page.on('pageerror', error => errors.push(error.message));
  await loginProtocol(page, '/audit');
  const date = page.locator('.t-date-picker').first();
  await expect(date).toBeVisible();
  // Keep the previous ancestor-scroll regression: render the real calendar
  // inside a test-only module scroller, while the document remains fixed.
  // Audit normally pins its filters; other module panels may scroll controls.
  await date.evaluate(element => {
    const body = element.closest('.t-card__body')!;
    const wrapper = document.createElement('div');
    wrapper.className = 'module-scroll scale-calendar-fixture';
    wrapper.style.cssText = 'flex:1;min-height:0;overflow:auto;display:block';
    const space = document.createElement('div'); space.style.height = '1000px';
    wrapper.append(space);
    for (const child of Array.from(body.childNodes)) wrapper.append(child);
    const bottom = document.createElement('div'); bottom.style.height = '1000px'; wrapper.append(bottom);
    body.append(wrapper); wrapper.scrollTop = 900;
  });
  const moduleScroller = page.locator('.scale-calendar-fixture');
  await expect.poll(() => moduleScroller.evaluate(element => element.scrollTop)).toBeGreaterThan(150);
  expect(await page.evaluate(() => window.scrollY)).toBe(0);
  await date.click();
  const panel = page.locator('.t-date-picker__panel-container:visible');
  await expect(panel).toHaveCount(1);
  async function checkMainPanel() {
    await expect.poll(async () => {
      const trigger = await date.boundingBox(), popup = await panel.boundingBox();
      // Refocusing the date input may scroll it toward the viewport edge;
      // either top or bottom placement is valid if the panel stays attached.
      return trigger && popup ? Math.max(Math.abs(popup.x - trigger.x), Math.min(
        Math.abs(popup.y - trigger.y - trigger.height),
        Math.abs(trigger.y - popup.y - popup.height),
      )) : Infinity;
    }).toBeLessThanOrEqual(1);
  }
  await checkMainPanel();
  const geometry: Record<string, unknown> = {};
  const year = page.locator('.t-date-picker__header-controller-year');
  const nextYear = String(Number(await year.locator('input').inputValue()) + 1);
  for (const kind of ['month', 'year'] as const) {
    const trigger = page.locator(`.t-date-picker__header-controller-${kind}`);
    await trigger.click();
    const popup = page.locator(`.t-date-picker__header-controller-${kind}-popup:visible`);
    await expect(popup).toHaveCount(1);
    // These checks fail on the old behavior: the nested popup was 82px below
    // its trigger after scrolling, even though options could still be clicked.
    await expect.poll(async () => {
      const a = await trigger.boundingBox(), b = await popup.boundingBox();
      return a && b ? Math.max(Math.abs(b.x - a.x), Math.abs(b.y - a.y - a.height)) : Infinity;
    }).toBeLessThanOrEqual(1);
    const bounds = (await popup.boundingBox())!;
    expect(bounds.x).toBeGreaterThanOrEqual(0);
    expect(bounds.y + bounds.height).toBeLessThanOrEqual(865);
    geometry[kind] = { trigger: await trigger.boundingBox(), popup: bounds, scrollY: await page.evaluate(() => window.scrollY) };
    await page.screenshot({ path: testInfo.outputPath(`nested-calendar-${kind}.png`), animations: 'disabled' });
    if (kind === 'month') {
      await popup.locator('.t-select-option').filter({ hasText: /^1\s*月$/ }).click();
      await expect(trigger.locator('input')).toHaveValue(/^1\s*月$/);
    } else {
      await popup.locator('.t-select-option').filter({ hasText: new RegExp(`^${nextYear}$`) }).click();
      await expect(trigger.locator('input')).toHaveValue(nextYear);
    }
    await expect(popup).toHaveCount(0);
    await checkMainPanel();
  }
  await testInfo.attach('nested-calendar-geometry', { body: JSON.stringify(geometry, null, 2), contentType: 'application/json' });
  await panel.locator('.t-date-picker__cell:not(.t-date-picker__cell--additional):not(.t-date-picker__cell--disabled)').first().click();
  await expect(date.locator('input')).toHaveValue(`${nextYear}-01-01`);
  await expect(panel).toHaveCount(0);
  expect(errors).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
  expect(backend.unknown).toEqual([]);
});
