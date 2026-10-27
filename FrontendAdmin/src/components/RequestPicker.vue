<script setup lang="ts">
import { scaledPopupProps } from '../utils/scaled-popup';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { createAdminRepository, requestError } from '../services/requests';
import PageNotice from './PageNotice.vue';
const props = defineProps<{ modelValue: string }>();
const emit = defineEmits<{ 'update:modelValue': [value: string] }>();
const { t } = useI18n(), repository = createAdminRepository(), query = ref(''), current = ref(1), error = ref('');
const options = computed(() => {
  const items = repository.requests.map(item => ({ value: item.id, label: item.public_code + ' · ' + item.title }));
  if (props.modelValue && !items.some(item => item.value === props.modelValue)) items.unshift({ value: props.modelValue, label: props.modelValue });
  return items;
});
async function load(search = false) {
  if (search) current.value = 1;
  error.value = '';
  try { await repository.loadPage({ page: current.value, pageSize: 20, q: query.value.trim() }); if (!props.modelValue && repository.requests[0]) emit('update:modelValue', repository.requests[0].id); }
  catch (e) { error.value = requestError(e); }
}
onMounted(() => load());
</script>
<template>
  <t-card :bordered="false" class="section-card">
    <PageNotice v-if="error" theme="error" :message="error" />
    <form class="selection-bar" @submit.prevent="load(true)">
      <label>{{ t('req.select') }}</label>
      <t-select :popup-props="scaledPopupProps" :value="modelValue" :options="options" :loading="repository.loading" :aria-label="t('req.select')" @change="value => emit('update:modelValue', String(value))" />
      <t-input v-model="query" :placeholder="t('req.search')" style="max-width:280px" clearable />
      <t-button type="submit" variant="outline" :loading="repository.loading">{{ t('common.search') }}</t-button>
    </form>
    <t-pagination v-if="repository.total > 20" v-model="current" :page-size="20" :total="repository.total" :show-page-size="false" size="small" @current-change="load()" />
    <p v-if="!error && !repository.loading && !repository.total" class="subtle">{{ t('common.empty') }}</p>
  </t-card>
</template>
