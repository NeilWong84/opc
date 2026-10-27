<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { adminRepository, hasReview, isRequestOpen, requestError, type RequestRecord, type ReviewRecord } from '../services/requests';
import { formatJst } from '../utils/format';
import RequestFiles from '../components/RequestFiles.vue';
import StatusTag from '../components/StatusTag.vue';
import PageNotice from '../components/PageNotice.vue';
const { t }=useI18n(), route=useRoute(), router=useRouter();
const request=ref<RequestRecord|null>(null), loading=ref(false), busy=ref(false), error=ref('');
const success=ref(false);
const validationRun=ref(0);
const checks=ref([false,false,false,false]),note=ref(''),question=ref(''),confirmVisible=ref(false);
const decision=ref<ReviewRecord['decision']>('approved');
const remaining=computed(()=>checks.value.filter(value=>!value).length);
const eligible=computed(()=>!!request.value?.scope && isRequestOpen(request.value) && !hasReview(request.value,'compliance'));
async function load() { loading.value=true;error.value='';success.value=false;request.value=null;try { request.value=await adminRepository.load(String(route.params.id));checks.value=[false,false,false,false];note.value='';question.value=''; } catch(e) { error.value=requestError(e); } finally { loading.value=false; } }
watch(()=>route.params.id,load,{immediate:true});
function prepare(value:ReviewRecord['decision']) {
  ++validationRun.value;
  error.value='';success.value=false;
  if(!note.value.trim() || value==='needs_info'&&!question.value.trim()) { error.value=t('error.reasonRequired');return; }
  if(value==='approved'&&remaining.value) { error.value=t('error.checksRequired');return; }
  decision.value=value;confirmVisible.value=true;
}
async function commit() {
  if(!request.value?.current_scope_version||busy.value)return;
  busy.value=true;error.value='';success.value=false;
  try { request.value=await adminRepository.review(request.value.id,request.value.revision,request.value.current_scope_version,'compliance',decision.value,note.value.trim(),question.value.trim());confirmVisible.value=false;success.value=true; }
  catch(e) { error.value=requestError(e);confirmVisible.value=false; } finally { busy.value=false; }
}
</script>
<template>
  <div class="page-stack module-page">
    <div class="selection-bar"><t-button variant="outline" :loading="loading" :disabled="busy" @click="load">{{t('req.refresh')}}</t-button><t-button variant="text" @click="router.push('/reviews')">{{t('common.back')}}</t-button></div>
    <PageNotice v-if="success" theme="success" :message="t('req.saved')" />
    <PageNotice v-if="error" theme="error" :message="error" :reset-key="validationRun" />
    <t-loading v-if="loading" :text="t('common.loading')" />
    <template v-else-if="request">
      <PageNotice notification theme="info"><template #message>{{request.public_code}} · {{t('req.scopeVersion')}} {{request.version}} · {{t('compliance.notice')}}</template></PageNotice>
      <PageNotice notification theme="info" :message="t('compliance.fileNotice')" />
      <PageNotice v-if="!isRequestOpen(request)" theme="warning" :message="t('req.closed')" />
      <PageNotice v-else-if="!request.scope" theme="warning" :message="t('req.emptyScope')" />
      <PageNotice v-else-if="hasReview(request,'compliance')" notification theme="info" :message="t('req.existingReview')" />
      <PageNotice v-if="eligible&&remaining" theme="warning" :message="t('compliance.remaining',{count:remaining})" />
      <div class="module-scroll page-stack">
      <div class="two-column equal">
        <t-card :title="t('compliance.original')" :bordered="false" class="section-card"><div class="form-stack"><t-tag variant="light">{{t('req.private')}}</t-tag><h2 class="record-title">{{request.title}}</h2><p class="readable">{{request.originalText}}</p><dl class="detail-list"><dt>{{t('common.customer')}}</dt><dd class="mono">{{request.customer}}</dd><dt>{{t('compliance.submitted')}}</dt><dd>{{formatJst(request.submittedAt)}}</dd><dt>{{t('req.originalVersion')}}</dt><dd>v{{request.current_request_version}}</dd><dt>{{t('req.intakeLabel')}}</dt><dd>{{t('req.intake.'+request.intake_status)}}</dd><dt>{{t('review.publication')}}</dt><dd><StatusTag :value="request.publication" /></dd></dl><hr class="section-divider" /><h3>{{t('compliance.attachments')}}</h3><RequestFiles :files="request.private_files" /></div></t-card>
        <t-card :title="t('compliance.record')" :bordered="false" class="section-card"><div class="form-stack">
          <StatusTag :value="request.compliance" />
          <t-link theme="primary" @click="router.push('/technical?id='+request.id)">{{t('nav.technical')}}</t-link>
          <template v-if="eligible"><p class="subtle">{{t('req.checkGuide')}}</p><div><div v-for="(_,index) in checks" :key="index" class="check-row"><t-checkbox v-model="checks[index]" :disabled="busy">{{t('compliance.check'+index)}}</t-checkbox></div></div><div><label for="review-note">{{t('compliance.note')}}</label><t-textarea id="review-note" v-model="note" :disabled="busy" :autosize="{minRows:3,maxRows:6}" :maxlength="4000" /></div><div><label for="review-question">{{t('compliance.question')}}</label><t-textarea id="review-question" v-model="question" :disabled="busy" :autosize="{minRows:3,maxRows:6}" :maxlength="4000" /></div></template>
        </div></t-card>
      </div>
      <t-card :title="t('req.history')" :bordered="false" class="section-card"><div v-if="request.reviews.length" class="form-stack"><div v-for="review in request.reviews" :key="review.id" class="timeline-item"><p class="subtle">{{formatJst(review.decided_at)}} · {{t('review.'+review.kind)}} · v{{review.scope_version}}</p><StatusTag :value="review.decision" /><p class="readable">{{review.reason}}</p><p class="mono">{{review.reviewer_id}}</p></div></div><p v-else class="subtle">{{t('common.empty')}}</p></t-card>
      </div>
      <div v-if="eligible" class="action-bar"><span class="muted">{{t('req.checkCurrent')}}</span><t-button variant="outline" theme="danger" :disabled="busy" @click="prepare('rejected')">{{t('compliance.reject')}}</t-button><t-button variant="outline" :disabled="busy" @click="prepare('needs_info')">{{t('compliance.return')}}</t-button><t-button :disabled="busy||remaining>0" @click="prepare('approved')">{{t('compliance.approve')}}</t-button></div>
      <t-dialog v-model:visible="confirmVisible" :header="t('compliance.confirm')" :confirm-btn="{content:t('common.confirm'),loading:busy}" :cancel-btn="{content:t('common.cancel'),disabled:busy}" :close-btn="!busy" :close-on-overlay-click="false" @confirm="commit"><div class="form-stack"><PageNotice inline theme="info" :message="t('req.confirmReview')" /><p><strong>{{request.public_code}} · {{request.version}}</strong></p><StatusTag :value="decision" /><p class="readable">{{note}}</p><p v-if="decision==='needs_info'" class="readable">{{question}}</p></div></t-dialog>
    </template>
    <t-empty v-else-if="!error" :description="t('error.notFound')" />
  </div>
</template>

