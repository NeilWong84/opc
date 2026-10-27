/** Read-only business smoke. Only creates and revokes its own short-lived auth session. */
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const base = process.env.OPC_ADMIN_SMOKE_URL || 'http://127.0.0.1:8001';
if (!['127.0.0.1', 'localhost'].includes(new URL(base).hostname)) throw new Error('Live smoke requires an explicitly local API.');
const credentialPath = fileURLToPath(new URL('../../BackendService/.local/demo-credentials.json', import.meta.url));
const credentials = JSON.parse(await readFile(credentialPath, 'utf8')).accounts.admin;
let token;
const results = [];
async function request(path, options = {}) {
  const response = await fetch(`${base}${path}`, {
    method: options.method || 'GET',
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(options.body ? { 'Content-Type': 'application/json' } : {}) },
    body: options.body ? JSON.stringify(options.body) : undefined,
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${path}: HTTP ${response.status}`);
  return response.json();
}
try {
  const readiness = await request('/health/ready');
  results.push({ check: 'readiness', status: readiness.status, migrations: readiness.migrations });
  const auth = await request('/api/v1/admin/auth/login', { method: 'POST', body: { email: credentials.email, password: credentials.password } });
  if (auth.audience !== 'admin') throw new Error('Wrong auth audience');
  token = auth.access_token;
  const me = await request('/api/v1/admin/auth/me');
  if (!me.roles.includes('administrator')) throw new Error('Smoke account lacks administrator role');
  results.push({ check: 'admin_auth', audience: auth.audience, status: me.status, roleVerified: true });
  for (const endpoint of ['dashboard', 'requests?limit=100&offset=0', 'engagements?limit=100&offset=0', 'accounts?limit=100&offset=0', 'threads?limit=100&offset=0', 'files?limit=100&offset=0', 'audit-events?limit=10']) {
    const data = await request(`/api/v1/admin/${endpoint}`);
    results.push({ check: endpoint.split('?')[0], readable: true, count: data.items?.length, total: data.total });
    if (endpoint.startsWith('requests?') && data.items.length) {
      const detail = await request(`/api/v1/admin/requests/${data.items[0].id}`);
      if (!detail.original || !Array.isArray(detail.reviews)) throw new Error('Request detail contract mismatch');
      results.push({ check: 'request_detail', readable: true, hasOriginal: true, rowVersion: detail.row_version });
    }
    if (endpoint.startsWith('engagements?') && data.items.length) {
      const detail = await request(`/api/v1/admin/engagements/${data.items[0].id}`);
      if (!detail.engagement || !Array.isArray(detail.deliveries)) throw new Error('Engagement detail contract mismatch');
      results.push({ check: 'engagement_detail', readable: true, deliveries: detail.deliveries.length });
    }
  }
} finally {
  if (token) {
    await request('/api/v1/admin/auth/logout', { method: 'POST' });
    results.push({ check: 'own_session_revoked', revoked: true });
  }
}
console.log(JSON.stringify({ businessWrites: 0, checks: results }, null, 2));
