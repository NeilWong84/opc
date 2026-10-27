import { createRouter, createWebHashHistory } from 'vue-router';
import { session } from './services/api';

export const router = createRouter({
  history: createWebHashHistory(),
  scrollBehavior: () => ({ top: 0 }),
  routes: [
    { path: '/login', name: 'login', component: () => import('./views/LoginView.vue') },
    { path: '/', redirect: '/dashboard' },
    { path: '/dashboard', name: 'dashboard', component: () => import('./views/DashboardView.vue') },
    { path: '/reviews', name: 'reviews', component: () => import('./views/ReviewListView.vue') },
    { path: '/reviews/:id', name: 'compliance', component: () => import('./views/ComplianceView.vue') },
    { path: '/technical', name: 'technical', component: () => import('./views/TechnicalView.vue') },
    { path: '/publishing', name: 'publishing', component: () => import('./views/PublishingView.vue') },
    { path: '/projects', name: 'projects', component: () => import('./views/ProjectView.vue') },
    { path: '/delivery', name: 'delivery', component: () => import('./views/DeliveryView.vue') },
    { path: '/members', name: 'members', component: () => import('./views/MembersView.vue') },
    { path: '/tickets', name: 'tickets', component: () => import('./views/TicketsView.vue') },
    { path: '/audit', name: 'audit', component: () => import('./views/AuditView.vue') },
    { path: '/:pathMatch(.*)*', name: 'notFound', component: () => import('./views/NotFoundView.vue') },
  ],
});
router.beforeEach(to=>{
  if(to.name!=='login'&&!session.account) return {name:'login',query:{redirect:to.fullPath}};
  if(to.name==='dashboard'&&session.account?.roles.includes('quality_reviewer')&&!session.account.roles.some(role=>['administrator','operator','compliance_reviewer','technical_reviewer'].includes(role))) return {name:'delivery'};
  if(to.name==='login'&&session.account) return {name:'dashboard'};
});
