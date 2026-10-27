import { reactive } from 'vue';
import { api, ApiError } from './api';
import { locale } from '../composables/preferences';
import { requestApiZh, requestApiJa } from '../locales/requests-api';

export type ReviewStatus = 'pending' | 'needs_info' | 'approved' | 'rejected';
export type TechStatus = ReviewStatus | 'not_started';
export type PublicationStatus = 'unpublished' | 'ready' | 'published' | 'withdrawn';
export interface RequestFile { file_id: string; original_name: string; upload_status: string; scan_status: string; size_bytes: number; }
export interface ScopeRecord {
  version: number; request_version: number; title: string; public_summary: string; category: string;
  goal: string; included_scope: string; excluded_scope: string; deliverables: string[];
  acceptance_criteria: string[]; duration_text: string; revision_terms: string; authored_at: string;
  reference_files: RequestFile[];
}
export interface ReviewRecord { id: string; scope_version: number; kind: 'compliance' | 'technical'; decision: Exclude<ReviewStatus, 'pending'>; reason: string; reviewer_id: string; decided_at: string; }
export interface ClarificationRecord { id: string; question: string; answer: string | null; asked_at: string; answered_at: string | null; request_version: number; }
export interface PublicationRecord { id: string; scope_version: number; published_at: string; withdrawn_at: string | null; withdrawal_reason?: string | null; }
export interface RequestDetail {
  id: string; public_code: string; customer_id: string; intake_status: string; current_request_version: number;
  current_scope_version: number | null; row_version: number; created_at: string; updated_at: string;
  original: { original_description: string; timing_text: string; budget_text: string; submitted_at: string; version: number };
  private_files: RequestFile[]; scope: ScopeRecord | null; reviews: ReviewRecord[];
  clarifications: ClarificationRecord[]; publications: PublicationRecord[];
}
export interface RequestRecord extends RequestDetail {
  title: string; originalText: string; customer: string; submittedAt: string; updatedAt: string;
  version: string; revision: number; compliance: ReviewStatus; technical: TechStatus;
  complianceVersion: string | null; technicalVersion: string | null; publication: PublicationStatus;
}
export interface TechnicalDraft {
  title: string; public_summary: string; category: string; goal: string; included_scope: string;
  excluded_scope: string; deliverables: string; acceptance_criteria: string;
  duration_text: string; revision_terms: string; file_ids: string[];
}
export function scopeDraft(scope: ScopeRecord | null): TechnicalDraft {
  return {
    title: scope?.title ?? '', public_summary: scope?.public_summary ?? '', category: scope?.category ?? '',
    goal: scope?.goal ?? '', included_scope: scope?.included_scope ?? '', excluded_scope: scope?.excluded_scope ?? '',
    deliverables: scope?.deliverables.join('\n') ?? '', acceptance_criteria: scope?.acceptance_criteria.join('\n') ?? '',
    duration_text: scope?.duration_text ?? '', revision_terms: scope?.revision_terms ?? '',
    file_ids: scope?.reference_files.map(file => file.file_id) ?? [],
  };
}
export function scopePayload(draft: TechnicalDraft, expectedVersion: number) {
  const lines = (text: string) => text.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  return { ...draft, expected_version: expectedVersion, deliverables: lines(draft.deliverables), acceptance_criteria: lines(draft.acceptance_criteria) };
}
export function mapRequest(detail: RequestDetail): RequestRecord {
  const current = detail.scope?.request_version === detail.current_request_version && detail.scope?.version === detail.current_scope_version;
  const review = (kind: ReviewRecord['kind']) => current ? detail.reviews.find(item => item.kind === kind && item.scope_version === detail.current_scope_version) : undefined;
  const compliance = review('compliance'), technical = review('technical');
  const active = detail.publications.find(item => !item.withdrawn_at && item.scope_version === detail.current_scope_version);
  const open = !['closed', 'withdrawn'].includes(detail.intake_status);
  const both = compliance?.decision === 'approved' && technical?.decision === 'approved';
  const ready = current && open && both && !detail.clarifications.some(item => item.answer === null);
  return { ...detail,
    title: detail.scope?.title || detail.original.original_description.slice(0, 80), originalText: detail.original.original_description,
    customer: detail.customer_id, submittedAt: detail.original.submitted_at, updatedAt: detail.updated_at,
    version: detail.current_scope_version === null ? '—' : `v${detail.current_scope_version}`, revision: detail.row_version,
    compliance: compliance?.decision ?? 'pending', technical: technical?.decision ?? (current ? 'pending' : 'not_started'),
    complianceVersion: compliance?.decision === 'approved' ? `v${compliance.scope_version}` : null,
    technicalVersion: technical?.decision === 'approved' ? `v${technical.scope_version}` : null,
    publication: active && ready ? 'published' : ready ? 'ready' : detail.publications.length ? 'withdrawn' : 'unpublished',
  };
}
export function isPublishable(request: RequestRecord) { return request.publication === 'ready'; }
export function isRequestOpen(request: RequestRecord) { return !['closed', 'withdrawn'].includes(request.intake_status); }
export function hasReview(request: RequestRecord, kind: ReviewRecord['kind']) {
  return request.reviews.some(review => review.kind === kind && review.scope_version === request.current_scope_version);
}
type Transport = typeof api;
export function createAdminRepository(transport: Transport = api) {
  const state = reactive({ requests: [] as RequestRecord[], details: {} as Record<string, RequestRecord>, total: 0, loading: false });
  let epoch = 0, listRun = 0;
  const path = (id: string) => `/api/v1/admin/requests/${encodeURIComponent(id)}`;
  function remember(detail: RequestDetail, started: number) {
    if (started !== epoch) throw new Error('SESSION_CHANGED');
    const mapped = mapRequest(detail);
    state.details[mapped.id] = mapped;
    const index = state.requests.findIndex(item => item.id === mapped.id);
    if (index >= 0) state.requests[index] = mapped;
    return mapped;
  }
  async function mutate(id: string, suffix: string, body: unknown) {
    const started = epoch;
    return remember(await transport<RequestDetail>(`${path(id)}/${suffix}`, { method: 'POST', body }), started);
  }
  return {
    get requests() { return state.requests; }, get details() { return state.details; }, get total() { return state.total; },
    get loading() { return state.loading; },
    async loadPage(options: { page?: number; pageSize?: number; q?: string; status?: string } = {}) {
      const run = ++listRun, started = epoch, size = options.pageSize ?? 20;
      state.loading = true; state.requests = []; state.total = 0;
      try {
        const query = new URLSearchParams({ limit: String(size), offset: String(((options.page ?? 1) - 1) * size) });
        if (options.q) query.set('q', options.q);
        if (options.status) query.set('status', options.status);
        const page = await transport<{ items: { id: string }[]; total: number }>(`/api/v1/admin/requests?${query}`);
        const records: RequestRecord[] = [];
        for (let index = 0; index < page.items.length; index += 5) {
          const batch = await Promise.all(page.items.slice(index, index + 5).map(async item => mapRequest(await transport<RequestDetail>(path(item.id)))));
          if (started !== epoch || run !== listRun) return;
          records.push(...batch);
        }
        if (started !== epoch || run !== listRun) return;
        state.requests = records; state.total = page.total;
        records.forEach(record => { state.details[record.id] = record; });
      } catch (error) {
        // A cancelled older search/session must not surface over a newer result.
        if (started === epoch && run === listRun) throw error;
      } finally { if (started === epoch && run === listRun) state.loading = false; }
    },
    async load(id: string) { const started = epoch; return remember(await transport<RequestDetail>(path(id)), started); },
    async scopes(id: string) { return (await transport<{ items: ScopeRecord[] }>(`${path(id)}/scopes`)).items; },
    createScope(id: string, revision: number, draft: TechnicalDraft) { return mutate(id, 'scopes', scopePayload(draft, revision)); },
    review(id: string, revision: number, scopeVersion: number, kind: ReviewRecord['kind'], decision: ReviewRecord['decision'], reason: string, question?: string) {
      return mutate(id, 'reviews', { expected_version: revision, scope_version: scopeVersion, kind, decision, reason, ...(decision === 'needs_info' ? { question } : {}) });
    },
    clarify(id: string, revision: number, question: string) { return mutate(id, 'clarifications', { expected_version: revision, question }); },
    publish(id: string, revision: number, scopeVersion: number, reason: string) { return mutate(id, 'publish', { expected_version: revision, scope_version: scopeVersion, reason }); },
    unpublish(id: string, revision: number, reason: string) { return mutate(id, 'publication/withdraw', { expected_version: revision, reason }); },
    reset() { epoch++; listRun++; state.requests = []; state.details = {}; state.total = 0; state.loading = false; },
  };
}
export const adminRepository = createAdminRepository();
if (typeof window !== 'undefined') window.addEventListener('opc:logout', () => adminRepository.reset());
export function requestError(error: unknown) {
  const code = error instanceof ApiError ? error.code : error instanceof Error && /^[A-Z_]+$/.test(error.message) ? error.message : 'UNKNOWN_ERROR';
  const resources = locale.value === 'ja-JP' ? requestApiJa : requestApiZh;
  const message = resources['req.error.' + code] ?? resources['req.error.UNKNOWN_ERROR'];
  const requestId = error instanceof ApiError && error.requestId ? ' · Request ID: ' + error.requestId : '';
  return message + ' [' + code + ']' + requestId;
}

