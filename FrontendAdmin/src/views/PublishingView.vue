<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { Icon } from 'tdesign-icons-vue-next';
import { adminRepository, isPublishable, requestError, type RequestRecord } from '../services/requests';
import { formatJst } from '../utils/format';
import RequestPicker from '../components/RequestPicker.vue';
import StatusTag from '../components/StatusTag.vue';
import PageNotice from '../components/PageNotice.vue';
const {t}=useI18n(),route=useRoute(),router=useRouter(),id=computed(()=>typeof route.query.id==='string'?route.query.id:'');
const request=ref<RequestRecord|null>(null),loading=ref(false),busy=ref(false),error=ref(''),reason=ref('');
const success=ref(false);
const dialogVisible=ref(false),unpublishing=ref(false);
const validationRun=ref(0);
const eligible=computed(()=>request.value?isPublishable(request.value):false);
const activePublication=computed(()=>request.value?.publications.some(item=>!item.withdrawn_at)??false);
async function load(){error.value='';success.value=false;request.value=null;if(!id.value)return;loading.value=true;try{request.value=await adminRepository.load(id.value);}catch(e){error.value=requestError(e);}finally{loading.value=false;}}
watch(id,load,{immediate:true});
function select(value:string){router.replace({path:'/publishing',query:{id:value}});}
function prepare(withdraw=false){unpublishing.value=withdraw;reason.value='';error.value='';success.value=false;dialogVisible.value=true;}
async function confirm(){
  ++validationRun.value;
  if(!request.value||busy.value)return;
  success.value=false;
  if(!reason.value.trim()){error.value=t('error.reasonRequired');return;}
  busy.value=true;error.value='';
  try{
    request.value=unpublishing.value?await adminRepository.unpublish(request.value.id,request.value.revision,reason.value.trim()):await adminRepository.publish(request.value.id,request.value.revision,request.value.current_scope_version!,reason.value.trim());
    dialogVisible.value=false;success.value=true;
  }catch(e){error.value=requestError(e);}finally{busy.value=false;}
}
</script>
<template>
  <div class="page-stack module-page">
    <RequestPicker :model-value="id" @update:model-value="select" />
    <div v-if="id" class="selection-bar"><t-button variant="outline" :loading="loading" :disabled="busy" @click="load">{{t('req.refresh')}}</t-button><t-link @click="router.push('/reviews')">{{t('common.back')}}</t-link></div>
    <PageNotice v-if="success" theme="success" :message="t('req.saved')" />
    <PageNotice v-if="error&&!dialogVisible" theme="error" :message="error" />
    <t-loading v-if="loading" :text="t('common.loading')" />
    <template v-else-if="request">
      <PageNotice notification theme="info" :message="t('publish.boundary')" />
      <PageNotice v-if="!eligible&&!activePublication" theme="warning" :message="t('publish.invalid')" />
      <PageNotice v-if="activePublication" theme="success" :message="t('req.publishDone')" />
      <div class="module-scroll page-stack">
      <div class="two-column equal">
        <t-card :title="t('publish.check')" :bordered="false" class="section-card"><div class="form-stack"><h2 class="record-title">{{request.title}}</h2><dl class="detail-list"><dt>{{t('common.id')}}</dt><dd>{{request.public_code}}</dd><dt>{{t('req.scopeVersion')}}</dt><dd>{{request.version}}</dd><dt>{{t('review.compliance')}}</dt><dd><StatusTag :value="request.compliance" /> {{request.complianceVersion||t('publish.none')}}</dd><dt>{{t('review.technical')}}</dt><dd><StatusTag :value="request.technical" /> {{request.technicalVersion||t('publish.none')}}</dd><dt>{{t('common.status')}}</dt><dd><StatusTag :value="request.publication" /></dd></dl><p class="subtle">{{t('publish.locked')}}</p><t-space><t-link theme="primary" @click="router.push('/technical?id='+request.id)">{{t('nav.technical')}}</t-link><t-link theme="primary" @click="router.push('/reviews/'+request.id)">{{t('nav.compliance')}}</t-link></t-space></div></t-card>
        <t-card :title="t('publish.preview')" :bordered="false" class="section-card"><div class="form-stack"><p class="muted"><Icon name="mobile" /> {{t('publish.app')}}</p><div v-if="request.scope" class="mobile-preview form-stack"><t-tag theme="primary" variant="light">{{request.scope.category}}</t-tag><h2>{{request.scope.title}}</h2><p class="subtle">{{request.public_code}} · {{request.version}}</p><p class="readable">{{request.scope.public_summary}}</p><hr class="section-divider" /><dl class="detail-list"><dt>{{t('req.duration')}}</dt><dd>{{request.scope.duration_text}}</dd><dt>{{t('tech.scope')}}</dt><dd class="readable">{{request.scope.included_scope}}</dd><dt>{{t('req.publicReferences')}}</dt><dd><p v-for="file in request.scope.reference_files" :key="file.file_id">{{file.original_name}}</p><span v-if="!request.scope.reference_files.length">{{t('common.noFiles')}}</span></dd></dl></div><t-empty v-else :description="t('req.emptyScope')" /><p class="subtle">{{t('req.noBudget')}}</p></div></t-card>
      </div>
      <t-card :title="t('req.publicationHistory')" :bordered="false" class="section-card"><div class="form-stack"><p v-if="!request.publications.length" class="subtle">{{t('common.empty')}}</p><div v-for="item in request.publications" :key="item.id" class="timeline-item"><p>v{{item.scope_version}} · {{t('req.publishedAt')}} {{formatJst(item.published_at)}}</p><p v-if="item.withdrawn_at" class="subtle">{{t('req.unpublishedAt')}} {{formatJst(item.withdrawn_at)}} · {{item.withdrawal_reason}}</p><StatusTag v-else value="published" /></div></div></t-card>
      </div>
      <div class="action-bar"><span class="muted">{{t('req.checkCurrent')}}</span><t-button v-if="activePublication" theme="warning" :disabled="busy" @click="prepare(true)">{{t('publish.unpublish')}}</t-button><t-button v-else :disabled="!eligible||busy" @click="prepare()">{{t('publish.publish',{version:request.version})}}</t-button></div>
      <t-dialog v-model:visible="dialogVisible" :header="t(unpublishing?'publish.confirmUnpublish':'publish.confirm')" :confirm-btn="{content:t('common.confirm'),loading:busy}" :cancel-btn="{content:t('common.cancel'),disabled:busy}" :close-btn="!busy" :close-on-overlay-click="false" @confirm="confirm"><div class="form-stack"><PageNotice inline theme="info" :message="t(unpublishing?'req.checkCurrent':'req.publishConfirm')" /><PageNotice v-if="error" inline theme="error" :message="error" :reset-key="validationRun" /><p><strong>{{request.public_code}} · {{request.version}}</strong></p><p>{{request.title}}</p><div><label for="publish-reason">{{t('common.reason')}}</label><t-textarea id="publish-reason" v-model="reason" :disabled="busy" :maxlength="4000" /></div></div></t-dialog>
    </template>
  </div>
</template>

