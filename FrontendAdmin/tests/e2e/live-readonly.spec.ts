import { readFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';
import { navigate } from './protocol-fixture';

// Do not record credentials or bearer tokens in Playwright artifacts.
test.use({ trace: 'off', screenshot: 'off', video: 'off' });
test.describe('真实本机 API 只读验证', () => {
  test.skip(process.env.OPC_LIVE_SMOKE !== '1', '仅显式开启时访问本机持久联调库');
  test('真实管理员登录并读取十页，业务记录不变，刷新必须重新登录', async ({ page, request }) => {
    test.setTimeout(60_000);
    const credentials = JSON.parse(await readFile(new URL('../../../BackendService/.local/demo-credentials.json', import.meta.url), 'utf8')).accounts.admin;
    const errors: string[] = [];
    const businessWrites: string[] = [];
    const visited = new Set<string>();
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', value => {
      const url = new URL(value.url());
      if (url.port === '8001' && !['GET', 'OPTIONS'].includes(value.method()) && !url.pathname.startsWith('/api/v1/admin/auth/')) businessWrites.push(`${value.method()} ${url.pathname}`);
    });
    page.on('response', response => {
      const url = new URL(response.url());
      if (url.port === '8001' && response.status() >= 400) errors.push(`${response.status()} ${url.pathname}`);
      if (url.port === '8001' && response.ok()) visited.add(url.pathname);
    });
    await page.goto('/#/reviews');
    await expect(page.locator('.login-card')).toBeVisible();
    await page.locator('input[name="email"]').fill(credentials.email);
    await page.locator('input[name="password"]').fill(credentials.password);
    const loginResponse = page.waitForResponse(response => response.url().endsWith('/api/v1/admin/auth/login') && response.request().method() === 'POST');
    await page.locator('.login-card button[type="submit"]').click();
    const auth = await (await loginResponse).json();
    if (!auth.access_token || auth.audience !== 'admin') throw new Error('真实管理登录失败');
    const headers = { Authorization: `Bearer ${auth.access_token}` };
    try {
      await expect(page.locator('.login-card')).toHaveCount(0);
      const beforeResponse = await request.get('http://127.0.0.1:8001/api/v1/admin/requests?limit=100&offset=0', { headers });
      expect(beforeResponse.ok()).toBe(true);
      const before = await beforeResponse.json();
      if (!before.items.length) throw new Error('联调库缺少用户授权的演示需求');
      await expect(page.getByText(before.items[0].public_code, { exact: true }).first()).toBeVisible();
      const targetRequest = before.items.find((item: { current_scope_version: number }) => item.current_scope_version > 0) || before.items[0];
      const projectsResponse = await request.get('http://127.0.0.1:8001/api/v1/admin/engagements?limit=100&offset=0', { headers });
      expect(projectsResponse.ok()).toBe(true);
      const projects = (await projectsResponse.json()).items;
      const project = projects.find((item: { status: string }) => item.status === 'internal_review') || projects[0];
      if (!project) throw new Error('联调库缺少用户授权的演示合作');
      for (const route of ['/dashboard', '/reviews', `/reviews/${targetRequest.id}`, `/technical?id=${targetRequest.id}`, `/publishing?id=${targetRequest.id}`, `/projects?id=${project.id}`, `/delivery?id=${project.id}`, '/members', '/tickets', '/audit']) {
        await navigate(page, route);
        await expect(page.locator('.page-content .t-card').first()).toBeVisible();
        await expect(page.locator('.page-content .t-loading')).toHaveCount(0);
      }
      const after = await (await request.get('http://127.0.0.1:8001/api/v1/admin/requests?limit=100&offset=0', { headers })).json();
      const stable = (data: { items: { id: string; row_version: number; intake_status: string }[] }) => data.items.map(item => ({ id: item.id, row_version: item.row_version, intake_status: item.intake_status })).sort((a, b) => a.id.localeCompare(b.id));
      expect(stable(after)).toEqual(stable(before));
      expect(errors).toEqual([]);
      expect(visited.has('/api/v1/admin/requests')).toBe(true);
      expect(visited.has('/api/v1/admin/engagements')).toBe(true);
      expect(visited.has(`/api/v1/admin/engagements/${project.id}`)).toBe(true);
      expect(visited.has('/api/v1/admin/accounts')).toBe(true);
      expect(visited.has('/api/v1/admin/audit-events')).toBe(true);
      const storage = await page.evaluate(() => JSON.stringify({ local: { ...localStorage }, session: { ...sessionStorage } }));
      expect(storage.includes(auth.access_token)).toBe(false);
      expect(storage.includes(credentials.password)).toBe(false);
      expect(businessWrites).toEqual([]);
      await page.reload();
      await expect(page.locator('.login-card')).toBeVisible();
    } finally {
      const revoked = await request.post('http://127.0.0.1:8001/api/v1/admin/auth/logout', { headers });
      expect(revoked.ok()).toBe(true);
    }
  });
});
