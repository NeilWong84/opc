import { expect, test, type Page } from '@playwright/test';
import { account, deliveryId, engagementId, installProtocol, loginProtocol, navigate } from './protocol-fixture';

const evidenceHint = '填写实际核对结果；上传资料或勾选清单不等于测试通过。此记录提交后不可覆盖。';
const deliveryBoundary = '内部检查通过后另行发布给客户；客户验收是独立步骤。';
const reviewLocked = '当前交付已有不可覆盖的质检记录；修改需提交新交付版本。';
const requestBoundary = '未通过或未发布的需求仅在获授权的审核区可见，不进入大厅列表、搜索或计数。';

async function fixedDocument(page: Page) {
  await expect.poll(() => page.evaluate(() => Math.max(
    document.documentElement.scrollHeight - innerHeight,
    document.documentElement.scrollWidth - innerWidth,
    Math.abs(scrollY),
  ))).toBeLessThanOrEqual(1);
}

async function openCenter(page: Page) {
  await page.locator('.notification-trigger').click();
  const center = page.locator('.notification-center');
  await expect(center).toBeVisible();
  return center;
}

async function closeCenter(page: Page) {
  await page.locator('.t-drawer__close-btn:visible').click();
  await expect(page.locator('.notification-center:visible')).toHaveCount(0);
}

test('交付说明进入通知中心，关闭说明不改变已锁定的质检记录', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1920, height: 1080 });
  const backend = await installProtocol(page);
  backend.detail.reviews.push({ id: '80000000-0000-4000-8000-000000000001', delivery_id: deliveryId,
    reviewer_id: account.id, decision: 'approved', evidence: '已保存的不可覆盖检查证据', reviewed_at: '2026-10-25T01:00:00Z' });
  backend.detail.deliveries[0]!.published = true;
  backend.detail.engagement.status = 'awaiting_acceptance';
  await loginProtocol(page, `/delivery?id=${engagementId}`);
  await expect(page.getByText('已保存的不可覆盖检查证据', { exact: true })).toBeVisible();
  await expect(page.locator('#page-notices .t-alert--info')).toHaveCount(0);
  await expect(page.locator('.page-module .page-notice.t-alert--info:visible')).toHaveCount(0);
  await expect(page.locator('.page-module .t-checkbox')).toHaveCount(0);
  await fixedDocument(page);

  const center = await openCenter(page);
  await expect(center.locator('.context-notification')).toHaveCount(3);
  for (const text of [reviewLocked, evidenceHint, deliveryBoundary]) await expect(center.getByText(text, { exact: true })).toBeVisible();
  await center.locator('.context-notification').filter({ hasText: reviewLocked }).getByRole('button', { name: '关闭', exact: true }).click();
  await expect(center.locator('.context-notification')).toHaveCount(2);
  await page.screenshot({ path: testInfo.outputPath('delivery-context-notifications.png'), animations: 'disabled' });
  await closeCenter(page);
  await expect(page.getByText('已保存的不可覆盖检查证据', { exact: true })).toBeVisible();
  await expect(page.locator('.page-module .t-checkbox')).toHaveCount(0);
  await expect(page.getByRole('button', { name: '通过内部检查', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: '撤回对客交付', exact: true })).toBeVisible();
  await fixedDocument(page);
  await openCenter(page);
  await expect(center.locator('.context-notification')).toHaveCount(2);
  expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});

test('页面说明随路由清理并随语言切换，关闭只作用于当前展示', async ({ page }) => {
  const backend = await installProtocol(page);
  await loginProtocol(page, '/reviews');
  let center = await openCenter(page);
  await expect(center.locator('.context-notification')).toHaveCount(1);
  await expect(center.getByText(requestBoundary, { exact: true })).toBeVisible();
  await center.locator('.context-notification').getByRole('button', { name: '关闭', exact: true }).click();
  await expect(center.locator('.context-notification')).toHaveCount(0);
  await closeCenter(page);

  await navigate(page, `/delivery?id=${engagementId}`);
  center = await openCenter(page);
  await expect(center.locator('.context-notification')).toHaveCount(2);
  await expect(center.getByText(requestBoundary, { exact: true })).toHaveCount(0);
  // Browser navigation can change the route while the drawer is open; the old page's notes must disappear with it.
  await navigate(page, '/reviews');
  await expect(page.locator('.notification-center:visible')).toHaveCount(0);
  await page.locator('.locale-select').click();
  await page.getByRole('listitem', { name: '日本語', exact: true }).click();
  center = await openCenter(page);
  await expect(page.locator('.notification-trigger')).toHaveAttribute('aria-label', '通知センター');
  await expect(center.locator('.t-tabs__nav-item').filter({ hasText: /^ページの説明/ })).toBeVisible();
  await expect(center.locator('.context-notification')).toHaveCount(1);
  await expect(center.getByText('未承認・未公開の依頼は権限のある審査エリアにのみ表示され、案件一覧・検索・件数には含まれません。', { exact: true })).toBeVisible();
  await expect(center.getByText(requestBoundary, { exact: true })).toHaveCount(0);
  await fixedDocument(page);
  expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});

test('业务通知继续读取服务端并标记已读，页面说明不发送写请求', async ({ page }) => {
  const backend = await installProtocol(page);
  const notificationId = '90000000-0000-4000-8000-000000000001';
  const reads: { method: string; path: string }[] = [];
  await page.route('http://127.0.0.1:8001/api/v1/admin/notifications**', async route => {
    const request = route.request(), url = new URL(request.url());
    if (request.method() === 'OPTIONS') return route.fallback();
    reads.push({ method: request.method(), path: url.pathname + url.search });
    const headers = { 'access-control-allow-origin': '*' };
    if (request.method() === 'GET' && url.pathname === '/api/v1/admin/notifications') return route.fulfill({
      headers, contentType: 'application/json', body: JSON.stringify({ items: [{ id: notificationId, template_key: 'message_received',
        parameters: { body: '服务端保存的项目通知原文' }, created_at: '2026-10-25T01:00:00Z', read_at: null }] }),
    });
    if (request.method() === 'POST' && url.pathname === `/api/v1/admin/notifications/${notificationId}/read`) return route.fulfill({
      headers, contentType: 'application/json', body: JSON.stringify({ read_at: '2026-10-25T02:00:00Z' }),
    });
    return route.fallback();
  });
  await loginProtocol(page, '/reviews');
  const center = await openCenter(page);
  await expect(center.getByText(requestBoundary, { exact: true })).toBeVisible();
  await center.locator('.t-tabs__nav-item').filter({ hasText: /^业务通知$/ }).click();
  await expect(center.getByText('服务端保存的项目通知原文', { exact: true })).toBeVisible();
  await center.getByRole('button', { name: '标为已读', exact: true }).click();
  await expect(center.getByText('已读', { exact: true })).toBeVisible();
  await expect(center.getByRole('button', { name: '标为已读', exact: true })).toHaveCount(0);
  await center.locator('.t-tabs__nav-item').filter({ hasText: /^页面说明/ }).click();
  await center.locator('.context-notification').getByRole('button', { name: '关闭', exact: true }).click();
  expect(reads).toEqual([{ method: 'GET', path: '/api/v1/admin/notifications?limit=30' },
    { method: 'POST', path: `/api/v1/admin/notifications/${notificationId}/read` }]);
  await fixedDocument(page);
  expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});

test('输入错误留在页头，关闭说明仍需完整清单和证据，提交确认提示留在弹窗', async ({ page }) => {
  const backend = await installProtocol(page);
  await loginProtocol(page, `/delivery?id=${engagementId}`);
  const approve = page.getByRole('button', { name: '通过内部检查', exact: true });
  await expect(approve).toBeVisible();
  await approve.click();
  const error = page.locator('#page-notices .t-alert--error').filter({ hasText: '必须先核对全部四项检查清单' });
  await expect(error).toBeVisible();
  const center = await openCenter(page);
  await expect(center.locator('.context-notification')).toHaveCount(2);
  while (await center.locator('.context-notification').count()) await center.locator('.context-notification').first().getByRole('button', { name: '关闭', exact: true }).click();
  await closeCenter(page);
  await error.getByRole('button', { name: '关闭', exact: true }).click();
  await approve.click();
  await expect(error).toBeVisible();
  await expect(page.locator('.page-module .t-checkbox')).toHaveCount(4);
  for (const checkbox of await page.locator('.page-module .t-checkbox').all()) await checkbox.click();
  await page.locator('.page-module textarea').fill('只用于检查确认界面，取消操作，不提交质检记录。');
  await approve.click();
  const dialog = page.locator('.t-dialog:visible');
  await expect(dialog).toBeVisible();
  await expect(dialog.locator('.t-alert--info').filter({ hasText: '该操作会写入数据库并保留审计。请核对当前对象、版本及操作内容。' })).toBeVisible();
  await expect(page.locator('#page-notices .t-alert--info')).toHaveCount(0);
  await dialog.getByRole('button', { name: '取消', exact: true }).click();
  await fixedDocument(page);
  expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});

test('通知接口失败只影响业务通知，页面说明和页面错误各自保留', async ({ page }) => {
  const backend = await installProtocol(page); backend.requestsStatus = 503;
  await page.route('http://127.0.0.1:8001/api/v1/admin/notifications**', async route => {
    if (route.request().method() !== 'GET') return route.fallback();
    return route.fulfill({ status: 503, headers: { 'access-control-allow-origin': '*' }, contentType: 'application/json',
      body: JSON.stringify({ error: { code: 'NOTIFICATIONS_UNAVAILABLE', message: '业务通知暂时不可读取' }, request_id: 'notification-protocol-id' }) });
  });
  await loginProtocol(page, '/reviews');
  await expect(page.locator('#page-notices .t-alert--error').filter({ hasText: 'SERVICE_UNAVAILABLE' })).toBeVisible();
  const center = await openCenter(page);
  await expect(center.getByText(requestBoundary, { exact: true })).toBeVisible();
  await expect(center.locator('.t-alert--error:visible')).toHaveCount(0);
  await center.locator('.t-tabs__nav-item').filter({ hasText: /^业务通知$/ }).click();
  await expect(center.locator('.t-alert--error').filter({ hasText: '业务通知暂时不可读取' })).toBeVisible();
  await center.locator('.t-tabs__nav-item').filter({ hasText: /^页面说明/ }).click();
  await expect(center.getByText(requestBoundary, { exact: true })).toBeVisible();
  await closeCenter(page);
  await expect(page.locator('#page-notices .t-alert--error').filter({ hasText: 'SERVICE_UNAVAILABLE' })).toHaveCount(1);
  await expect(page.locator('#page-notices .t-alert--error').filter({ hasText: '业务通知暂时不可读取' })).toHaveCount(0);
  await fixedDocument(page);
  expect(backend.unknown).toEqual([]);
  expect(backend.calls.filter(call => call.method !== 'GET' && !call.path.startsWith('/api/v1/admin/auth/'))).toEqual([]);
});
