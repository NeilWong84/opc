<script setup lang="ts">
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { downloadFile } from '../services/api';
import { requestError, type RequestFile } from '../services/requests';
import PageNotice from './PageNotice.vue';
defineProps<{ files: RequestFile[] }>();
const { t } = useI18n(), downloading = ref(''), error = ref('');
async function download(file: RequestFile) {
  downloading.value = file.file_id; error.value = '';
  try { await downloadFile('/api/v1/admin/files/' + file.file_id + '/download', file.original_name); }
  catch (e) { error.value = requestError(e); } finally { downloading.value = ''; }
}
</script>
<template>
  <div class="form-stack">
    <PageNotice v-if="error" theme="error" :message="error" />
    <p v-if="!files.length" class="subtle">{{ t('common.noFiles') }}</p>
    <div v-for="file in files" :key="file.file_id" class="file-row">
      <span>{{ file.original_name }}<small class="subtle"> · {{ file.size_bytes }} B</small></span>
      <t-tag :theme="file.scan_status === 'clean' ? 'success' : 'warning'" variant="light">{{ t('req.scan.' + file.scan_status) }}</t-tag>
      <t-button size="small" variant="text" :loading="downloading === file.file_id" :disabled="!!downloading || file.scan_status !== 'clean' || file.upload_status !== 'ready'" @click="download(file)">{{ t('req.download') }}</t-button>
    </div>
    <p v-if="files.some(file => file.scan_status !== 'clean' || file.upload_status !== 'ready')" class="subtle">{{ t('req.downloadBlocked') }}</p>
  </div>
</template>
