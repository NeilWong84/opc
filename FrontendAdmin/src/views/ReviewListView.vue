<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { adminRepository, isPublishable, requestError, type RequestRecord } from '../services/requests';
import { formatJst } from '../utils/format';
import { scaledPopupProps } from '../utils/scaled-popup';
import StatusTag from '../components/StatusTag.vue';
import PageNotice from '../components/PageNotice.vue';
import ScrollTable from '../components/ScrollTable.vue';
const { t } = useI18n(), router = useRouter();
const keyword = ref(''), status = ref(''), current = ref(1), pageSize = ref(20), error = ref('');
const selected = ref<RequestRecord | null>(null), drawerVisible = ref(false);
const filters = ref({ q: '', status: '' });
const columns = computed(() => [
  { colKey: 'public_code', title: t('common.id'), width: 135 }, { colKey: 'title', title: t('review.original'), minWidth: 220 },
  { colKey: 'intake_status', title: t('req.intakeLabel'), width: 120 }, { colKey: 'compliance', title: t('review.compliance'), width: 110 },
  { colKey: 'technical', title: t('review.technical'), width: 110 }, { colKey: 'publication', title: t('review.publication'), width: 100 },
  { colKey: 'updatedAt', title: t('common.updated'), width: 120 }, { colKey: 'action', title: t('common.action'), width: 150 },
]);
const options = computed(() => [{ value: '', label: t('common.all') }, ...['submitted','needs_info','in_review','withdrawn','closed'].map(value => ({ value, label: t('req.intake.' + value) }))]);
async function load() {
  error.value = '';
  try { await adminRepository.loadPage({ page: current.value, pageSize: pageSize.value, ...filters.value }); }
  catch (e) { error.value = requestError(e); }
}
function search() { filters.value = { q: keyword.value.trim(), status: status.value }; current.value = 1; void load(); }
function reset() { keyword.value = ''; status.value = ''; search(); }
function openRequest(row: RequestRecord) { router.push(isPublishable(row) || row.publication === 'published' ? '/publishing?id=' + row.id : !row.scope ? '/technical?id=' + row.id : '/reviews/' + row.id); }
onMounted(load);
</script>
<template>
  <div class="page-stack module-page">
    <PageNotice notification theme="info" :message="t('review.boundary')" />
    <PageNotice v-if="error" theme="error" :message="error"><template #operation><t-link @click="load">{{ t('req.reload') }}</t-link></template></PageNotice>
    <t-card :bordered="false" class="section-card list-card">
      <form class="table-toolbar" @submit.prevent="search">
        <div class="filter-field keyword-field"><label for="review-keyword">{{ t('review.keyword') }}</label><t-input id="review-keyword" v-model="keyword" :placeholder="t('req.search')" clearable /></div>
        <div class="filter-field"><label>{{ t('req.intakeLabel') }}</label><t-select v-model="status" :popup-props="scaledPopupProps" :aria-label="t('req.intakeLabel')" :options="options" /></div>
        <t-space><t-button type="submit" :loading="adminRepository.loading">{{ t('common.search') }}</t-button><t-button variant="outline" @click="reset">{{ t('common.reset') }}</t-button></t-space>
      </form>
      <ScrollTable row-key="id" :data="adminRepository.requests" :columns="columns" :loading="adminRepository.loading" :empty="t('common.empty')" :pagination="{current,pageSize,total:adminRepository.total,pageSizeOptions:[10,20,50],selectProps:{popupProps:scaledPopupProps}}" :disable-data-page="true" @page-change="(info:any) => { current=info.current; pageSize=info.pageSize; load(); }">
        <template #title="{row}"><div class="table-primary">{{ row.title }}</div><div class="table-secondary">{{ t('req.originalVersion') }} v{{ row.current_request_version }} · {{ t('req.scopeVersion') }} {{ row.version }}</div></template>
        <template #intake_status="{row}">{{ t('req.intake.' + row.intake_status) }}</template>
        <template #compliance="{row}"><StatusTag :value="row.compliance" /></template><template #technical="{row}"><StatusTag :value="row.technical" /></template><template #publication="{row}"><StatusTag :value="row.publication" /></template>
        <template #updatedAt="{row}"><span class="subtle">{{ formatJst(row.updatedAt,true) }}</span></template>
        <template #action="{row}"><t-space size="small" class="table-actions"><t-link theme="primary" @click="openRequest(row)">{{ t('review.open') }}</t-link><t-link @click="selected=row;drawerVisible=true">{{ t('common.view') }}</t-link></t-space></template>
      </ScrollTable>
    </t-card>
    <t-drawer v-model:visible="drawerVisible" :header="t('review.summary')" :footer="false" :close-btn="true" size="480px">
      <div v-if="selected" class="page-stack"><t-tag>{{ selected.public_code }} · {{ selected.version }}</t-tag><h2 class="record-title">{{ selected.title }}</h2><p class="readable">{{ selected.originalText }}</p><dl class="detail-list"><dt>{{ t('common.customer') }}</dt><dd class="mono">{{ selected.customer }}</dd><dt>{{ t('review.compliance') }}</dt><dd><StatusTag :value="selected.compliance" /></dd><dt>{{ t('review.technical') }}</dt><dd><StatusTag :value="selected.technical" /></dd></dl><t-button @click="router.push('/reviews/'+selected.id)">{{ t('nav.compliance') }}</t-button></div>
    </t-drawer>
  </div>
</template>

