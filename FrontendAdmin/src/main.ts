import { createApp } from 'vue';
import TDesign from 'tdesign-vue-next';
import 'tdesign-vue-next/es/style/index.css';
import './styles.css';
import App from './App.vue';
import { router } from './router';
import { i18n } from './locales';
import { initializePreferences } from './composables/preferences';
import { initializeScaledPopups } from './utils/scaled-popup';

initializePreferences();
initializeScaledPopups();
createApp(App).use(TDesign).use(i18n).use(router).mount('#app');
