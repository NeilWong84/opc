import { beforeEach, describe, expect, it, vi } from 'vitest';
import * as ops from '../../src/services/operations';
import * as audit from '../../src/services/audit';
const mocks = vi.hoisted(() => ({ api: vi.fn(), downloadFile: vi.fn() }));
vi.mock('../../src/services/api', () => mocks);
beforeEach(() => vi.clearAllMocks());
describe('真实运营API契约', () => {
 it('读取返回服务端行版本，失败不回退样例', async () => { const detail={engagement:{id:'e1',row_version:8},deliveries:[]}; mocks.api.mockResolvedValueOnce(detail); expect(await ops.getEngagement('e1')).toBe(detail); mocks.api.mockRejectedValueOnce(new Error('NETWORK_ERROR')); await expect(ops.getEngagement('e1')).rejects.toThrow('NETWORK_ERROR'); });
 it('未核对清单不能提交通过', async () => { await expect(ops.reviewDelivery('e1','d1',7,'approved','実際の証拠',[true,true,false,true])).rejects.toThrow('checklistRequired'); expect(mocks.api).not.toHaveBeenCalled(); });
 it('质检和发布独立并使用真实合作行版本', async () => { await ops.reviewDelivery('e1','d1',7,'approved','実際の証拠',[true,true,true,true]); expect(mocks.api).toHaveBeenLastCalledWith('/api/v1/admin/engagements/e1/deliveries/d1/review',{method:'POST',body:{expected_version:7,decision:'approved',evidence:'実際の証拠'}}); await ops.publishDelivery('e1','d1',8); expect(mocks.api).toHaveBeenLastCalledWith('/api/v1/admin/engagements/e1/deliveries/d1/publish',{method:'POST',body:{expected_version:8}}); });
 it('停用只变更账号，不自动改派项目',async()=>{ await ops.changeMemberStatus('a1',11,'disabled','引き継ぎを確認'); expect(mocks.api).toHaveBeenCalledTimes(1); expect(mocks.api).toHaveBeenCalledWith('/api/v1/admin/accounts/a1/status',{method:'PUT',body:{expected_version:11,status:'disabled',reason:'引き継ぎを確認'}}); });
 it('角色和内部授权是不同契约',async()=>{ await ops.changeProviderRole('a1',true,'担当者登録'); expect(mocks.api).toHaveBeenLastCalledWith('/api/v1/admin/accounts/a1/roles',{method:'POST',body:{role:'provider',reason:'担当者登録'}}); await ops.changeProviderAuthorization('a1',true,'内部受注許可'); expect(mocks.api).toHaveBeenLastCalledWith('/api/v1/admin/accounts/a1/provider-authorization',{method:'POST',body:{reason:'内部受注許可'}}); });
 it('手动检查保留证据和文件版本',async()=>{ await ops.inspectFile('f1',4,'clean','検査記録 A'); expect(mocks.api).toHaveBeenLastCalledWith('/api/v1/admin/files/f1/inspection',{method:'POST',body:{expected_version:4,decision:'clean',reason:'検査記録 A'}}); });
 it('消息重试沿用调用方的幂等ID',async()=>{ await ops.sendProjectMessage('t1','原文です','fixed-id'); expect(mocks.api).toHaveBeenCalledWith('/api/v1/admin/threads/t1/messages',{method:'POST',body:{body:'原文です',client_message_id:'fixed-id'}}); });
 it('审计使用服务端游标，不在本地伪造审计',async()=>{ mocks.api.mockResolvedValue({items:[]}); expect(await audit.listAuditEntries(100)).toEqual({items:[]}); expect(mocks.api).toHaveBeenCalledWith('/api/v1/admin/audit-events?limit=50&before_id=100'); expect(audit.formatJst('2026-10-12T01:18:32Z')).toBe('2026-10-12 10:18:32 JST'); });
});
