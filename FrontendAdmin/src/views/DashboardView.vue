<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { Icon } from 'tdesign-icons-vue-next';
import { adminRepository, isPublishable, isRequestOpen, requestError } from '../services/requests';
import { formatJst } from '../utils/format';
import StatusTag from '../components/StatusTag.vue';
import PageNotice from '../components/PageNotice.vue';
import ScrollTable from '../components/ScrollTable.vue';
const { t } = useI18n(), router = useRouter(), error = ref('');
const open = computed(() => adminRepository.requests.filter(isRequestOpen));
const metrics = computed(() => [
  { key:'compliance', label:t('dash.compliance'),count:open.value.filter(r => r.compliance==='pending').length,hint:t('dash.reviewHint'),icon:'task-checked',path:'/reviews' },
  { key:'technical', label:t('dash.technical'),count:open.value.filter(r => !r.scope || r.technical==='pending').length,hint:t('dash.techHint'),icon:'task',path:'/technical' },
  { key:'publishing',label:t('dash.publishing'),count:open.value.filter(isPublishable).length,hint:t('dash.publishHint'),icon:'sound',path:'/publishing' },
  { key:'total',label:t('req.total'),count:adminRepository.total,hint:t('req.totalHint'),icon:'folder-open',path:'/reviews' },
]);
const rows = computed(() => open.value.filter(r => r.publication !== 'published').slice(0,10));
const columns = computed(() => [{ colKey:'public_code',title:t('common.id'),width:135 },{ colKey:'title',title:t('dash.subject'),minWidth:190 },{ colKey:'status',title:t('common.status'),width:110 },{ colKey:'updatedAt',title:t('common.updated'),width:115 },{ colKey:'action',title:t('common.action'),width:80 }]);
async function load() { error.value=''; try { await adminRepository.loadPage({pageSize:100}); } catch(e) { error.value=requestError(e); } }
function target(row:typeof rows.value[number]) { return isPublishable(row) ? '/publishing?id='+row.id : !row.scope || row.compliance==='approved' ? '/technical?id='+row.id : '/reviews/'+row.id; }
onMounted(load);
</script>
<template>
  <div class="page-stack module-page dashboard-page">
    <PageNotice notification theme="info" :message="t('dash.scopeHint')" />
    <div class="selection-bar"><p class="muted">{{ t('req.snapshot',{count:adminRepository.requests.length,total:adminRepository.total}) }}</p><t-button variant="outline" :loading="adminRepository.loading" @click="load">{{ t('req.refresh') }}</t-button></div>
    <PageNotice v-if="error" theme="error" :message="error" />
    <div class="dashboard-body module-scroll">
    <div class="metric-grid"><t-card v-for="metric in metrics" :key="metric.key" :bordered="false" class="metric-card" tabindex="0" role="link" @click="router.push(metric.path)" @keydown.enter="router.push(metric.path)"><div class="metric-label"><span>{{ metric.label }}</span><Icon :name="metric.icon" size="18px" /></div><p class="metric-value">{{ adminRepository.loading || error ? '—' : String(metric.count).padStart(2,'0') }}</p><p class="metric-foot">{{ metric.hint }}</p></t-card></div>
    <div class="dashboard-columns">
      <t-card :title="t('dash.priority')" :bordered="false" class="section-card dashboard-table list-card"><ScrollTable row-key="id" :data="rows" :columns="columns" :loading="adminRepository.loading" :empty="t('common.empty')"><template #status="{row}"><StatusTag :value="isPublishable(row)?'ready':row.compliance==='approved'?row.technical:row.compliance" /></template><template #updatedAt="{row}"><span class="subtle">{{ formatJst(row.updatedAt,true) }}</span></template><template #action="{row}"><t-link theme="primary" @click="router.push(target(row))">{{ t('common.view') }}</t-link></template></ScrollTable></t-card>
      <div class="page-stack module-scroll">
        <t-card :title="t('dash.checkTitle')" :bordered="false" class="section-card"><div class="form-stack"><div class="check-row"><span>{{ t('review.compliance') }}</span><t-tag theme="success" variant="light">{{ t('dash.manual') }}</t-tag></div><div class="check-row"><span>{{ t('review.technical') }}</span><t-tag theme="primary" variant="light">{{ t('dash.acceptable') }}</t-tag></div><p class="muted">{{ t('dash.rule') }}</p><t-button block variant="outline" @click="router.push('/publishing')">{{ t('dash.openQueue') }}</t-button></div></t-card>
        <t-card :title="t('nav.audit')" :bordered="false" class="section-card"><div class="form-stack"><p class="muted">{{ t('subtitle.audit') }}</p><t-button block variant="outline" @click="router.push('/audit')">{{ t('common.view') }}</t-button></div></t-card>
      </div>
    </div>
    </div>
  </div>
</template>

