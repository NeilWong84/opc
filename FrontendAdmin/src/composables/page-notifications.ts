import { defineComponent, h, type InjectionKey, type PropType, type VNodeChild } from 'vue';

export interface PageNotification {
  id: symbol;
  content: () => VNodeChild;
  dismiss: () => void;
}

// Page-scoped explanation entries are not server business notifications and
// never persist private content or read state to browser storage.
export const pageNotificationsKey: InjectionKey<Map<symbol, PageNotification>> = Symbol('page-notifications');
export const PageNotificationContent = defineComponent({
  props: { entry: { type: Object as PropType<PageNotification>, required: true } },
  setup: props => () => h('div', { class: 'readable' }, [props.entry.content()]),
});
