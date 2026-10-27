import { loadEnv } from 'vite';
const env={...loadEnv('production',process.cwd(),'VITE_'),...process.env};
try {
  const url=new URL(env.VITE_API_BASE_URL||'');
  if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash||url.pathname!=='/'||['localhost','127.0.0.1','[::1]','0.0.0.0'].includes(url.hostname)) throw new Error();
  console.log('Production API configuration accepted. Backend deployment, CORS and permissions must be verified separately.');
} catch {
  console.error('Production build requires an explicit HTTPS VITE_API_BASE_URL for the deployed backend in .env.production.local or the build environment. The current local API configuration is for local integration.');
  process.exit(1);
}
