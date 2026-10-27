import { expect, test } from '@playwright/test';
import { installProtocol, loginProtocol, navigate, requestId, engagementId, deliveryId } from './protocol-fixture';

test('未登录保护所有后台入口，管理登录凭据不持久化', async ({ page }) => {
  const backend = await installProtocol(page);
  await page.goto('/#/reviews');
  await expect(page.locator('.login-card')).toBeVisible();
  expect(backend.calls.some(call => call.path.startsWith('/api/v1/admin/requests'))).toBe(false);
  await loginProtocol(page, '/reviews');
  await expect(page.getByText('REQ-API-001', { exact: true }).first()).toBeVisible();
  const storage = await page.evaluate(() => JSON.stringify({ local: { ...localStorage }, session: { ...sessionStorage } }));
  expect(storage).not.toContain('protocol-token-memory-only');
  expect(storage).not.toContain('protocol-only-password');
  expect(storage).not.toContain('admin@example.invalid');
  await page.reload();
  await expect(page.locator('.login-card')).toBeVisible();
  await expect(page.getByText('REQ-API-001', { exact: true })).toHaveCount(0);
  expect(backend.unknown).toEqual([]);
});

test('非管理账号明确拒绝登录，不展示样例后台', async ({ page }) => {
  const backend = await installProtocol(page); backend.rejectLogin = true;
  await page.goto('/#/dashboard');
  await page.locator('input[name="email"]').fill('customer@example.invalid');
  await page.locator('input[name="password"]').fill('protocol-only-password');
  await page.locator('.login-card button[type="submit"]').click();
  await expect(page.locator('.login-card .t-alert')).toBeVisible();
  await expect(page.locator('.side-menu')).toHaveCount(0);
  expect(backend.calls.some(call => call.path === '/api/v1/admin/dashboard')).toBe(false);
});

test('仅质检角色登录后进入交付页，不请求无权限的需求列表', async ({ page }) => {
  const backend = await installProtocol(page);
  backend.account.roles = ['quality_reviewer'];
  await loginProtocol(page);
  await expect(page).toHaveURL(/#\/delivery$/);
  await expect(page.getByText('PRJ-API-001 / v1', { exact: true })).toBeVisible();
  expect(backend.calls.some(call => call.path.startsWith('/api/v1/admin/requests'))).toBe(false);
  expect(backend.unknown).toEqual([]);
});

test('服务端不可用显示错误且不回退旧 Mock 记录', async ({ page }) => {
  const backend = await installProtocol(page); backend.requestsStatus = 503;
  await loginProtocol(page, '/reviews');
  await expect(page.locator('.page-content .t-alert--error').filter({ hasText: 'SERVICE_UNAVAILABLE' })).toBeVisible();
  await expect(page.locator('tbody')).not.toContainText('REQ-1042');
  await expect(page.locator('tbody')).not.toContainText('REQ-API-001');
  expect(backend.unknown).toEqual([]);
});

test('服务端 401 退出并清理已经展示的私有需求', async ({ page }) => {
  const backend = await installProtocol(page);
  await loginProtocol(page, '/reviews');
  await expect(page.getByText('REQ-API-001', { exact: true }).first()).toBeVisible();
  backend.expire = true;
  await page.getByRole('button', { name: '查询', exact: true }).click();
  await expect(page.locator('.login-card')).toBeVisible();
  await expect(page.getByText('REQ-API-001', { exact: true })).toHaveCount(0);
});

test('筛选条件发送真实查询参数，并使用服务端筛选结果', async ({ page }) => {
  const backend = await installProtocol(page);
  await loginProtocol(page, '/reviews');
  const keyword = page.locator('.keyword-field input');
  await keyword.fill('不存在的条件');
  await page.getByRole('button', { name: '查询', exact: true }).click();
  await expect(page.getByText('没有符合条件的记录', { exact: true })).toBeVisible();
  expect(backend.calls.some(call => call.path.includes(`q=${encodeURIComponent('不存在的条件')}`))).toBe(true);
  await page.getByRole('button', { name: '重置', exact: true }).click();
  await expect(page.getByText('REQ-API-001', { exact: true }).first()).toBeVisible();
});

for (const locale of ['zh-CN', 'ja-JP']) for (const theme of ['light', 'dark']) {
  test(`${locale} ${theme} 实际协议十页渲染与主题`, async ({ page }, testInfo) => {
    const backend = await installProtocol(page);
    const errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (['warning', 'error'].includes(message.type()) && /intlify|Vue warn|tdesign|icon/i.test(message.text())) errors.push(message.text()); });
    await page.addInitScript(({ locale, theme }) => { localStorage.setItem('opc.admin.locale', locale); localStorage.setItem('opc.admin.theme', theme); }, { locale, theme });
    await loginProtocol(page);
    for (const route of ['/dashboard', '/reviews', `/reviews/${requestId}`, `/technical?id=${requestId}`, `/publishing?id=${requestId}`, '/projects', '/delivery', '/members', '/tickets', '/audit']) {
      await navigate(page, route);
      await expect(page.locator('h1')).toBeVisible();
      await expect(page.locator('.page-content .t-card').first()).toBeVisible();
      await expect(page.locator('html')).toHaveAttribute('lang', locale);
      if (theme === 'dark') await expect(page.locator('html')).toHaveAttribute('theme-mode', 'dark');
      else await expect(page.locator('html')).not.toHaveAttribute('theme-mode', 'dark');
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
      await page.screenshot({ path: testInfo.outputPath(`${route.split('?')[0].split('/')[1]}${route.startsWith('/reviews/') ? '-detail' : ''}.png`), animations: 'disabled', fullPage: true });
    }
    expect(errors).toEqual([]); expect(backend.unknown).toEqual([]);
  });
}

test('发布携带服务端行版本，409 保持未发布而非模拟成功', async ({ page }) => {
  const backend = await installProtocol(page); backend.conflict = true;
  await loginProtocol(page, `/publishing?id=${requestId}`);
  await page.getByRole('button', { name: '发布 v1', exact: true }).click();
  const dialog = page.locator('.t-dialog:visible');
  await dialog.locator('textarea').fill('已确认当前同版本双审核。');
  await dialog.getByRole('button', { name: '确认', exact: true }).click();
  await expect(dialog).toContainText('VERSION_CONFLICT');
  await expect(dialog).toContainText('test-request-id');
  const submission = backend.calls.find(call => call.method === 'POST' && call.path.endsWith('/publish'));
  expect(submission?.body).toEqual({ expected_version: 7, scope_version: 1, reason: '已确认当前同版本双审核。' });
  expect(submission?.authorization).toBe('Bearer protocol-token-memory-only');
  await expect(page.getByRole('button', { name: '下架当前版本', exact: true })).toHaveCount(0);
});

test('发布成功来自真实响应，后续下架使用更新后的版本', async ({ page }) => {
  const backend = await installProtocol(page);
  await loginProtocol(page, `/publishing?id=${requestId}`);
  await page.getByRole('button', { name: '发布 v1', exact: true }).click();
  await page.locator('.t-dialog:visible textarea').fill('确认当前同版本双审核。');
  await page.locator('.t-dialog:visible').getByRole('button', { name: '确认', exact: true }).click();
  await page.getByRole('button', { name: '下架当前版本', exact: true }).click();
  await page.locator('.t-dialog:visible textarea').fill('确认变更前先下架。');
  await page.locator('.t-dialog:visible').getByRole('button', { name: '确认', exact: true }).click();
  await expect(page.getByRole('button', { name: '发布 v1', exact: true })).toBeVisible();
  const unpublish = backend.calls.find(call => call.method === 'POST' && call.path.endsWith('/publication/withdraw'));
  expect(unpublish?.body).toEqual({ expected_version: 8, reason: '确认变更前先下架。' });
  expect(backend.request.publications[0]?.withdrawn_at).toBeTruthy();
});

test('交付审核必须核对清单，409 保留未发布且不伪造成功', async ({ page }) => {
  const backend = await installProtocol(page); backend.conflict = true;
  await loginProtocol(page, `/delivery?id=${engagementId}`);
  const approve = page.getByRole('button', { name: '通过内部检查', exact: true });
  await approve.click();
  expect(backend.calls.some(call => call.method === 'POST' && call.path.endsWith('/review'))).toBe(false);
  await expect(page.locator('.t-dialog:visible')).toHaveCount(0);
  for (const checkbox of await page.locator('.page-content .t-checkbox').all()) await checkbox.click();
  await page.locator('.page-content textarea').fill('已核对固定版本、权限、资料和验收条件。');
  await approve.click();
  await page.locator('.t-dialog:visible').getByRole('button', { name: '确认', exact: true }).click();
  await expect(page.locator('.page-content .t-alert--error')).toContainText('记录已变化，请刷新后重新核对');
  await expect(page.locator('.page-content .t-alert--error')).toContainText('test-request-id');
  const submission = backend.calls.find(call => call.method === 'POST' && call.path.endsWith(`/${deliveryId}/review`));
  expect(submission?.body).toEqual({ expected_version: 4, decision: 'approved', evidence: '已核对固定版本、权限、资料和验收条件。' });
  await expect(page.getByRole('button', { name: '发布给客户', exact: true })).toHaveCount(0);
  expect(backend.detail.reviews).toHaveLength(0);
  expect(backend.unknown).toEqual([]);
});

test('语言、主题仅保存偏好，1024 宽与系统暗色继续适用', async ({ page }) => {
  await page.setViewportSize({ width: 1024, height: 1000 });
  await installProtocol(page);
  await loginProtocol(page);
  await page.locator('.locale-select').click();
  await page.getByRole('listitem', { name: '日本語', exact: true }).click();
  await page.locator('.theme-select').click();
  await page.getByRole('listitem', { name: 'ダーク', exact: true }).click();
  await expect(page.locator('html')).toHaveAttribute('lang', 'ja-JP');
  await expect(page.locator('html')).toHaveAttribute('theme-mode', 'dark');
  for (const route of ['/reviews', `/reviews/${requestId}`, `/projects?id=${engagementId}`, `/delivery?id=${engagementId}`, '/members', '/audit']) {
    await navigate(page, route);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
  }
  await page.reload();
  await expect(page.locator('.login-card')).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('lang', 'ja-JP');
  await expect(page.locator('html')).toHaveAttribute('theme-mode', 'dark');
  await page.locator('.theme-select').click();
  await page.getByRole('listitem', { name: 'システム設定', exact: true }).click();
  await page.emulateMedia({ colorScheme: 'light' });
  await expect(page.locator('html')).not.toHaveAttribute('theme-mode', 'dark');
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect(page.locator('html')).toHaveAttribute('theme-mode', 'dark');
  expect(await page.evaluate(() => localStorage.getItem('opc.admin.theme'))).toBe('system');
});
