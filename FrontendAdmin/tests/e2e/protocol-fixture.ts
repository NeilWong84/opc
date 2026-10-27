import { expect, type Page } from '@playwright/test';

export const requestId = '30000000-0000-4000-8000-000000000001';
export const engagementId = '40000000-0000-4000-8000-000000000001';
export const deliveryId = '70000000-0000-4000-8000-000000000001';
export const account = {
  id: '10000000-0000-4000-8000-000000000001', email: 'admin@example.invalid', display_name: '协议测试管理员', status: 'active',
  ui_locale: 'zh', row_version: 1, created_at: '2026-10-22T01:00:00Z', roles: ['administrator'], internally_authorized: false, opc_certified: false,
};
export const capabilities = {
  service_codes: ['development'], locales: ['ja', 'zh'], currency: 'JPY', business_timezone: 'Asia/Tokyo',
  hall_audience: 'internal', assignment_mode: 'disabled', file_storage: 'local_private', file_inspection: 'manual_evidence',
  office_pdf_conversion: false, email_push_delivery: false, password_recovery: false, email_verification: false,
  ai_provider: false, payments: false, formal_certification: false,
};
const now = '2026-10-22T01:00:00Z';
export function requestFixture() {
  return {
    id: requestId, public_code: 'REQ-API-001', service_code: 'development', customer_id: '20000000-0000-4000-8000-000000000001',
    intake_status: 'in_review', current_request_version: 1, current_scope_version: 1, row_version: 7, created_at: now, updated_at: now,
    original: { original_description: '実際の API 応答から表示する在庫照会システムです。', timing_text: '一か月程度', budget_text: 'JPY 要相談', submitted_at: now, version: 1 },
    private_files: [],
    scope: { version: 1, request_version: 1, title: 'API 在庫照会システム', public_summary: '現在の在庫を確認する社内システム。', category: '業務開発', goal: '在庫照会を簡単にする', included_scope: '在庫一覧と検索', excluded_scope: '決済機能', deliverables: ['固定ソースと説明書'], acceptance_criteria: ['権限のある利用者のみ照会できる'], duration_text: '一か月', revision_terms: '確認済み範囲で一回修正', authored_at: now, reference_files: [] },
    reviews: ['compliance', 'technical'].map((kind, index) => ({ id: `50000000-0000-4000-8000-00000000000${index + 1}`, scope_version: 1, kind, decision: 'approved', reason: '現在の範囲を確認しました。', reviewer_id: account.id, decided_at: now })),
    clarifications: [], publications: [] as { id: string; scope_version: number; published_at: string; withdrawn_at: string | null }[],
  };
}
export async function installProtocol(page: Page) {
  const engagement = { id: engagementId, request_id: requestId, public_code: 'PRJ-API-001', customer_id: '20000000-0000-4000-8000-000000000001', provider_id: '10000000-0000-4000-8000-000000000002', status: 'internal_review', row_version: 4, created_at: now, closed_at: null };
  const detail = { engagement, agreements: [{ version: 1, scope_version: 1, terms: '合意済みの範囲で納品する。', quoted_amount: 100000, currency: 'JPY', due_at: '2026-11-22T01:00:00Z', authored_at: now, scope: requestFixture().scope }], confirmations: [{ agreement_version: 1, party: 'customer', confirmed_by: '20000000-0000-4000-8000-000000000001', confirmed_at: now }], deliveries: [{ id: deliveryId, version: 1, agreement_version: 1, note: '現在の固定版を確認してください。', source_file_id: null, repository_url: 'https://example.invalid/protocol-repository', source_commit: 'a'.repeat(40), source_archive_ref: null, guide_text: 'README の起動手順を参照。', test_report_text: '権限と在庫照会のテスト結果。', submitted_at: now, published: false, files: [] }], acceptances: [], assignments: [], reviews: [] as { id: string; delivery_id: string; reviewer_id: string; decision: string; evidence: string; reviewed_at: string }[], publications: [] as { id: string; delivery_id: string; withdrawn_at: string | null }[] };
  const state = {
    request: requestFixture(), detail, account: { ...account }, requestsStatus: 200, rejectLogin: false, expire: false, conflict: false,
    calls: [] as { method: string; path: string; body: unknown; authorization: string | undefined }[], unknown: [] as string[],
  };
  await page.route('http://127.0.0.1:8001/**', async route => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname;
    const method = request.method();
    const headers = { 'access-control-allow-origin': '*', 'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS', 'access-control-allow-headers': '*' };
    const fulfill = (body: unknown, status = 200) => route.fulfill({ status, headers, contentType: 'application/json', body: JSON.stringify(body) });
    if (method === 'OPTIONS') return fulfill(null, 204);
    const body = method === 'GET' ? undefined : request.postDataJSON();
    state.calls.push({ method, path: path + url.search, body, authorization: request.headers().authorization });
    const failure = (status: number, code: string, message: string) => fulfill({ error: { code, message }, request_id: 'test-request-id' }, status);
    if (path === '/health/ready') return fulfill({ status: 'ready', migrations: 6 });
    if (path === '/api/v1/capabilities') return fulfill(capabilities);
    if (path === '/api/v1/admin/auth/login') return state.rejectLogin ? failure(403, 'ADMIN_FORBIDDEN', '当前账号没有管理权限') : fulfill({ access_token: 'protocol-token-memory-only', token_type: 'bearer', audience: 'admin', expires_at: '2099-10-22T12:00:00Z' });
    if (state.expire) return failure(401, 'SESSION_EXPIRED', '会话已过期，请重新登录');
    if (path === '/api/v1/admin/auth/me') return fulfill(state.account);
    if (path === '/api/v1/admin/auth/logout') return fulfill({ revoked: true });
    if (path === '/api/v1/admin/dashboard') return fulfill({ requests: [{ intake_status: 'in_review', count: 1 }], engagements: [] });
    if (path === '/api/v1/admin/requests' && method === 'GET') {
      if (state.requestsStatus !== 200) return failure(state.requestsStatus, 'SERVICE_UNAVAILABLE', '测试服务当前不可用');
      const q = url.searchParams.get('q');
      const matches = !q || `${state.request.public_code} ${state.request.original.original_description}`.includes(q);
      return fulfill({ items: matches ? [state.request] : [], total: matches ? 1 : 0, limit: Number(url.searchParams.get('limit') || 20), offset: Number(url.searchParams.get('offset') || 0) });
    }
    if (path === `/api/v1/admin/requests/${requestId}`) return fulfill(state.request);
    if (path === `/api/v1/admin/requests/${requestId}/scopes` && method === 'GET') return fulfill({ items: [state.request.scope] });
    if (path === `/api/v1/admin/requests/${requestId}/publish` && method === 'POST') {
      if (state.conflict) return failure(409, 'VERSION_CONFLICT', '记录已变化，请刷新后重新操作');
      state.request.row_version++;
      state.request.publications.push({ id: '60000000-0000-4000-8000-000000000001', scope_version: 1, published_at: now, withdrawn_at: null });
      return fulfill(state.request, 201);
    }
    if (path === `/api/v1/admin/requests/${requestId}/publication/withdraw` && method === 'POST') {
      state.request.row_version++;
      state.request.publications.forEach(item => { item.withdrawn_at = now; });
      return fulfill(state.request);
    }
    if (path === '/api/v1/admin/accounts') return fulfill({ items: [account, { ...account, id: '10000000-0000-4000-8000-000000000002', email: 'provider@example.invalid', display_name: '指定内部成员', roles: ['provider'], internally_authorized: true }], limit: 20, offset: 0 });
    if (path === '/api/v1/admin/engagements') return fulfill({ items: [engagement], limit: 20, offset: 0 });
    if (path === `/api/v1/admin/engagements/${engagementId}`) return fulfill(detail);
    if (path === `/api/v1/admin/engagements/${engagementId}/deliveries/${deliveryId}/review` && method === 'POST') {
      if (state.conflict) return failure(409, 'VERSION_CONFLICT', '记录已变化，请刷新后重新操作');
      const input = body as { decision: string; evidence: string };
      detail.engagement.row_version++;
      detail.reviews.push({ id: '80000000-0000-4000-8000-000000000001', delivery_id: deliveryId, reviewer_id: account.id, decision: input.decision, evidence: input.evidence, reviewed_at: now });
      return fulfill({ row_version: detail.engagement.row_version });
    }
    if (path === '/api/v1/admin/audit-events') return fulfill({ items: [{ id: 10, occurred_at: now, application_actor_id: account.id, correlation_id: 'e2e-request-id', table_name: 'requests', operation: 'UPDATE', entity_key: { id: requestId }, changed_fields: ['intake_status'], details: {} }] });
    if (['/api/v1/admin/engagements', '/api/v1/admin/threads', '/api/v1/admin/notifications', '/api/v1/admin/files'].includes(path)) return fulfill({ items: [], limit: 20, offset: 0 });
    state.unknown.push(`${method} ${path}`);
    return failure(501, 'UNEXPECTED_PROTOCOL_CALL', `No protocol fixture for ${method} ${path}`);
  });
  return state;
}
export async function loginProtocol(page: Page, target = '/dashboard') {
  await page.goto(`/#${target}`);
  await page.locator('input[name="email"]').fill('admin@example.invalid');
  await page.locator('input[name="password"]').fill('protocol-only-password');
  await page.locator('.login-card button[type="submit"]').click();
  await expect(page.locator('.login-card')).toHaveCount(0);
}
export async function navigate(page: Page, route: string) {
  const changed = await page.evaluate(value => location.hash !== `#${value}`, route);
  const previousCard = changed ? await page.locator('.page-content .t-card').first().elementHandle() : null;
  await page.evaluate(value => { location.hash = value; }, route);
  await expect.poll(() => page.evaluate(() => location.hash)).toBe(`#${route}`);
  if (previousCard) await expect.poll(() => previousCard.evaluate(element => element.isConnected)).toBe(false);
  await expect(page.locator('h1')).toBeVisible();
  await expect(page.locator('.page-content .t-card').first()).toBeVisible();
  await expect(page.locator('.page-content .t-loading:visible')).toHaveCount(0);
}
