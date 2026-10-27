<script setup lang="ts">import {useI18n} from 'vue-i18n'; const {t}=useI18n();</script>
<template><t-card class="empty-state"><t-empty :description="t('nav.notFound')"/><t-button @click="$router.push('/dashboard')">{{t('nav.dashboard')}}</t-button></t-card></template>
