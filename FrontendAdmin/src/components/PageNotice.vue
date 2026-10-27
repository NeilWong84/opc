<script setup lang="ts">
import { computed, inject, onUnmounted, ref, useSlots, watch, watchEffect, type Ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { Icon } from 'tdesign-icons-vue-next';
import { pageNotificationsKey } from '../composables/page-notifications';

defineOptions({ inheritAttrs: false });
const props = withDefaults(defineProps<{
  message?: string;
  theme?: 'info' | 'success' | 'warning' | 'error';
  inline?: boolean;
  resetKey?: unknown;
  notification?: boolean;
}>(), { theme: 'info', inline: false });
const emit = defineEmits<{ close: [] }>();
const target = inject<Ref<string | null>>('page-notice-target', ref(null));
const destination = computed(() => props.inline ? null : target.value);
const dismissed = ref(false);
const closeRequested = ref(false);
const notifications = inject(pageNotificationsKey, null);
const slots = useSlots();
const notificationId = Symbol('page-notice');
const inNotificationCenter = computed(() => Boolean(props.notification && !props.inline && notifications));
const { t } = useI18n();
watch(() => [props.message, props.theme, props.resetKey], () => { closeRequested.value = false; dismissed.value = false; });
function close() {
  if (dismissed.value) return;
  closeRequested.value = true;
  dismissed.value = true;
  if (inNotificationCenter.value) completeClose();
}
function completeClose() {
  if (closeRequested.value && dismissed.value) { closeRequested.value = false; emit('close'); }
}
const entry = { id: notificationId, content: () => slots.message?.() || slots.default?.() || props.message, dismiss: close };
watchEffect(() => {
  if (inNotificationCenter.value && !dismissed.value) notifications?.set(notificationId, entry);
  else notifications?.delete(notificationId);
});
onUnmounted(() => notifications?.delete(notificationId));
</script>
<template>
  <Teleport v-if="!inNotificationCenter" :to="destination || 'body'" :disabled="!destination" defer>
    <Transition name="notice-fade" appear @after-leave="completeClose">
      <div v-if="!dismissed" class="notice-transition-shell" :data-theme="theme">
        <div class="notice-transition-content">
          <t-alert v-bind="$attrs" class="page-notice" :theme="theme" :message="message" @close="close">
            <template v-for="(_,name) in $slots" #[name]="scope"><slot :name="name" v-bind="scope || {}" /></template>
            <!-- Own dismissal so TDesign's internal transition cannot hide the alert before the wrapper collapses. -->
            <template #closeBtn><button type="button" class="notice-close" :aria-label="t('common.close')" @click.stop="close"><Icon name="close" /></button></template>
          </t-alert>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
