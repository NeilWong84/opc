import { expect, test, type Page, type Locator } from '@playwright/test';
import { account, installProtocol, loginProtocol, navigate, requestFixture, requestId } from './protocol-fixture';

async function longLists(page: Page) {
  const backend = await installProtocol(page);
  const requests = Array.from({ length: 60 }, (_, index) => ({ ...requestFixture(),
    id: index === 0 ? requestId : `30000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
    public_code: `REQ-SCROLL-${String(index + 1).padStart(3, '0')}`,
    scope: { ...requestFixture().scope, title: `一覧の高さを確認する API レコード ${index + 1}` },
  }));
  const members = Array.from({ length: 20 }, (_, index) => ({ ...account,
    id: `10000000-0000-4000-8000-${String(index + 10).padStart(12, '0')}`,
    display_name: `成员 ${index + 1}`, email: `member${index + 1}@example.invalid`,
  }));
  const audit = Array.from({ length: 50 }, (_, index) => ({ id: 1000 - index,
    occurred_at: '2026-10-25T01:00:00Z', application_actor_id: account.id, correlation_id: `scroll-layout-${index}`,
    table_name: 'requests', operation: 'UPDATE', entity_key: { id: requestId, record: index },
    changed_fields: ['intake_status'], details: {},
  }));
  await page.route('http://127.0.0.1:8001/api/v1/admin/**', async route => {
    const request = route.request(), url = new URL(request.url());
    if (request.method() !== 'GET') return route.fallback();
    let body: unknown;
    if (url.pathname === '/api/v1/admin/requests') {
      if (backend.requestsStatus !== 200) {
        backend.calls.push({ method: 'GET', path: url.pathname + url.search, body: undefined, authorization: request.headers().authorization });
        return route.fulfill({ status: backend.requestsStatus, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify({ error: { code: 'SERVICE_UNAVAILABLE', message: '测试服务当前不可用' }, request_id: 'scroll-height-error' }) });
      }
      const limit = Number(url.searchParams.get('limit') || 20), offset = Number(url.searchParams.get('offset') || 0);
      body = { items: requests.slice(offset, offset + limit), total: requests.length, limit, offset };
    } else if (url.pathname.startsWith('/api/v1/admin/requests/')) {
      const id = url.pathname.split('/')[5], record = requests.find(row => row.id === id);
      if (!record || url.pathname.endsWith('/scopes')) return route.fallback();
      body = record;
    } else if (url.pathname === '/api/v1/admin/accounts') body = { items: members, limit: 20, offset: 0 };
    else if (url.pathname === '/api/v1/admin/audit-events') body = { items: audit };
    else return route.fallback();
    backend.calls.push({ method: 'GET', path: url.pathname + url.search, body: undefined, authorization: request.headers().authorization });
    return route.fulfill({ contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) });
  });
  return backend;
}

async function documentIsFixed(page: Page) {
  await expect.poll(() => page.evaluate(() => Math.max(
    document.documentElement.scrollHeight - innerHeight,
    document.documentElement.scrollWidth - innerWidth,
    Math.abs(scrollY),
  ))).toBeLessThanOrEqual(1);
}

async function box(locator: Locator) {
  const bounds = await locator.boundingBox();
  expect(bounds).not.toBeNull();
  return bounds!;
}

async function assertListScrolls(page: Page) {
  const list = page.locator('.scroll-table').first();
  const body = list.locator('.t-table__content');
  await expect(body).toBeVisible();
  await expect.poll(() => body.evaluate(element => element.scrollHeight - element.clientHeight)).toBeGreaterThan(100);
  const toolbar = page.locator('.table-toolbar').first();
  const header = list.locator('thead').first();
  const pager = page.locator('.t-pagination:visible, .pager:visible, .audit-more:visible').last();
  const before = { toolbar: await box(toolbar), header: await box(header), pager: await box(pager) };
  await body.hover();
  await page.mouse.wheel(0, 650);
  await expect.poll(() => body.evaluate(element => element.scrollTop)).toBeGreaterThan(100);
  await documentIsFixed(page);
  for (const [name, locator] of [['toolbar', toolbar], ['header', header], ['pager', pager]] as const) {
    const after = await box(locator);
    expect(Math.abs(after.y - before[name].y), `${name} must stay fixed`).toBeLessThanOrEqual(1);
    expect(after.y).toBeGreaterThanOrEqual(0);
    expect(after.y + after.height).toBeLessThanOrEqual(page.viewportSize()!.height + 1);
  }
  return body;
}

const modes = [
  { width: 1920, height: 1080, scale: 80, locale: 'zh-CN', theme: 'light' },
  { width: 1536, height: 864, scale: 80, locale: 'ja-JP', theme: 'dark' },
  { width: 1920, height: 1080, scale: 100, locale: 'ja-JP', theme: 'light' },
  { width: 1536, height: 864, scale: 75, locale: 'zh-CN', theme: 'dark' },
];

for (const mode of modes) test(`列表独立滚动 ${mode.width}×${mode.height} ${mode.scale}% ${mode.locale} ${mode.theme}`, async ({ page }, testInfo) => {
  await page.setViewportSize({ width: mode.width, height: mode.height });
  await page.addInitScript(({ scale, locale, theme }) => {
    localStorage.setItem('opc.admin.scale', String(scale)); localStorage.setItem('opc.admin.locale', locale); localStorage.setItem('opc.admin.theme', theme);
  }, mode);
  const backend = await longLists(page), errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  await loginProtocol(page, '/reviews');
  for (const route of ['/reviews', '/members', '/audit']) {
    if (route !== '/reviews') await navigate(page, route);
    await expect(page.locator('.scroll-table tbody tr')).toHaveCount(route === '/audit' ? 50 : 20);
    await documentIsFixed(page);
    // General explanations are available from the existing bell without using table height.
    await expect(page.locator('#page-notices .t-alert--info')).toHaveCount(0);
    await page.locator('.notification-trigger').click();
    await expect(page.locator('.notification-center .context-notification').first()).toBeVisible();
    await page.locator('.t-drawer__close-btn:visible').click();
    await expect(page.locator('.t-drawer--open')).toHaveCount(0);
    await expect(page.locator('style[data-id^="td_drawer_"]')).toHaveCount(0);
    await assertListScrolls(page);
    await page.screenshot({ path: testInfo.outputPath(route.slice(1) + '-internal-scroll.png'), animations: 'disabled' });
  }
  expect(errors).toEqual([]); expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});

test('关闭错误后再次失败会重新显示，重试和权限仍由真实响应决定', async ({ page }) => {
  await page.setViewportSize({ width: 1536, height: 864 });
  const backend = await installProtocol(page); backend.requestsStatus = 503;
  await loginProtocol(page, '/reviews');
  const error = page.locator('#page-notices .t-alert--error').filter({ hasText: 'SERVICE_UNAVAILABLE' });
  await expect(error).toBeVisible();
  await error.locator('.t-alert__close').click();
  await expect(error).toHaveCount(0);
  await page.locator('.table-toolbar button[type="submit"]').click();
  await expect(error).toBeVisible();
  backend.requestsStatus = 200;
  await error.locator('.t-link').click();
  await expect(error).toHaveCount(0);
  await expect(page.getByText('REQ-API-001', { exact: true }).first()).toBeVisible();
  await documentIsFixed(page);
  backend.account.roles = ['operator'];
  await page.reload();
  await loginProtocol(page, '/members');
  const warning = page.locator('#page-notices .t-alert--warning');
  await expect(warning).toBeVisible();
  await warning.locator('.t-alert__close').click();
  await expect(warning).toHaveCount(0);
  await expect(page.getByRole('button', { name: '创建内部账号', exact: true })).toHaveCount(0);
  expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});

test('长表单只滚动模块内容，缩小窗口后底部操作仍可到达', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1920, height: 1080 });
  const backend = await installProtocol(page);
  await loginProtocol(page, `/technical?id=${requestId}`);
  const module = page.locator('.module-scroll').first();
  await expect(module).toBeVisible();
  await expect.poll(() => module.evaluate(element => element.scrollHeight - element.clientHeight)).toBeGreaterThan(100);
  const heading = await box(page.locator('.page-heading'));
  const save = page.getByRole('button', { name: '保存并激活新范围版本', exact: true });
  await save.scrollIntoViewIfNeeded();
  await expect(save).toBeInViewport();
  expect(await module.evaluate(element => element.scrollTop)).toBeGreaterThan(100);
  await documentIsFixed(page);
  expect(Math.abs((await box(page.locator('.page-heading'))).y - heading.y)).toBeLessThanOrEqual(1);
  await page.setViewportSize({ width: 1536, height: 600 });
  await save.scrollIntoViewIfNeeded();
  await expect(save).toBeInViewport();
  await documentIsFixed(page);
  await page.screenshot({ path: testInfo.outputPath('technical-module-scroll.png'), animations: 'disabled' });
  expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});

test('列表随视口和提示关闭重新分配高度，不产生外层滚动', async ({ page }) => {
  const backend = await longLists(page);
  await page.setViewportSize({ width: 1920, height: 1080 });
  backend.requestsStatus = 503;
  await loginProtocol(page, '/reviews');
  const error = page.locator('#page-notices .t-alert--error').filter({ hasText: 'SERVICE_UNAVAILABLE' });
  await expect(error).toBeVisible();
  const body = page.locator('.scroll-table .t-table__content').first();
  const withError = await body.evaluate(element => element.clientHeight);
  const noticeBox = await box(error), tableBox = await box(page.locator('.scroll-table').first());
  expect(noticeBox.y + noticeBox.height).toBeLessThanOrEqual(tableBox.y + 1);
  const callsBefore = backend.calls.length;
  await error.getByRole('button', { name: '关闭', exact: true }).click();
  await expect(error).toHaveCount(0);
  await expect.poll(() => body.evaluate(element => element.clientHeight)).toBeGreaterThan(withError);
  expect(backend.calls.length).toBe(callsBefore);
  backend.requestsStatus = 200;
  await page.locator('.table-toolbar button[type="submit"]').click();
  await expect(page.locator('.scroll-table tbody tr')).toHaveCount(20);
  const tall = await body.evaluate(element => element.clientHeight);
  await page.setViewportSize({ width: 1536, height: 650 });
  await expect.poll(() => body.evaluate(element => element.clientHeight)).toBeLessThan(tall);
  await assertListScrolls(page);
  await page.setViewportSize({ width: 1920, height: 1080 });
  await expect.poll(() => body.evaluate(element => element.clientHeight)).toBe(tall);
  await documentIsFixed(page);
  expect(backend.unknown).toEqual([]);
});

test('发布弹窗的提示可用键盘关闭，重复校验仍显示错误且不会写入', async ({ page }) => {
  const backend = await installProtocol(page);
  await loginProtocol(page, `/publishing?id=${requestId}`);
  await page.getByRole('button', { name: '发布 v1', exact: true }).click();
  const dialog = page.locator('.t-dialog:visible');
  const confirm = dialog.getByRole('button', { name: '确认', exact: true });
  const error = dialog.locator('.t-alert--error');
  await confirm.click();
  await expect(error).toBeVisible();
  const close = error.getByRole('button', { name: '关闭', exact: true });
  await close.focus(); await page.keyboard.press('Enter');
  await expect(error).toHaveCount(0);
  await confirm.click();
  await expect(error).toBeVisible();
  await expect(page.locator('#page-notices .t-alert--error')).toHaveCount(0);
  await dialog.getByRole('button', { name: '取消', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await documentIsFixed(page);
  expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});

test('短屏工作台的表格保留可用高度，模块内能到达审计入口', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1024, height: 768 });
  const backend = await longLists(page);
  await loginProtocol(page, '/dashboard');
  await expect(page.locator('.dashboard-table tbody tr')).toHaveCount(10);
  const body = page.locator('.dashboard-body.module-scroll');
  const table = body.locator('.scroll-table .t-table__content');
  await expect.poll(() => body.evaluate(element => element.scrollHeight - element.clientHeight)).toBeGreaterThan(100);
  await table.scrollIntoViewIfNeeded();
  await expect.poll(() => table.evaluate(element => element.clientHeight)).toBeGreaterThan(100);
  await expect(table).toBeInViewport();
  await expect.poll(() => table.evaluate(element => element.scrollHeight - element.clientHeight)).toBeGreaterThan(100);
  await table.evaluate(element => { element.scrollTop = 300; });
  await expect.poll(() => table.evaluate(element => element.scrollTop)).toBeGreaterThan(100);
  await documentIsFixed(page);
  const audit = body.locator('.section-card').filter({ hasText: '操作审计' }).getByRole('button', { name: '查看', exact: true });
  await audit.scrollIntoViewIfNeeded();
  await expect(audit).toBeInViewport();
  expect(await body.evaluate(element => element.scrollTop)).toBeGreaterThan(100);
  await documentIsFixed(page);
  await page.screenshot({ path: testInfo.outputPath('dashboard-short-screen.png'), animations: 'disabled' });
  await audit.click();
  await expect(page).toHaveURL(/#\/audit$/);
  await expect(page.locator('h1')).toHaveText('操作审计');
  await documentIsFixed(page);
  expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});
