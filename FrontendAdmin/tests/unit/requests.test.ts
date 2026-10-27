import { describe, expect, it, vi } from 'vitest';
import { api, ApiError } from '../../src/services/api';
import { locale } from '../../src/composables/preferences';
import { createAdminRepository, hasReview, isPublishable, mapRequest, requestError, scopeDraft, scopePayload, type RequestDetail } from '../../src/services/requests';

function detail(overrides: Partial<RequestDetail> = {}): RequestDetail {
  return {
    id:'request-a',public_code:'REQ-A',customer_id:'customer-a',intake_status:'in_review',
    current_request_version:2,current_scope_version:3,row_version:9,created_at:'2026-10-16T00:00:00Z',updated_at:'2026-10-22T00:00:00Z',
    original:{version:2,original_description:'顧客が提出した原文です。',timing_text:'相談',budget_text:'相談',submitted_at:'2026-10-16T00:00:00Z'},private_files:[],
    scope:{version:3,request_version:2,title:'公開タイトル',public_summary:'公開概要',category:'development',goal:'目的',included_scope:'範囲',excluded_scope:'対象外',deliverables:['ソース','手順書'],acceptance_criteria:['確認項目'],duration_text:'2週間',revision_terms:'修正条件',authored_at:'2026-10-17T00:00:00Z',reference_files:[]},
    reviews:[
      {id:'review-a',scope_version:3,kind:'compliance',decision:'approved',reason:'確認済み',reviewer_id:'admin-a',decided_at:'2026-10-18T00:00:00Z'},
      {id:'review-b',scope_version:3,kind:'technical',decision:'approved',reason:'確認済み',reviewer_id:'admin-a',decided_at:'2026-10-18T00:00:00Z'},
    ],clarifications:[],publications:[],...overrides,
  };
}
describe('真实管理接口数据与发布状态',()=>{
  it('根据界面语言展示 API 错误并保留诊断编号，不直接把中文服务消息放进日语界面',()=>{
    locale.value='ja-JP';
    const error=new ApiError(409,'VERSION_CONFLICT','中文后台错误','request-trace-123');
    expect(requestError(error)).toContain('データの版が変更');
    expect(requestError(error)).not.toContain('中文后台错误');
    expect(requestError(error)).toContain('VERSION_CONFLICT');
    expect(requestError(error)).toContain('request-trace-123');
    locale.value='zh-CN';
    expect(requestError(error)).toContain('数据版本已改变');
  });
  it('仅当前原文、范围与双审一致时显示待发布',()=>{
    expect(isPublishable(mapRequest(detail()))).toBe(true);
    expect(isPublishable(mapRequest(detail({current_request_version:4})))).toBe(false);
    expect(isPublishable(mapRequest(detail({current_scope_version:4})))).toBe(false);
    expect(isPublishable(mapRequest(detail({reviews:detail().reviews.slice(0,1)})))).toBe(false);
  });
  it.each(['closed','withdrawn'])('已%s需求不能显示可发布',intake_status=>{
    expect(isPublishable(mapRequest(detail({intake_status})))).toBe(false);
  });
  it('未回答澄清阻止待发布展示，旧版审核不冒充当前审核',()=>{
    const record=detail({clarifications:[{id:'question-a',question:'資料の権限は？',answer:null,asked_at:'2026-10-18T00:00:00Z',answered_at:null,request_version:2}]});
    expect(isPublishable(mapRequest(record))).toBe(false);
    record.clarifications=[];
    record.reviews.forEach(review=>review.scope_version=1);
    const mapped=mapRequest(record);
    expect(mapped.compliance).toBe('pending');expect(mapped.technicalVersion).toBeNull();expect(hasReview(mapped,'compliance')).toBe(false);
  });
  it('区分真实发布记录与只有审核通过的记录',()=>{
    const published=mapRequest(detail({publications:[{id:'publication-a',scope_version:3,published_at:'2026-10-18T00:00:00Z',withdrawn_at:null}]}));
    expect(published.publication).toBe('published');expect(isPublishable(published)).toBe(false);
  });
  it('没有整理稿的需求保留客户原文，不创建合成技术范围',()=>{
    const mapped=mapRequest(detail({scope:null,current_scope_version:null,reviews:[]}));
    expect(mapped.title).toBe(mapped.originalText);expect(mapped.technical).toBe('not_started');expect(mapped.version).toBe('—');
    expect(scopeDraft(null).title).toBe('');expect(scopeDraft(null).file_ids).toEqual([]);
  });
  it('技术整理保留明确文件选择并按接口转换列表字段',()=>{
    const draft=scopeDraft(detail().scope);
    draft.deliverables=' ソース \r\n\n 手順書 ';draft.file_ids=['selected-file'];
    const payload=scopePayload(draft,9);
    expect(payload.deliverables).toEqual(['ソース','手順書']);expect(payload.expected_version).toBe(9);
    expect(payload.file_ids).toEqual(['selected-file']);expect(payload.acceptance_criteria).toEqual(['確認項目']);
  });
});

describe('真实 API Repository',()=>{
  it('按服务端分页、搜索与受理状态查询，记录来自接口详情',async()=>{
    const transport=vi.fn<typeof api>();
    transport.mockResolvedValueOnce({items:[{id:'request-a'}],total:42}).mockResolvedValueOnce(detail());
    const repository=createAdminRepository(transport as typeof api);
    await repository.loadPage({page:3,pageSize:10,q:'顧客 A',status:'needs_info'});
    const url=transport.mock.calls[0]![0];
    expect(url).toContain('limit=10');expect(url).toContain('offset=20');expect(url).toContain('status=needs_info');
    expect(new URL('http://localhost'+url).searchParams.get('q')).toBe('顧客 A');
    expect(transport.mock.calls[1]![0]).toBe('/api/v1/admin/requests/request-a');
    expect(repository.total).toBe(42);expect(repository.requests[0]?.originalText).toBe(detail().original.original_description);
  });
  it('读取失败清空旧列表并传播错误，不回退样例',async()=>{
    const transport=vi.fn<typeof api>().mockResolvedValueOnce({items:[{id:'request-a'}],total:1}).mockResolvedValueOnce(detail());
    const repository=createAdminRepository(transport as typeof api);await repository.loadPage();
    transport.mockRejectedValueOnce(new Error('DATABASE_UNAVAILABLE'));
    await expect(repository.loadPage()).rejects.toThrow('DATABASE_UNAVAILABLE');
    expect(repository.requests).toEqual([]);expect(repository.loading).toBe(false);expect(repository.total).toBe(0);
  });
  it('审核提交携带服务端 row_version 和 scope_version，不本地推算成功',async()=>{
    const transport=vi.fn<typeof api>().mockResolvedValueOnce(detail({row_version:10}));
    const repository=createAdminRepository(transport as typeof api);
    await repository.review('request-a',9,3,'compliance','needs_info','需补充权利证明','使用许可在哪里？');
    expect(transport).toHaveBeenCalledWith('/api/v1/admin/requests/request-a/reviews',{method:'POST',body:{expected_version:9,scope_version:3,kind:'compliance',decision:'needs_info',reason:'需补充权利证明',question:'使用许可在哪里？'}});
    expect(repository.details['request-a']?.revision).toBe(10);
  });
  it('409或失败不会伪造发布成功',async()=>{
    const transport=vi.fn<typeof api>().mockResolvedValueOnce(detail());
    const repository=createAdminRepository(transport as typeof api);await repository.load('request-a');
    transport.mockRejectedValueOnce(new Error('VERSION_CONFLICT'));
    await expect(repository.publish('request-a',9,3,'发布')).rejects.toThrow('VERSION_CONFLICT');
    expect(repository.details['request-a']?.publication).toBe('ready');expect(repository.details['request-a']?.revision).toBe(9);
  });
  it('下架使用真实 API 保留原因与乐观锁',async()=>{
    const transport=vi.fn<typeof api>().mockResolvedValue(detail());
    const repository=createAdminRepository(transport as typeof api);await repository.unpublish('request-a',9,'需重新确认');
    expect(transport).toHaveBeenCalledWith('/api/v1/admin/requests/request-a/publication/withdraw',{method:'POST',body:{expected_version:9,reason:'需重新确认'}});
  });
  it('退出后的迟到响应不能重新填充受保护数据',async()=>{
    let resolve!:(value:RequestDetail)=>void;
    const transport=vi.fn<typeof api>().mockImplementation(()=>new Promise(resolvePromise=>{resolve=resolvePromise;}));
    const repository=createAdminRepository(transport as typeof api),loading=repository.load('request-a');
    repository.reset();resolve(detail());
    await expect(loading).rejects.toThrow('SESSION_CHANGED');
    expect(repository.details).toEqual({});expect(repository.requests).toEqual([]);
  });
  it('较旧的列表响应不能覆盖后续搜索',async()=>{
    let resolve!:(value:unknown)=>void;
    const transport=vi.fn<typeof api>().mockImplementationOnce(()=>new Promise(done=>{resolve=done;})).mockResolvedValueOnce({items:[],total:0});
    const repository=createAdminRepository(transport as typeof api),first=repository.loadPage({q:'old'});
    await repository.loadPage({q:'new'});resolve({items:[],total:20});await first;
    expect(repository.total).toBe(0);expect(repository.loading).toBe(false);
  });
});


