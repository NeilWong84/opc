<script setup lang="ts">
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
const props=defineProps<{value:string}>();
const {t}=useI18n();
const color=computed(()=>props.value==='approved'||props.value==='published'?'success':props.value==='rejected'?'danger':props.value==='pending'||props.value==='needs_info'?'warning':props.value==='ready'||props.value==='draft'?'primary':'default');
</script>
<template><t-tag :theme="color" variant="light">{{t(`status.${value}`)}}</t-tag></template>
