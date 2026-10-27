import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const account = {
  id: '10000000-0000-4000-8000-000000000001', email: 'reviewer@example.invalid', display_name: '测试管理账号',
  status: 'active', ui_locale: 'ja', row_version: 3, created_at: '2026-10-16T01:00:00Z',
  roles: ['administrator'], internally_authorized: false, opc_certified: false,
};
const tokenResponse = { access_token: 'test-token-memory-only', token_type: 'bearer', audience: 'admin', expires_at: '2099-10-22T12:00:00Z' };
const capabilitiesResponse = {
  service_codes: ['development'], locales: ['ja', 'zh'], currency: 'JPY', business_timezone: 'Asia/Tokyo',
  hall_audience: 'internal', assignment_mode: 'disabled', file_storage: 'local_private', file_inspection: 'manual_evidence',
  office_pdf_conversion: false, email_push_delivery: false, password_recovery: false, email_verification: false,
  ai_provider: false, payments: false, formal_certification: false,
};
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } });
const fetchStub = vi.fn<typeof fetch>();
const storage = { getItem: vi.fn(() => null), setItem: vi.fn(), removeItem: vi.fn(), clear: vi.fn(), key: vi.fn(), length: 0 };
let client: typeof import('../../src/services/api');
let eventTarget: EventTarget;

beforeEach(async () => {
  vi.resetModules();
  vi.clearAllMocks();
  eventTarget = new EventTarget();
  vi.stubGlobal('window', eventTarget);
  vi.stubGlobal('localStorage', storage);
  vi.stubGlobal('sessionStorage', storage);
  vi.stubGlobal('fetch', fetchStub);
  fetchStub.mockReset();
  client = await import('../../src/services/api');
});
afterEach(() => { client?.clearSession(); vi.unstubAllGlobals(); });

async function signIn() {
  fetchStub.mockResolvedValueOnce(json(tokenResponse)).mockResolvedValueOnce(json(account));
  await client.login('reviewer@example.invalid', 'not-a-real-password');
}

describe('真实 API 认证与会话边界', () => {
  it('管理登录核实 admin audience 和 me，凭据仅保存在内存', async () => {
    await signIn();
    expect(client.session.token).toBe('test-token-memory-only');
    expect(client.session.account).toMatchObject({ id: account.id, roles: ['administrator'] });
    expect(client.session.expiresAt).toBe(tokenResponse.expires_at);
    expect(storage.setItem).not.toHaveBeenCalled();
    const calls = fetchStub.mock.calls;
    expect(String(calls[0]?.[0])).toContain('/api/v1/admin/auth/login');
    expect(JSON.parse(String(calls[0]?.[1]?.body))).toEqual({ email: 'reviewer@example.invalid', password: 'not-a-real-password' });
    expect(new Headers(calls[1]?.[1]?.headers).get('authorization')).toBe('Bearer test-token-memory-only');
  });

  it('mobile audience 不能进入管理会话', async () => {
    fetchStub.mockResolvedValueOnce(json({ ...tokenResponse, audience: 'mobile' }));
    await expect(client.login('reviewer@example.invalid', 'not-a-real-password')).rejects.toBeInstanceOf(client.ApiError);
    expect(client.session.token).toBeNull();
    expect(client.session.account).toBeNull();
  });

  it('登录后 me 拒绝时清除临时 token，不留下半登录状态', async () => {
    fetchStub.mockResolvedValueOnce(json(tokenResponse)).mockResolvedValueOnce(json({ error: { code: 'ADMIN_FORBIDDEN', message: '当前账号没有管理权限' }, request_id: 'req-forbidden' }, 403));
    await expect(client.login('reviewer@example.invalid', 'not-a-real-password')).rejects.toMatchObject({ status: 403, code: 'ADMIN_FORBIDDEN' });
    expect(client.session.token).toBeNull();
    expect(client.session.account).toBeNull();
  });

  it('无会话的私有调用本地拒绝，不能访问真实管理数据', async () => {
    await expect(client.api('/api/v1/admin/requests')).rejects.toMatchObject({ status: 401 });
    expect(fetchStub).not.toHaveBeenCalled();
  });

  it('服务端 401 清空会话并通知页面清理私有数据', async () => {
    await signIn();
    const onLogout = vi.fn();
    eventTarget.addEventListener('opc:logout', onLogout);
    fetchStub.mockResolvedValueOnce(json({ error: { code: 'SESSION_EXPIRED', message: '会话已过期' }, request_id: 'request-expired' }, 401));
    await expect(client.api('/api/v1/admin/requests')).rejects.toMatchObject({ status: 401, code: 'SESSION_EXPIRED', requestId: 'request-expired' });
    expect(client.session.token).toBeNull();
    expect(client.session.account).toBeNull();
    expect(onLogout).toHaveBeenCalledOnce();
  });

  it('退出后迟到的成功响应不能把私有数据交给页面', async () => {
    await signIn();
    let resolveResponse!: (response: Response) => void;
    fetchStub.mockImplementationOnce(() => new Promise(resolve => { resolveResponse = resolve; }));
    const pending = client.api('/api/v1/admin/requests');
    const rejected = expect(pending).rejects.toBeInstanceOf(client.ApiError);
    client.clearSession();
    resolveResponse(json({ items: [{ id: 'private-record' }] }));
    await rejected;
    expect(client.session.token).toBeNull();
  });

  it('注销接口不可用时也清除本地会话', async () => {
    await signIn();
    fetchStub.mockRejectedValueOnce(new TypeError('Network unavailable'));
    try { await client.logout(); } catch { /* The caller may display a remote revoke failure. */ }
    expect(client.session.token).toBeNull();
    expect(client.session.account).toBeNull();
    expect(client.session.expiresAt).toBeNull();
  });

  it('较早登录的 me 迟到失败不能清除较新成功登录的会话', async () => {
    let finishOldMe!: (response: Response) => void;
    fetchStub.mockResolvedValueOnce(json(tokenResponse)).mockImplementationOnce(() => new Promise(resolve => { finishOldMe = resolve; }));
    const olderLogin = client.login('reviewer@example.invalid', 'not-a-real-password');
    const olderRejected = expect(olderLogin).rejects.toBeInstanceOf(client.ApiError);
    await vi.waitFor(() => expect(finishOldMe).toBeTypeOf('function'));
    const newerAccount = { ...account, id: '10000000-0000-4000-8000-000000000002', display_name: '新登录账号' };
    fetchStub.mockResolvedValueOnce(json({ ...tokenResponse, access_token: 'new-session-token' })).mockResolvedValueOnce(json(newerAccount));
    await client.login('newer@example.invalid', 'not-a-real-password');
    finishOldMe(json(account));
    await olderRejected;
    expect(client.session.token).toBe('new-session-token');
    expect(client.session.account?.id).toBe(newerAccount.id);
  });

  it('旧会话注销响应迟到不能注销新登录的账号', async () => {
    await signIn();
    let finishLogout!: (response: Response) => void;
    fetchStub.mockImplementationOnce(() => new Promise(resolve => { finishLogout = resolve; }));
    const oldLogout = client.logout().catch(() => undefined);
    fetchStub.mockResolvedValueOnce(json({ ...tokenResponse, access_token: 'new-session-token' })).mockResolvedValueOnce(json(account));
    await client.login('reviewer@example.invalid', 'not-a-real-password');
    finishLogout(json({ revoked: true }));
    await oldLogout;
    expect(client.session.token).toBe('new-session-token');
    expect(client.session.account?.id).toBe(account.id);
  });

  it('旧请求 401 错误正文迟到不能清除较新管理会话', async () => {
    await signIn();
    let finishBody!: (body: unknown) => void;
    const parse = vi.fn(() => new Promise(resolve => { finishBody = resolve; }));
    fetchStub.mockResolvedValueOnce({ ok: false, status: 401, headers: new Headers(), json: parse } as unknown as Response);
    const oldRequest = client.api('/api/v1/admin/requests');
    const rejected = expect(oldRequest).rejects.toBeInstanceOf(client.ApiError);
    await vi.waitFor(() => expect(parse).toHaveBeenCalledOnce());
    fetchStub.mockResolvedValueOnce(json({ ...tokenResponse, access_token: 'new-session-token' })).mockResolvedValueOnce(json(account));
    await client.login('reviewer@example.invalid', 'not-a-real-password');
    finishBody({ error: { code: 'SESSION_EXPIRED', message: '较早会话已失效' }, request_id: 'older-401' });
    await rejected;
    expect(client.session.token).toBe('new-session-token');
    expect(client.session.account?.id).toBe(account.id);
  });

  it.each(['disabled', 'active'])('me 返回非管理角色或禁用账号不能建立会话：%s', async status => {
    fetchStub.mockResolvedValueOnce(json(tokenResponse)).mockResolvedValueOnce(json({ ...account, status, roles: status === 'active' ? ['customer'] : ['administrator'] }));
    await expect(client.login('reviewer@example.invalid', 'not-a-real-password')).rejects.toMatchObject({ status: 403 });
    expect(client.session.token).toBeNull();
  });
});

describe('真实传输、错误与能力检测', () => {
  it('管理凭据不能随任意绝对 URL 或跨产品路径发出', async () => {
    await signIn();
    const callsAfterLogin = fetchStub.mock.calls.length;
    for (const path of ['https://other.example.invalid/data', '//other.example.invalid/data', '/api/v1/mobile/requests', '/api/v1/admin/../mobile/requests']) {
      await expect(client.api(path)).rejects.toMatchObject({ code: 'INVALID_API_PATH' });
    }
    expect(fetchStub.mock.calls).toHaveLength(callsAfterLogin);
  });
  it('写操作发送当前令牌、真实 JSON 及指定幂等键', async () => {
    await signIn();
    fetchStub.mockResolvedValueOnce(json({ id: 'server-id', row_version: 9 }, 201));
    const result = await client.api('/api/v1/admin/requests/request-id/publish', { method: 'POST', body: { expected_version: 8, reason: '已核对当前范围' }, idempotencyKey: 'publication-attempt-1' });
    expect(result).toEqual({ id: 'server-id', row_version: 9 });
    const init = fetchStub.mock.calls.at(-1)?.[1];
    expect(init?.method).toBe('POST');
    expect(new Headers(init?.headers).get('idempotency-key')).toBe('publication-attempt-1');
    expect(JSON.parse(String(init?.body))).toEqual({ expected_version: 8, reason: '已核对当前范围' });
  });

  it('上传 FormData 原样发送，浏览器负责 multipart boundary', async () => {
    await signIn();
    const form = new FormData(); form.append('file', new Blob(['actual bytes']), 'evidence.txt');
    fetchStub.mockResolvedValueOnce(json({ id: 'uploaded-file' }, 201));
    await client.api('/api/v1/admin/files', { method: 'POST', body: form });
    const init = fetchStub.mock.calls.at(-1)?.[1];
    expect(init?.body).toBe(form);
    expect(new Headers(init?.headers).get('content-type')).toBeNull();
  });

  it.each([403, 409, 422, 503])('HTTP %s 保留服务端稳定错误码和 request_id，不返回 Mock 成功', async status => {
    await signIn();
    fetchStub.mockResolvedValueOnce(json({ error: { code: 'SERVER_RULE_REJECTED', message: '当前操作不满足服务端规则' }, request_id: `case-${status}` }, status));
    await expect(client.api('/api/v1/admin/requests')).rejects.toMatchObject({ status, code: 'SERVER_RULE_REJECTED', message: '当前操作不满足服务端规则', requestId: `case-${status}` });
    expect(client.session.account?.id).toBe(account.id);
  });

  it('网络中断明确失败，不生成默认业务记录', async () => {
    await signIn();
    fetchStub.mockRejectedValueOnce(new TypeError('Failed to fetch'));
    await expect(client.api('/api/v1/admin/requests')).rejects.toBeInstanceOf(client.ApiError);
    expect(client.connection.value).toBe('disconnected');
  });

  it('非 JSON 错误响应也返回结构化错误，不把 HTML 当业务数据', async () => {
    await signIn();
    fetchStub.mockResolvedValueOnce(new Response('<html>Bad gateway</html>', { status: 502, headers: { 'content-type': 'text/html' } }));
    await expect(client.api('/api/v1/admin/requests')).rejects.toMatchObject({ status: 502 });
  });

  it('就绪与实际能力从公开端点读取，未接入能力不伪造可用', async () => {
    fetchStub.mockImplementation(async url => String(url).endsWith('/health/ready') ? json({ status: 'ready' }) : json(capabilitiesResponse));
    await client.checkConnection();
    expect(client.connection.value).toBe('connected');
    expect(client.capabilities.value).toMatchObject({ payments: false, ai_provider: false, office_pdf_conversion: false, assignment_mode: 'disabled' });
    expect(client.session.token).toBeNull();
  });

  it('就绪检测失败清空旧能力数据并标记断开', async () => {
    fetchStub.mockImplementation(async url => String(url).endsWith('/health/ready') ? json({ status: 'ready' }) : json(capabilitiesResponse));
    await client.checkConnection();
    fetchStub.mockRejectedValue(new TypeError('offline'));
    try { await client.checkConnection(); } catch { /* Both signalling designs must retain disconnected state. */ }
    expect(client.connection.value).toBe('disconnected');
    expect(client.capabilities.value).toBeNull();
  });
});
