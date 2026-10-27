<script setup lang="ts">
import PageNotice from '../components/PageNotice.vue';
import {useI18n} from 'vue-i18n';import {useRouter} from 'vue-router';const {t}=useI18n(),router=useRouter();
</script>
<template><div class="page-stack module-page"><PageNotice theme="info" :message="t('ops.api.ticketsHint')"/><t-card :bordered="false" class="section-card module-scroll"><t-empty :description="t('ops.api.ticketsUnavailable')"><t-button theme="primary" @click="router.push('/projects')">{{t('ops.project.progress')}}</t-button></t-empty></t-card></div></template>
