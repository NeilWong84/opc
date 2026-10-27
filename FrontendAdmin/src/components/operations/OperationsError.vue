<script setup lang="ts">
import { computed } from 'vue'; import { useI18n } from 'vue-i18n';
import PageNotice from '../PageNotice.vue';
const props=defineProps<{error:unknown;inline?:boolean}>(); const {t,te}=useI18n();
const value=computed(()=>props.error as {code?:string;requestId?:string;status?:number}|null);
const message=computed(()=>value.value?.status===403?t('ops.api.forbidden'):value.value?.code&&te(`ops.api.errors.${value.value.code}`)?t(`ops.api.errors.${value.value.code}`):t('ops.api.error'));
</script>
<template><PageNotice v-if="error" :inline="inline" theme="error" :message="message" :reset-key="error"><template #operation><span v-if="value?.requestId">{{t('ops.api.requestId')}}: {{value.requestId}}</span></template></PageNotice></template>
