import { computed, ref, watch } from 'vue';

export type Locale = 'zh-CN' | 'ja-JP';
export type Theme = 'light' | 'dark' | 'system';
export const scaleOptions = [75, 80, 85, 90, 100] as const;
export type UiScale = typeof scaleOptions[number];
function read(key: string) { try { return localStorage.getItem(key); } catch { return null; } }
function save(key: string, value: string) { try { localStorage.setItem(key, value); } catch { /* Preference persistence is optional. */ } }
const savedLocale = read('opc.admin.locale');
const savedTheme = read('opc.admin.theme');
const savedScale = Number(read('opc.admin.scale'));
export const locale = ref<Locale>(savedLocale === 'ja-JP' ? 'ja-JP' : 'zh-CN');
export const theme = ref<Theme>(savedTheme === 'dark' || savedTheme === 'system' ? savedTheme : 'light');
export const uiScale = ref<UiScale>(scaleOptions.includes(savedScale as UiScale) ? savedScale as UiScale : 80);
const systemDark = ref(false);
export const resolvedTheme = computed(() => theme.value === 'system' ? (systemDark.value ? 'dark' : 'light') : theme.value);
export function initializePreferences() {
  watch(uiScale, value => {
    const scale = String(value / 100);
    document.documentElement.style.setProperty('--opc-ui-scale', scale);
    document.documentElement.dataset.adminScale = scale;
    save('opc.admin.scale', String(value));
  }, { immediate: true });
  const media = window.matchMedia('(prefers-color-scheme: dark)');
  systemDark.value = media.matches;
  media.addEventListener('change', event => { systemDark.value = event.matches; });
  watch(resolvedTheme, value => {
    if (value === 'dark') document.documentElement.setAttribute('theme-mode', 'dark');
    else document.documentElement.removeAttribute('theme-mode');
    document.documentElement.style.colorScheme = value;
  }, { immediate: true });
  watch(theme, value => save('opc.admin.theme', value));
  watch(locale, value => {
    save('opc.admin.locale', value);
    document.documentElement.lang = value;
  }, { immediate: true });
}
