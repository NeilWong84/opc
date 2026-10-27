import { api, downloadFile } from './api';
export interface Page<T> { items: T[]; limit: number; offset: number }
export interface Member { id:string; email:string; display_name:string; status:'active'|'disabled'; ui_locale:'zh'|'ja'; row_version:number; roles:string[]; internally_authorized:boolean; opc_certified:boolean }
export interface Engagement { id:string; request_id:string; public_code:string; customer_id:string; provider_id:string|null; status:string; row_version:number; created_at:string; closed_at:string|null }
export interface FileRecord { id:string; original_name:string; media_type:string; kind:string; size_bytes:number; sha256:string; row_version:number; scan_status:string; upload_status:string; purpose?:string }
export interface Delivery { id:string; version:number; agreement_version:number; note:string; source_file_id:string|null; repository_url:string|null; source_commit:string|null; source_archive_ref:string|null; guide_text:string; test_report_text:string; submitted_at:string; published:boolean; files:FileRecord[] }
export interface Agreement { version:number; scope_version:number; terms:string; quoted_amount:number|null; currency:string; due_at:string|null; authored_at:string; scope:{title:string;goal:string;included_scope:string;excluded_scope:string;deliverables:string[];acceptance_criteria:string[];reference_files:FileRecord[]} }
export interface Review { id:string; delivery_id:string; reviewer_id:string; decision:string; evidence:string; reviewed_at?:string; created_at?:string }
export interface EngagementDetail { engagement:Engagement; agreements:Agreement[]; confirmations:{agreement_version:number;party:string;confirmed_by:string;confirmed_at:string}[]; deliveries:Delivery[]; acceptances:{id:string;delivery_id:string;delivery_version:number;decision:string;feedback:string;decided_at:string}[]; assignments:Record<string,unknown>[]; reviews:Review[]; publications:{id:string;delivery_id:string;withdrawn_at:string|null}[] }
export interface Thread { id:string; request_id:string; engagement_id:string|null; kind:'internal'|'customer_project'|'consultation'; created_at:string }
export interface Message { id:string; author_id:string; author_name:string; body:string; sent_at:string; client_message_id:string }
export class OperationError extends Error { constructor(public code:string) { super(code); } }
const root='/api/v1/admin';
const id=(value:string)=>encodeURIComponent(value);
const post=<T>(path:string,body:unknown)=>api<T>(path,{method:'POST',body});
function reason(value:string) { if(!value.trim()) throw new OperationError('reasonRequired'); return value.trim(); }
export const listEngagements=(offset=0,limit=20)=>api<Page<Engagement>>(`${root}/engagements?limit=${limit}&offset=${offset}`);
export const getEngagement=(engagementId:string)=>api<EngagementDetail>(`${root}/engagements/${id(engagementId)}`);
export const listMembers=(offset=0,limit=20)=>api<Page<Member>>(`${root}/accounts?limit=${limit}&offset=${offset}`);
export const createMember=(body:{display_name:string;email:string;password:string;ui_locale:'zh'|'ja'})=>post<Member>(`${root}/accounts`,body);
export const changeMemberStatus=(accountId:string,version:number,status:'active'|'disabled',note:string)=>api<Member>(`${root}/accounts/${id(accountId)}/status`,{method:'PUT',body:{expected_version:version,status,reason:reason(note)}});
export const changeProviderRole=(accountId:string,grant:boolean,note:string)=>post(`${root}/accounts/${id(accountId)}/roles${grant?'':'/revoke'}`,{role:'provider',reason:reason(note)});
export const changeProviderAuthorization=(accountId:string,grant:boolean,note:string)=>post(`${root}/accounts/${id(accountId)}/provider-authorization${grant?'':'/revoke'}`,{reason:reason(note)});
export const listThreads=(offset=0,limit=100)=>api<Page<Thread>>(`${root}/threads?limit=${limit}&offset=${offset}`);
export const listMessages=(threadId:string,offset=0,limit=50)=>api<Page<Message>>(`${root}/threads/${id(threadId)}/messages?limit=${limit}&offset=${offset}`);
export const createInternalThread=(requestId:string,engagementId:string)=>post<{id:string}>(`${root}/threads`,{request_id:requestId,engagement_id:engagementId,kind:'internal'});
export const sendProjectMessage=(threadId:string,body:string,clientMessageId:string)=>post<Message>(`${root}/threads/${id(threadId)}/messages`,{body:reason(body),client_message_id:clientMessageId});
export async function reviewDelivery(engagementId:string,deliveryId:string,version:number,decision:'approved'|'changes_requested'|'rejected',evidence:string,checks:boolean[]=[]) {
 if(decision==='approved'&&(checks.length!==4||!checks.every(Boolean))) throw new OperationError('checklistRequired');
 return post<{row_version:number}>(`${root}/engagements/${id(engagementId)}/deliveries/${id(deliveryId)}/review`,{expected_version:version,decision,evidence:reason(evidence)});
}
export const publishDelivery=(engagementId:string,deliveryId:string,version:number)=>post<{row_version:number}>(`${root}/engagements/${id(engagementId)}/deliveries/${id(deliveryId)}/publish`,{expected_version:version});
export const withdrawDelivery=(engagementId:string,deliveryId:string,version:number,note:string)=>post<{row_version:number}>(`${root}/engagements/${id(engagementId)}/deliveries/${id(deliveryId)}/withdraw`,{expected_version:version,reason:reason(note)});
export const getFile=(fileId:string)=>api<FileRecord>(`${root}/files/${id(fileId)}`);
export const listFiles=(offset=0,scanStatus='')=>api<Page<FileRecord>>(`${root}/files?limit=20&offset=${offset}${scanStatus?`&scan_status=${id(scanStatus)}`:''}`);
export const inspectFile=(fileId:string,version:number,decision:'clean'|'rejected',note:string)=>post<FileRecord>(`${root}/files/${id(fileId)}/inspection`,{expected_version:version,decision,reason:reason(note)});
export const downloadOriginal=(file:Pick<FileRecord,'id'|'original_name'>)=>downloadFile(`${root}/files/${id(file.id)}/download`,file.original_name);

