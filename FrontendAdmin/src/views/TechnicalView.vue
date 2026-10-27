<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { adminRepository, hasReview, isRequestOpen, requestError, scopeDraft, type RequestRecord, type ScopeRecord, type TechnicalDraft } from '../services/requests';
import { formatJst } from '../utils/format';
import RequestPicker from '../components/RequestPicker.vue';
import RequestFiles from '../components/RequestFiles.vue';
import StatusTag from '../components/StatusTag.vue';
import PageNotice from '../components/PageNotice.vue';
const {t}=useI18n(),route=useRoute(),router=useRouter();
const id=computed(()=>typeof route.query.id==='string'?route.query.id:'');
const request=ref<RequestRecord|null>(null),history=ref<ScopeRecord[]>([]),loading=ref(false),busy=ref(false),error=ref('');
const success=ref(false);
const validationRun=ref(0);
const draft=ref<TechnicalDraft>(scopeDraft(null)),reason=ref(''),question=ref(''),tab=ref('scope');
const confirmVisible=ref(false),mode=ref<'scope'|'review'|'question'>('scope');
type TextKey=Exclude<keyof TechnicalDraft,'file_ids'>;
const fields:{key:TextKey;label:string;max:number}[]=[
  {key:'title',label:'tech.publicTitle',max:500},{key:'public_summary',label:'tech.publicSummary',max:10000},
  {key:'category',label:'req.category',max:500},{key:'goal',label:'tech.goal',max:10000},
  {key:'included_scope',label:'tech.scope',max:10000},{key:'excluded_scope',label:'tech.exclusions',max:10000},
  {key:'deliverables',label:'req.deliverables',max:25000},{key:'acceptance_criteria',label:'req.acceptance',max:25000},
  {key:'duration_text',label:'req.duration',max:500},{key:'revision_terms',label:'req.revisionTerms',max:10000},
];
const pending=computed(()=>request.value?.clarifications.some(item=>item.answer===null)??false);
const open=computed(()=>request.value?isRequestOpen(request.value):false);
const dirty=computed(()=>request.value&&JSON.stringify(draft.value)!==JSON.stringify(scopeDraft(request.value.scope)));
const references=computed(()=>[...new Map([...(request.value?.private_files??[]),...(request.value?.scope?.reference_files??[])].map(file=>[file.file_id,file])).values()]);
async function load() {
  error.value='';success.value=false;request.value=null;history.value=[];
  if(!id.value)return;
  loading.value=true;
  try { const [record,scopes]=await Promise.all([adminRepository.load(id.value),adminRepository.scopes(id.value)]);request.value=record;history.value=scopes;draft.value=scopeDraft(record.scope);reason.value='';question.value=''; }
  catch(e) { error.value=requestError(e); } finally { loading.value=false; }
}
watch(id,load,{immediate:true});
function select(value:string) { router.replace({path:'/technical',query:{id:value}}); }
function prepare(value:typeof mode.value) {
  ++validationRun.value;
  error.value='';success.value=false;
  if(value==='scope'&&fields.some(field=>!draft.value[field.key].trim())) { error.value=t('req.scopeRequired');return; }
  if(value==='review'&&dirty.value) { error.value=t('tech.unsaved');return; }
  if(value==='review'&&!reason.value.trim()||value==='question'&&!question.value.trim()) { error.value=t('error.reasonRequired');return; }
  mode.value=value;confirmVisible.value=true;
}
async function commit() {
  if(!request.value||busy.value)return;
  busy.value=true;error.value='';success.value=false;
  try {
    if(mode.value==='scope') {
      request.value=await adminRepository.createScope(request.value.id,request.value.revision,draft.value);
      draft.value=scopeDraft(request.value.scope);
      if(request.value.scope)history.value.unshift(request.value.scope);
      success.value=true;
    } else if(mode.value==='review'&&request.value.current_scope_version) {
      request.value=await adminRepository.review(request.value.id,request.value.revision,request.value.current_scope_version,'technical','approved',reason.value.trim());reason.value='';
      success.value=true;
    } else if(mode.value==='question') {
      request.value=await adminRepository.clarify(request.value.id,request.value.revision,question.value.trim());question.value='';
      success.value=true;
    }
    confirmVisible.value=false;
  } catch(e) { error.value=requestError(e);confirmVisible.value=false; } finally { busy.value=false; }
}
</script>
<template>
  <div class="page-stack module-page">
    <RequestPicker :model-value="id" @update:model-value="select" />
    <div v-if="id" class="selection-bar"><t-button variant="outline" :loading="loading" :disabled="busy" @click="load">{{t('req.refresh')}}</t-button><t-link @click="router.push('/reviews/'+id)">{{t('nav.compliance')}}</t-link><t-link @click="router.push('/publishing?id='+id)">{{t('nav.publishing')}}</t-link></div>
    <PageNotice v-if="success" theme="success" :message="t('req.saved')" />
    <PageNotice v-if="error" theme="error" :message="error" :reset-key="validationRun" />
    <t-loading v-if="loading" :text="t('common.loading')" />
    <template v-else-if="request">
      <PageNotice v-if="!open" theme="warning" :message="t('req.closed')" />
      <PageNotice v-else-if="pending" theme="warning" :message="t('req.pendingQuestions')" />
      <PageNotice v-if="tab==='scope'" notification theme="info" :message="t('req.scopeConfirm')" />
      <PageNotice v-if="!request.scope" theme="info" :message="t('req.emptyScope')" />
      <PageNotice v-else-if="hasReview(request,'technical')" notification theme="info" :message="t('req.existingReview')" />
      <div class="module-scroll">
      <div class="two-column">
        <t-card :title="t('tech.draft')" :bordered="false" class="section-card">
          <t-tabs v-model="tab"><t-tab-panel value="scope" :label="t('tech.scopeTab')"/><t-tab-panel value="history" :label="t('tech.historyTab')"/></t-tabs>
          <div v-if="tab==='scope'" class="form-stack">
            <p class="subtle">{{request.public_code}} · {{t('req.originalVersion')}} v{{request.current_request_version}} · {{t('req.scopeVersion')}} {{request.version}}</p>
            <div v-for="field in fields" :key="field.key"><label :for="'scope-'+field.key">{{t(field.label)}}</label><t-textarea :id="'scope-'+field.key" v-model="draft[field.key]" :disabled="busy||!open" :maxlength="field.max" :autosize="{minRows:field.key==='title'||field.key==='category'||field.key==='duration_text'?1:3,maxRows:8}" /></div>
            <div><label>{{t('req.references')}}</label><p class="subtle">{{t('req.referenceHint')}}</p><t-checkbox-group v-model="draft.file_ids"><div v-for="file in references" :key="file.file_id" class="check-row"><t-checkbox :value="file.file_id" :disabled="busy||!open||file.scan_status!=='clean'||file.upload_status!=='ready'">{{file.original_name}} · {{t('req.scan.'+file.scan_status)}}</t-checkbox></div></t-checkbox-group><p v-if="!references.length" class="subtle">{{t('common.noFiles')}}</p></div>
            <t-button :disabled="busy||!open||pending" @click="prepare('scope')">{{t('req.createScope')}}</t-button>
          </div>
          <div v-else class="form-stack"><p v-if="!history.length" class="subtle">{{t('common.empty')}}</p><div v-for="scope in history" :key="scope.version" class="timeline-item"><p class="subtle">v{{scope.version}} · {{t('req.originalVersion')}} v{{scope.request_version}} · {{formatJst(scope.authored_at)}}</p><h3>{{scope.title}}</h3><p class="readable">{{scope.included_scope}}</p><p class="readable">{{scope.acceptance_criteria.join('\n')}}</p></div></div>
        </t-card>
        <div class="page-stack">
          <t-card :title="t('tech.context')" :bordered="false" class="section-card"><div class="form-stack"><p class="readable">{{request.originalText}}</p><dl class="detail-list"><dt>{{t('req.intakeLabel')}}</dt><dd>{{t('req.intake.'+request.intake_status)}}</dd><dt>{{t('req.duration')}}</dt><dd>{{request.original.timing_text}}</dd><dt>{{t('publish.budget')}}</dt><dd>{{request.original.budget_text}}</dd></dl><RequestFiles :files="request.private_files" /></div></t-card>
          <t-card :title="t('tech.approve')" :bordered="false" class="section-card"><div class="form-stack"><StatusTag :value="request.technical" /><template v-if="request.scope&&!hasReview(request,'technical')"><label for="technical-reason">{{t('req.reviewReason')}}</label><t-textarea id="technical-reason" v-model="reason" :maxlength="4000" :disabled="busy||!open" /><t-button :disabled="busy||!open||dirty||pending" @click="prepare('review')">{{t('tech.approve')}}</t-button></template><p class="subtle">{{t('req.noAI')}}</p></div></t-card>
          <t-card :title="t('req.sentQuestions')" :bordered="false" class="section-card"><div class="form-stack"><div v-for="item in request.clarifications" :key="item.id" class="timeline-item"><p class="subtle">{{formatJst(item.asked_at)}} · v{{item.request_version}}</p><p class="readable">{{item.question}}</p><p class="readable">{{item.answer??t('req.awaitingAnswer')}}</p></div><p v-if="!request.clarifications.length" class="subtle">{{t('common.empty')}}</p><template v-if="open"><label for="technical-question">{{t('compliance.question')}}</label><t-textarea id="technical-question" v-model="question" :maxlength="4000" :disabled="busy" /><p class="subtle">{{t('req.questionHint')}}</p><t-button variant="outline" :disabled="busy" @click="prepare('question')">{{t('req.sendQuestion')}}</t-button></template></div></t-card>
        </div>
      </div>
      </div>
      <t-dialog v-model:visible="confirmVisible" :header="t(mode==='scope'?'req.createScope':mode==='review'?'tech.approve':'req.sendQuestion')" :confirm-btn="{content:t('common.confirm'),loading:busy}" :cancel-btn="{content:t('common.cancel'),disabled:busy}" :close-btn="!busy" :close-on-overlay-click="false" @confirm="commit"><div class="form-stack"><PageNotice inline theme="info" :message="t(mode==='scope'?'req.scopeConfirm':mode==='question'?'req.questionHint':'req.checkCurrent')" /><p><strong>{{request.public_code}} · {{request.version}}</strong></p><p class="readable">{{mode==='scope'?draft.title:mode==='review'?reason:question}}</p></div></t-dialog>
    </template>
  </div>
</template>

