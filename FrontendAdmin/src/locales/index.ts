import { createI18n } from 'vue-i18n';
import { locale } from '../composables/preferences';
import { coreZh,coreJa } from './core';
import { operationsZh,operationsJa } from './operations';
import { sessionZh,sessionJa } from './session';
import { requestApiZh,requestApiJa } from './requests-api';

export const i18n=createI18n({
  legacy:false, locale:locale.value, fallbackLocale:'zh-CN', flatJson:true,
  messages:{'zh-CN':{...coreZh,...sessionZh,...requestApiZh,ops:operationsZh},'ja-JP':{...coreJa,...sessionJa,...requestApiJa,ops:operationsJa}},
});
