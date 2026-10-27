<script setup lang="ts">
import { computed,ref } from 'vue';
import { useRoute,useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { ApiError,login } from '../services/api';
import PageNotice from '../components/PageNotice.vue';
const {t,te}=useI18n(),router=useRouter(),route=useRoute();
const email=ref(''),password=ref(''),busy=ref(false),error=ref<unknown>(null);
const validationRun=ref(0);
const errorMessage=computed(()=>error.value instanceof ApiError&&te('auth.error.'+error.value.code)?t('auth.error.'+error.value.code):error.value instanceof Error?error.value.message:String(error.value||''));
async function submit() {
  if(busy.value)return;
  ++validationRun.value;
  error.value=null;
  if(!email.value.trim()||!password.value){error.value=t('auth.required');return;}
  busy.value=true;
  try {
    await login(email.value,password.value);
    password.value='';
    const next=typeof route.query.redirect==='string'?route.query.redirect:'/dashboard';
    await router.replace(next.startsWith('/')&&!next.startsWith('//')&&!next.startsWith('/login')?next:'/dashboard');
  } catch(e) {error.value=e;password.value='';}
  finally {busy.value=false;}
}
</script>
<template>
  <t-card class="login-card" :bordered="false">
    <div class="login-title"><span class="login-brand">OPC <small>ADMIN</small></span><h1>{{t('auth.title')}}</h1><p>{{t('auth.subtitle')}}</p></div>
    <form class="page-stack" @submit.prevent="submit">
      <PageNotice v-if="error" inline theme="error" :message="errorMessage" :reset-key="validationRun" />
      <label class="login-field"><span>{{t('auth.email')}}</span><t-input v-model="email" name="email" type="text" autocomplete="username" :aria-label="t('auth.email')" :disabled="busy" /></label>
      <label class="login-field"><span>{{t('auth.password')}}</span><t-input v-model="password" name="password" type="password" autocomplete="current-password" :aria-label="t('auth.password')" :disabled="busy" /></label>
      <t-button type="submit" theme="primary" block :loading="busy">{{t('auth.login')}}</t-button>
      <p class="muted">{{t('auth.session')}}</p>
    </form>
  </t-card>
</template>
