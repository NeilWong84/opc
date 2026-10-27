<script setup lang="ts">
import { computed, onMounted, onUnmounted, provide, ref, shallowReactive, watch } from 'vue';
import { useRoute,useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import zhCN from 'tdesign-vue-next/es/locale/zh_CN';
import jaJP from 'tdesign-vue-next/es/locale/ja_JP';
import type { GlobalConfigProvider } from 'tdesign-vue-next';
import { Icon } from 'tdesign-icons-vue-next';
import { locale,theme,resolvedTheme,uiScale,scaleOptions } from './composables/preferences';
import { api,API_BASE_URL,checkConnection,connection,logout,session } from './services/api';
import { formatJst } from './utils/format';
import { scaledPopupProps } from './utils/scaled-popup';
import PageNotice from './components/PageNotice.vue';
import { pageNotificationsKey, PageNotificationContent, type PageNotification } from './composables/page-notifications';
const route=useRoute(),router=useRouter(),{t,te,locale:i18nLocale}=useI18n();
const collapsed=ref(false),aboutVisible=ref(false),notificationsVisible=ref(false),notificationBusy=ref(false),notificationError=ref(''),connectionError=ref(''),logoutError=ref('');
const active=computed(()=>route.name==='compliance'?'reviews':String(route.name));
const page=computed(()=>String(route.name||'dashboard'));
const loggedIn=computed(()=>Boolean(session.account)&&route.name!=='login');
const pageNotifications=shallowReactive(new Map<symbol,PageNotification>());
const contextNotifications=computed(()=>Array.from(pageNotifications.values()));
const notificationTab=ref<'context'|'inbox'>('context');
const contextLeaving=ref(0);
provide(pageNotificationsKey,pageNotifications);
provide('page-notice-target', computed(()=>loggedIn.value?'#page-notices':null));
const isLocal=computed(()=>['localhost','127.0.0.1','[::1]'].includes(new URL(API_BASE_URL).hostname));
type MutableLocale<T> = { -readonly [K in keyof T]: MutableLocale<T[K]> };
const config=computed<GlobalConfigProvider>(()=>structuredClone(locale.value==='ja-JP'?jaJP:zhCN) as MutableLocale<typeof zhCN>);
const now=ref(new Date().toISOString());
const navItems=[['dashboard','dashboard'],['reviews','task-checked'],['technical','task'],['publishing','sound'],['projects','folder-open'],['delivery','file-safety'],['members','usergroup'],['tickets','error-circle'],['audit','history']] as const;
interface Notification {id:string;template_key:string;parameters:Record<string,unknown>;created_at:string;read_at:string|null}
const notifications=ref<Notification[]>([]);
let notificationRequest=0;
async function connect() {connectionError.value='';try{await checkConnection();}catch(e){connectionError.value=e instanceof Error?e.message:t('error.unexpected');}}
async function showNotifications() {
  const request=++notificationRequest,accountId=session.account?.id;
  notificationTab.value=pageNotifications.size?'context':'inbox';
  notificationsVisible.value=true;notificationBusy.value=true;notificationError.value='';notifications.value=[];
  try{const result=await api<{items:Notification[]}>('/api/v1/admin/notifications?limit=30');if(request===notificationRequest&&accountId===session.account?.id)notifications.value=result.items;}
  catch(e){if(request===notificationRequest&&accountId===session.account?.id)notificationError.value=e instanceof Error?e.message:t('error.unexpected');}
  finally{if(request===notificationRequest)notificationBusy.value=false;}
}
async function markRead(item:Notification) {
  const accountId=session.account?.id,request=notificationRequest;
  try{const result=await api<{read_at:string}>(`/api/v1/admin/notifications/${item.id}/read`,{method:'POST'});if(accountId===session.account?.id){item.read_at=result.read_at;const current=notifications.value.find(value=>value.id===item.id);if(current)current.read_at=result.read_at;}}
  catch(e){if(accountId===session.account?.id&&request===notificationRequest)notificationError.value=e instanceof Error?e.message:t('error.unexpected');}
}
async function signOut() {
  logoutError.value='';
  try{await logout();}catch{logoutError.value=t('auth.logoutFailed');}
}
watch(locale,value=>{i18nLocale.value=value;},{immediate:true});
watch(connection,value=>{if(value==='connected')connectionError.value='';});
watch(()=>[page.value,locale.value],()=>{document.title=`${t(loggedIn.value?`nav.${page.value}`:'auth.title')} · OPC Admin`;},{immediate:true});
watch(()=>session.account,account=>{
  if(!account){++notificationRequest;pageNotifications.clear();notifications.value=[];notificationError.value='';notificationBusy.value=false;notificationsVisible.value=false;aboutVisible.value=false;if(route.name!=='login')void router.replace({name:'login',query:{redirect:route.fullPath}});}
});
watch(()=>route.fullPath,()=>{notificationsVisible.value=false;});
let clockTimer:ReturnType<typeof setInterval>;
onMounted(()=>{void connect();clockTimer=setInterval(()=>{now.value=new Date().toISOString();},60000);});
onUnmounted(()=>clearInterval(clockTimer));
</script>
<template>
  <t-config-provider :global-config="config">
    <div :class="[loggedIn?'admin-shell':'login-shell',{'is-collapsed':collapsed}]">
      <aside v-if="loggedIn" class="app-sidebar">
        <a class="brand" href="#/dashboard" aria-label="OPC Admin"><span class="brand-icon"><Icon name="layers" size="22px" /></span><strong v-if="!collapsed">OPC</strong><span v-if="!collapsed" class="brand-caption">ADMIN</span></a>
        <div v-if="!collapsed" class="nav-label">{{t('app.business')}}</div>
        <t-menu :value="active" :collapsed="collapsed" :theme="resolvedTheme" class="side-menu">
          <!-- A collapsed TMenuItem renders Tooltip as its root; Vue forwards these attributes to that tooltip. -->
          <t-menu-item v-for="[name,icon] in navItems" :key="name" :value="name" :title="t(`nav.${name}`)" v-bind="collapsed?{popperOptions:scaledPopupProps.popperOptions}:{}" @click="router.push('/'+name)">
            <template #icon><Icon :name="icon" /></template><span class="nav-item-label">{{t(`nav.${name}`)}}</span>
          </t-menu-item>
        </t-menu>
        <div v-if="!collapsed" class="sidebar-foot"><t-tag variant="light">{{t('app.scope')}}</t-tag><p>{{t('app.authorized')}}</p></div>
      </aside>
      <div :class="loggedIn?'app-workspace':'login-workspace'">
        <header class="app-header">
          <t-button v-if="loggedIn" variant="text" shape="square" :aria-label="t('app.collapse')" @click="collapsed=!collapsed"><Icon name="view-list" size="20px" /></t-button>
          <span class="platform-name">{{t('app.name')}}</span>
          <t-tag :theme="connection==='connected'?'success':connection==='checking'?'primary':'danger'" variant="light" class="connection-tag">{{t(`connection.${connection}`)}}</t-tag>
          <t-select v-model="uiScale" :popup-props="scaledPopupProps" class="scale-select" :aria-label="t('app.scale')" :title="t('app.scale')" :options="scaleOptions.map(value=>({label:`${value}%`,value}))">
            <template #prefixIcon><Icon name="zoom-out" /></template>
          </t-select>
          <t-select v-model="locale" :popup-props="scaledPopupProps" class="locale-select" :aria-label="t('app.language')" :options="[{label:'简体中文',value:'zh-CN'},{label:'日本語',value:'ja-JP'}]" />
          <t-select v-model="theme" :popup-props="scaledPopupProps" class="theme-select" :aria-label="t('app.theme')" :options="[{label:t('app.light'),value:'light'},{label:t('app.dark'),value:'dark'},{label:t('app.system'),value:'system'}]">
            <template #prefixIcon><Icon :name="resolvedTheme==='dark'?'moon':'sunny'" /></template>
          </t-select>
          <template v-if="loggedIn">
            <t-badge :count="contextNotifications.length" size="small" theme="primary"><t-button class="notification-trigger" variant="text" shape="square" :aria-label="t('app.notifications')" :title="`${t('app.notifications')} · ${t('notification.pageInfo')} (${contextNotifications.length})`" @click="showNotifications"><Icon name="notification" size="20px" /></t-button></t-badge>
            <button class="profile-control" @click="aboutVisible=true" :aria-label="t('app.help')"><t-avatar size="30px">{{session.account?.display_name.slice(0,1)}}</t-avatar><span>{{session.account?.display_name}}</span></button>
            <t-button variant="text" shape="square" :aria-label="t('auth.logout')" :title="t('auth.logout')" @click="signOut"><Icon name="logout" /></t-button>
          </template>
        </header>
        <main id="main-content" :class="loggedIn?'page-content':'login-content'">
          <PageNotice v-if="connection==='disconnected'" theme="error" :message="connectionError||t('connection.disconnected')"><template #operation><t-button variant="text" @click="connect">{{t('connection.retry')}}</t-button></template></PageNotice>
          <PageNotice v-if="logoutError" theme="warning" :message="logoutError" />
          <template v-if="loggedIn">
            <t-breadcrumb><t-breadcrumb-item :to="{path:'/dashboard'}">{{t('app.workspace')}}</t-breadcrumb-item><t-breadcrumb-item>{{t(`nav.${page}`)}}</t-breadcrumb-item></t-breadcrumb>
            <div class="page-heading"><div><h1>{{t(`nav.${page}`)}}</h1><p>{{t(`subtitle.${page}`)}}</p></div><div class="page-context"><span>{{formatJst(now)}}</span><t-tag theme="primary" variant="light">{{t('app.service')}}</t-tag></div></div>
          </template>
          <div v-if="loggedIn" id="page-notices" class="page-notices" aria-live="polite" />
          <div :class="loggedIn?'page-module':'login-module'"><router-view v-slot="{Component}"><component :is="Component" :key="route.fullPath" /></router-view></div>
          <footer class="page-footer">OPC ADMIN <span>·</span> {{t('app.scope')}}</footer>
        </main>
      </div>
    </div>
    <t-dialog v-model:visible="aboutVisible" :header="t('app.help')" :footer="false"><div class="page-stack"><p>{{t('connection.description')}}</p><t-tag>{{t(isLocal?'connection.local':'connection.remote')}}</t-tag><p v-if="isLocal">{{t('connection.localNote')}}</p><dl class="detail-list"><dt>{{t('connection.endpoint')}}</dt><dd>{{API_BASE_URL}}</dd><dt>{{t('connection.account')}}</dt><dd>{{session.account?.email}}</dd><dt>{{t('connection.roles')}}</dt><dd>{{session.account?.roles.join(', ')}}</dd></dl><t-button :loading="connection==='checking'" @click="connect">{{t('connection.retry')}}</t-button></div></t-dialog>
    <t-drawer v-if="loggedIn" v-model:visible="notificationsVisible" :header="t('app.notifications')" :footer="false" :close-btn="true" size="460px">
      <div class="notification-center">
        <t-tabs v-model="notificationTab" class="notification-tabs">
          <t-tab-panel value="context" :label="`${t('notification.pageInfo')} (${contextNotifications.length})`">
            <div class="page-stack notification-panel">
              <p class="muted">{{t('nav.'+page)}}</p>
              <TransitionGroup name="notice-fade" tag="div" class="context-notification-list" appear @before-leave="contextLeaving++" @after-leave="contextLeaving--" @leave-cancelled="contextLeaving--">
                <div v-for="item in contextNotifications" :key="item.id" class="notice-transition-shell">
                  <div class="notice-transition-content">
                    <article class="context-notification">
                      <Icon name="info-circle" class="context-notification-icon" />
                      <PageNotificationContent :entry="item" />
                      <button type="button" class="notice-close" :aria-label="t('common.close')" @click="item.dismiss"><Icon name="close" /></button>
                    </article>
                  </div>
                </div>
              </TransitionGroup>
              <t-empty v-if="!contextNotifications.length&&!contextLeaving" :description="t('notification.noPageInfo')" />
            </div>
          </t-tab-panel>
          <t-tab-panel value="inbox" :label="t('notification.inbox')">
            <div class="page-stack notification-panel">
              <PageNotice v-if="notificationError" inline theme="error" :message="notificationError" />
              <p class="muted">{{t('notification.latest')}}</p>
              <t-loading v-if="notificationBusy" />
              <t-empty v-if="!notificationBusy&&!notificationError&&!notifications.length" :description="t('notification.empty')"/>
              <t-card v-for="item in notifications" :key="item.id" :title="te('notification.'+item.template_key)?t('notification.'+item.template_key):String(item.parameters.title||t('notification.generic'))"><p>{{formatJst(item.created_at)}}</p><p class="readable">{{item.parameters.body}}</p><t-button v-if="!item.read_at" variant="text" @click="markRead(item)">{{t('notification.read')}}</t-button><t-tag v-else>{{t('notification.readDone')}}</t-tag></t-card>
            </div>
          </t-tab-panel>
        </t-tabs>
      </div>
    </t-drawer>
  </t-config-provider>
</template>
