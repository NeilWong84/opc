import { reactive, ref } from 'vue';

export interface AdminAccount {
  id: string; email: string; display_name: string; status: string; ui_locale: string;
  roles: string[]; row_version: number; internally_authorized: boolean; opc_certified: boolean;
}
export type Capabilities = Record<string, boolean | string | string[]>;
export const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL || 'http://127.0.0.1:8001').replace(/\/$/, '');
export const session = reactive<{token:string|null;account:AdminAccount|null;expiresAt:string|null}>({token:null,account:null,expiresAt:null});
export const connection = ref<'checking'|'connected'|'disconnected'>('checking');
export const capabilities = ref<Capabilities|null>(null);
export class ApiError extends Error {
  constructor(public status:number, public code:string, message:string, public requestId?:string) { super(message); this.name='ApiError'; }
}
type Options = {method?:string;body?:unknown;idempotencyKey?:string;signal?:AbortSignal};
const pending = new Set<AbortController>();
let generation=0;
let expiryTimer:ReturnType<typeof setTimeout>|undefined;
export function clearSession() {
  generation++;
  clearTimeout(expiryTimer);
  session.token=null; session.account=null; session.expiresAt=null;
  for(const controller of pending) controller.abort();
  pending.clear();
  if(typeof window!=='undefined') window.dispatchEvent(new Event('opc:logout'));
}
function validatePath(path:string) {
  if(!/^\/(?:api\/v1\/(?:admin(?:\/|$)|capabilities$|services$)|health\/(?:ready|live)$)/.test(path) || path.includes('..') || path.includes('\\')) {
    throw new ApiError(0,'INVALID_API_PATH','Invalid API path');
  }
}
async function request(path:string, options:Options={}, binary=false):Promise<unknown> {
  validatePath(path);
  const loginPath=path==='/api/v1/admin/auth/login';
  const privatePath=path.startsWith('/api/v1/admin/')&&!loginPath;
  const token=session.token, started=generation;
  if(privatePath&&!token) throw new ApiError(401,'AUTH_REQUIRED','请先登录管理后台');
  const controller=new AbortController();
  const abort=()=>controller.abort();
  if(options.signal?.aborted) controller.abort();
  else options.signal?.addEventListener('abort',abort,{once:true});
  pending.add(controller);
  let timedOut=false;
  const timer=setTimeout(()=>{timedOut=true;controller.abort();},20000);
  const headers=new Headers({Accept:binary?'application/octet-stream':'application/json'});
  if(privatePath&&token) headers.set('Authorization',`Bearer ${token}`);
  if(options.idempotencyKey) headers.set('Idempotency-Key',options.idempotencyKey);
  const form=options.body instanceof FormData;
  if(options.body!==undefined&&!form) headers.set('Content-Type','application/json');
  try {
    const response=await fetch(`${API_BASE_URL}${path}`,{
      method:options.method||'GET',headers,credentials:'omit',cache:'no-store',redirect:'error',signal:controller.signal,
      body:options.body===undefined?undefined:form?options.body as FormData:JSON.stringify(options.body),
    });
    if(started!==generation) throw new ApiError(401,'SESSION_CHANGED','登录状态已改变，请重新登录');
    if(!response.ok) {
      const data=await response.json().catch(()=>null);
      if(started!==generation) throw new ApiError(401,'SESSION_CHANGED','登录状态已改变，请重新登录');
      if(response.status===401&&privatePath) clearSession();
      if(response.status>=500) connection.value='disconnected';
      throw new ApiError(response.status,data?.error?.code||`HTTP_${response.status}`,data?.error?.message||`API 请求失败 (${response.status})`,data?.request_id||response.headers.get('X-Request-ID')||undefined);
    }
    const data=binary?await response.blob():response.status===204?null:await response.json();
    if(started!==generation) throw new ApiError(401,'SESSION_CHANGED','登录状态已改变，请重新登录');
    connection.value='connected';
    return data;
  } catch(error) {
    if(error instanceof ApiError) throw error;
    if(started!==generation) throw new ApiError(401,'SESSION_CHANGED','登录状态已改变，请重新登录');
    if(controller.signal.aborted&&!timedOut) throw new ApiError(0,'REQUEST_CANCELLED','请求已取消');
    connection.value='disconnected';
    throw new ApiError(0,timedOut?'REQUEST_TIMEOUT':'NETWORK_ERROR',timedOut?'请求超时，请检查服务状态后重试':'无法连接后台服务，请检查网络或服务状态');
  } finally {
    clearTimeout(timer);pending.delete(controller);options.signal?.removeEventListener('abort',abort);
  }
}
export async function api<T>(path:string,options:Options={}):Promise<T> { return request(path,options) as Promise<T>; }
export async function login(email:string,password:string) {
  clearSession();
  const attempt=generation;
  const result=await api<{access_token:string;audience:string;token_type:string;expires_at:string}>('/api/v1/admin/auth/login',{method:'POST',body:{email:email.trim(),password}});
  if(attempt!==generation) throw new ApiError(401,'SESSION_CHANGED','登录状态已改变，请重新登录');
  if(result.audience!=='admin'||result.token_type!=='bearer'||!result.access_token) throw new ApiError(403,'ADMIN_FORBIDDEN','当前账号没有管理权限');
  const expires=Date.parse(result.expires_at);
  if(!Number.isFinite(expires)||expires<=Date.now()) throw new ApiError(401,'SESSION_EXPIRED','登录会话已过期');
  session.token=result.access_token;session.expiresAt=result.expires_at;
  try {
    const account=await api<AdminAccount>('/api/v1/admin/auth/me');
    if(attempt!==generation) throw new ApiError(401,'SESSION_CHANGED','登录状态已改变，请重新登录');
    const roles=['administrator','operator','compliance_reviewer','technical_reviewer','quality_reviewer'];
    if(account.status!=='active'||!account.roles.some(role=>roles.includes(role))) throw new ApiError(403,'ADMIN_FORBIDDEN','当前账号没有管理权限');
    session.account=account;
    expiryTimer=setTimeout(clearSession,Math.min(expires-Date.now(),2147483647));
  } catch(error) {if(attempt===generation)clearSession();throw error;}
}
export async function logout() {
  const attempt=generation;
  try { if(session.token) await api('/api/v1/admin/auth/logout',{method:'POST'}); }
  finally { if(attempt===generation)clearSession(); }
}
export async function checkConnection() {
  connection.value='checking';
  try {
    const ready=await api<{status:string}>('/health/ready');
    if(ready.status!=='ready') throw new ApiError(503,'SERVICE_NOT_READY','后台服务尚未就绪');
    capabilities.value=await api<Capabilities>('/api/v1/capabilities');
    connection.value='connected';
  } catch(error) {connection.value='disconnected';capabilities.value=null;throw error;}
}
export async function downloadFile(path:string,filename:string) {
  const blob=await request(path,{},true) as Blob;
  const url=URL.createObjectURL(blob),link=document.createElement('a');
  link.href=url;link.download=filename;link.click();
  setTimeout(()=>URL.revokeObjectURL(url),1000);
}
