"""Additive local process fixtures. No production startup hooks or policy changes."""
from hashlib import sha256
import json
import mimetypes
from pathlib import Path
from uuid import uuid5, NAMESPACE_URL

from fastapi.testclient import TestClient
import psycopg
from psycopg.rows import dict_row

from .config import Settings
from .communication import participant
from .demo_seed import DemoAPI, SeedDatabase, SCHEMA, REASON, validate_target, write_manifest
from .files import storage_path
from .main import create_app

ROOT = Path('.local/process-demo-20261025')
PROCESS_SCHEMA = 'opc.process-demo.20261025.v1'
SCENARIOS = [
    ('pending', 'booking', '地域施設の予約受付画面', 'submitted'),
    ('needs_info', 'media', '資料ライブラリの閲覧権限整理', 'needs_info'),
    ('reviewing', 'booking', '予約一覧のCSV出力改善', 'in_review'),
    ('hall_booking', 'booking', '小規模店舗の予約管理ツール', 'published'),
    ('hall_media', 'media', '画像と音声と動画の社内資料ポータル', 'published'),
    ('confirmation', 'booking', '会議室予約の重複防止機能', 'awaiting_confirmation'),
    ('executing', 'booking', '受付スタッフ向け予約検索', 'executing'),
    ('internal_review', 'media', '資料ダウンロード権限の検証ツール', 'internal_review'),
    ('revision', 'booking', '予約時刻の入力チェック改善', 'revision'),
    ('completed', 'booking', '予約データ保存の小規模開発', 'completed'),
]


def load_assets(root):
    evidence = json.loads((root / 'asset-manifest.json').read_text(encoding='utf-8'))
    if evidence.get('schema') != 'opc.process-assets.v1':
        raise ValueError('附件清单版本无效')
    assets = {}
    for record in evidence['files']:
        name = record['name']
        if Path(name).name != name or '/' in name or '\\' in name:
            raise ValueError('附件文件名无效')
        data = (root / 'assets' / name).read_bytes()
        if len(data) != record['size_bytes'] or sha256(data).hexdigest() != record['sha256']:
            raise ValueError('附件在检查后发生变化，拒绝标记 clean：' + name)
        if not record.get('inspection'):
            raise ValueError('附件缺少实际检查依据：' + name)
        assets[name] = (data, record)
    return assets


class ProcessAPI(DemoAPI):
    def __init__(self, client, accounts, conn, assets):
        super().__init__(client, accounts)
        self.conn, self.accounts, self.assets = conn, accounts, assets
        self.uploads = {}
        self.created_keys = []
        self.message_indices = {}
        for name, account in accounts.items():
            audience = 'admin' if name == 'admin' else 'mobile'
            me = self.call('GET', f'/{audience}/auth/me', name)
            if me['id'] != account['id']:
                raise ValueError('演示凭据账号与已验证登录身份不一致')

    def fixture(self, name, owner='customer'):
        key = owner + ':' + name
        if key in self.uploads:
            return self.uploads[key]['id']
        data, evidence = self.assets[name]
        media = mimetypes.guess_type(name)[0] or 'application/octet-stream'
        record = self.call('POST', '/mobile/files', owner, files={'file': (name, data, media)})
        row = self.conn.execute('SELECT storage_key FROM opc.files WHERE id=%s', (record['id'],)).fetchone()
        self.created_keys.append(str(row['storage_key']))
        if record['sha256'] != evidence['sha256'] or record['size_bytes'] != len(data):
            raise ValueError('上传字节校验失败')
        record = self.call('POST', f"/admin/files/{record['id']}/inspection", payload={
            'expected_version': record['row_version'], 'decision': 'clean',
            'reason': '仅本批已检查合成/公开测试素材。SHA-256=' + evidence['sha256'] + '；' + evidence['inspection'] + '。未运行恶意软件扫描，不适用于未知用户附件。',
        })
        response = self.client.get(f"/api/v1/mobile/files/{record['id']}/download", headers=self.headers[owner])
        if response.status_code != 200 or response.content != data:
            raise ValueError('真实下载不一致')
        self.uploads[key] = record
        return record['id']

    def messages(self, thread, sequence):
        # Normal API checks object visibility before each seed insert. Explicit
        # clock_timestamp preserves message order inside this atomic fixture tx;
        # the ordinary API's now() default would tie every message timestamp.
        for actor, body in sequence:
            index = self.message_indices.get(thread, 0) + 1
            self.message_indices[thread] = index
            audience = 'admin' if actor == 'admin' else 'mobile'
            self.call('GET', f'/{audience}/threads/{thread}/messages', actor)
            account_id = self.accounts[actor]['id']
            self.conn.execute("SELECT set_config('opc.actor_id',%s,true)", (account_id,))
            self.conn.execute("SELECT set_config('opc.correlation_id','process-demo-20261025',true)")
            participant(self.conn, thread, account_id, account_id)
            client_id = uuid5(NAMESPACE_URL, f'opc-process:{thread}:{index}')
            self.conn.execute('''INSERT INTO opc.messages(thread_id,author_id,body,client_message_id,sent_at)
                VALUES (%s,%s,%s,%s,clock_timestamp())''',
                (thread, account_id, '【合成デモ / 合成演示】' + body, client_id))

    def scope(self, rid, record, title, family, refs):
        features = ('予約一覧、日付検索、重複防止、CSV 出力。预约列表、日期筛选、重复校验和导出。' if family == 'booking'
                    else '画像・音声・動画の分類、権限別一覧、原本ダウンロード。按媒体格式检索与鉴权下载。')
        return self.call('POST', f'/admin/requests/{rid}/scopes', payload={
            'expected_version': record['row_version'], 'title': title,
            'public_summary': '【合成デモ案件】日本国内の開発サービス。' + features,
            'category': '業務システム開発', 'goal': '手作業を減らし、操作と資料取得の履歴を確認できるようにする。',
            'included_scope': features, 'excluded_scope': '決済、本番公開、個人情報、OSS、AI 自動処理、Office 変換。',
            'deliverables': ['固定バージョンのソース ZIP', '操作説明と検証資料', '合成データと参考画面'],
            'acceptance_criteria': ['合成データを保存し再取得できる', '権限外の資料取得を拒否する', '原本のハッシュが一致する'],
            'duration_text': '双方確認後 10 営業日（合成予定）',
            'revision_terms': '合意した範囲内の不具合を修正。范围增加需重新整理审核。', 'file_ids': refs,
        })


def create_scenarios(api):
    scenarios = {}
    for key, family, title, stage in SCENARIOS:
        refs = [api.fixture(family + suffix) for suffix in ['-screen.png', '-requirements.docx', '-acceptance.pdf', '-data.xlsx', '-overview.pptx', '-sample.csv']]
        if family == 'media':
            refs += [api.fixture(name) for name in ['landscape.jpg', 'sample-tone.mp3', 'sample-road.mp4', 'media-sources.md', 'media-test-notes.txt']]
        private = api.fixture('private-intake-note.txt')
        record = api.call('POST', '/mobile/requests', 'customer', {
            'original_description': f'【合成デモ案件】{title}。日本国内の3名のスタッフで使用する小規模な開発を相談します。現状は手作業が多いため、入力・検索・資料取得を改善したいです。附上合成需求、验收指南和文件示例；不含真实客户资料。',
            'timing_text': '双方確認後 10 営業日', 'budget_text': 'JPY 120,000 参考見積のみ / 仅参考报价',
            'file_ids': refs + [private],
        }, key='process-20261025-' + key)
        rid = record['id']
        scenario = scenarios[key] = {'request_id': rid, 'title': title, 'family': family, 'initial_stage': stage, 'reference_file_ids': refs, 'private_file_id': private}
        internal = api.call('POST', '/admin/threads', payload={'request_id': rid, 'kind': 'internal'})['id']
        scenario['internal_thread_id'] = internal
        api.messages(internal, [('admin', f'受理评估：{title}，仅开发服务，日本国内使用，素材为合成或公开测试内容。私有补充附件不进入大厅。'),
                                ('admin', '技術整理メモ：利用者3名。範囲、納品物、権限と検収条件を分けて確認する。内部授权不等于正式认证，合成报价不代表收款。')])
        if key in {'pending', 'needs_info', 'reviewing'}:
            thread = api.call('POST', f'/mobile/requests/{rid}/consultation', 'customer')['id']
            scenario['consultation_thread_id'] = thread
            api.messages(thread, [('customer', '現在は表計算とメッセージで管理しています。添付の画面例を参考に相談できますか。'),
                                  ('admin', '可以。请先确认使用人数、哪些文件允许作为参考资料发布。私有补充只用于受理。'),
                                  ('customer', '利用者は3名です。合成の画面と資料のみ公開可能です。音声と動画は形式検証用です。'),
                                  ('admin', '已记录。范围整理和审核完成后才会发布，预计工期仍需双方确认。')])
        if key == 'pending':
            continue
        if key == 'reviewing':
            record = api.call('POST', f'/admin/requests/{rid}/clarifications', payload={'expected_version': record['row_version'], 'question': 'CSV に必要な項目と利用人数を教えてください。请说明导出字段与使用人数。'})
            question = record['clarifications'][-1]['id']
            record = api.call('POST', f'/mobile/requests/{rid}/clarifications/{question}/answer', 'customer', {'expected_version': record['row_version'], 'answer': 'ID、日付、時刻、表示名、状態の5項目。利用者3名。仅使用合成数据，不导出个人联系方式。'})
        record = api.scope(rid, record, title, family, refs)
        if key == 'needs_info':
            api.call('POST', f'/admin/requests/{rid}/reviews', payload={'expected_version': record['row_version'], 'scope_version': record['current_scope_version'], 'kind': 'compliance', 'decision': 'needs_info', 'reason': REASON + '；私有/发布资料的授权范围尚需客户补充。公開範囲を再確認します。', 'question': 'どの資料を内部担当者へ公開してよいですか。请明确音频视频是否只作内部参考。'})
            continue
        for kind in ['compliance', 'technical']:
            if key == 'reviewing' and kind == 'technical':
                break
            record = api.call('POST', f'/admin/requests/{rid}/reviews', payload={
                'expected_version': record['row_version'], 'scope_version': record['current_scope_version'], 'kind': kind, 'decision': 'approved',
                'reason': REASON + ('；合规演示：材料为合成值与公开测试素材，私有附件未选为发布参考。公開範囲と用途を確認。' if kind == 'compliance' else '；技术评审演示：输入、权限、交付版本与验收条件已在整理稿列明；不包含生产部署和自动转换。実装範囲を限定。'),
            })
        if key == 'reviewing':
            continue
        record = api.call('POST', f'/admin/requests/{rid}/publish', payload={'expected_version': record['row_version'], 'scope_version': record['current_scope_version'], 'reason': REASON + '；显式发布审核版本及选定参考资料。'})
        if key.startswith('hall_'):
            thread = api.call('POST', f'/mobile/requests/{rid}/consultation', 'provider')['id']
            scenario['provider_consultation_thread_id'] = thread
            api.messages(thread, [('provider', '公開された範囲を確認しました。参考ファイルの取得と検証条件について質問があります。'),
                                  ('admin', '本批只演示开发需求与附件。图片和MP4可预览，音频、Office和PDF按现有能力下载原件打开。合作录入仍需确认，不代表自动抢单。'),
                                  ('provider', '承知しました。未公開の私有資料は参照せず、公開版の範囲で検討します。')])
            continue
        engagement = api.call('POST', '/admin/engagements', payload={
            'request_id': rid, 'expected_version': record['row_version'], 'provider_id': api.accounts['provider']['id'],
            'terms': '【合成合作】双方按当前范围确认后实施。源码 ZIP、操作说明、合成验证材料交付；不代表真实业务订单或收费。',
            'quoted_amount': 120000, 'reason': REASON + '；仅录入合成已确认合作关系，不选定接单机制。',
        }, key='process-engagement-' + key)
        eid = scenario['engagement_id'] = engagement['engagement_id']
        thread = next(t['id'] for t in api.call('GET', '/mobile/threads?limit=100', 'customer')['items'] if t['engagement_id'] == eid and t['kind'] == 'customer_project')
        scenario['project_thread_id'] = thread
        api.messages(thread, [('customer', f'{title}の整理内容を読みました。保存後の再読込と、重複・権限の確認を重視しています。'),
                              ('provider', '已收到。先按整理范围制作最小示例，代码和说明会固定版本提交。'),
                              ('customer', '対象外の本番公開や決済は今回は依頼しません。合成データのみ利用してください。'),
                              ('provider', '了解。工期从双方确认条款后计算，进度与变更会在此会话记录。')])
        if key == 'confirmation':
            continue
        for actor in ['customer', 'provider']:
            engagement = api.call('POST', f'/mobile/engagements/{eid}/agreements/1/confirm', actor, {'expected_version': engagement['row_version']})
        api.messages(thread, [('provider', '双方の確認を受け、実装に着手しました。まず保存と再取得を確認します。'),
                              ('customer', '请保留修改记录。文件名和原文无需随界面语言翻译。')])
        if key == 'executing':
            api.messages(thread, [('provider', '一覧と検索の準備を進めています。次は合成入力で境界条件を確認する予定です。'), ('customer', '好的，交付时请一起提供运行说明和测试材料。')])
            continue
        versions = [1, 2] if key == 'completed' else [1]
        scenario['delivery_ids'] = []
        for version in versions:
            source = api.fixture(f'booking-source-v{version}.zip', 'provider')
            attachments = [{'file_id': api.fixture(family + suffix, 'provider'), 'purpose': purpose} for suffix, purpose in [('-requirements.docx', 'guide'), ('-acceptance.pdf', 'tests'), ('-data.xlsx', 'tests'), ('-overview.pptx', 'demo'), ('-screen.png', 'demo')]]
            delivery = api.call('POST', f'/mobile/engagements/{eid}/deliveries', 'provider', {
                'expected_version': engagement['row_version'], 'agreement_version': 1,
                'note': f'【合成納品 v{version}】最小の予約保存サンプルと説明資料。媒体项目也仅附最小字节持久化参考代码，不冒充完整门户实现。',
                'source_file_id': source, 'guide_text': '下载 ZIP 后解压，在 Python 3 下执行 python -m unittest -v。标准库最小示例，无网络依赖；不适用于生产。',
                'test_report_text': '本批生成时实际执行1项合成源码单测：保存、重新读取、重复阻止；下载字节与 SHA-256 实际核对。权限另由种子验证器检查。未运行未知客户代码。',
                'files': attachments,
            }, key=f'process-delivery-{key}-{version}')
            did = delivery['delivery_id']
            scenario['delivery_ids'].append(did)
            engagement = delivery
            if key == 'internal_review':
                api.messages(internal, [('admin', '内部检查待办：核对源码、说明与验收范围。最小预约样例不是媒体门户的完整实现，尚未作出质检结论或对客发布。'), ('admin', '品質確認中。お客様には内部納品を公開していません。')])
                break
            reviewed = api.call('POST', f'/admin/engagements/{eid}/deliveries/{did}/review', payload={
                'expected_version': engagement['row_version'], 'decision': 'approved',
                'evidence': REASON + '；演示质检：已知最小样例的单测、OOXML/PDF结构与素材解码检查及原件哈希证据见本机批次清单。不是完整生产系统验收。合成資料の版と用途を確認。',
            })
            engagement = api.call('POST', f'/admin/engagements/{eid}/deliveries/{did}/publish', payload={'expected_version': reviewed['row_version']})
            api.messages(thread, [('provider', f'合成の納品 v{version} が内部確認後に公開されました。ソースと説明資料を取得できます。'), ('customer', '已收到，我会核对说明中的最小保存示例与附件。')])
            decision = 'accepted' if key == 'completed' and version == 2 else 'revision_requested'
            feedback = ('【合成验收】确认最小保存示例和原件下载说明。こちらは合成検収記録です。実決済や本番承認を行いません。' if decision == 'accepted' else '【合成修改】请在说明中补充重复时段被拒绝的预期结果，保留旧版本。重複入力時の説明を明記してください。')
            engagement = api.call('POST', f'/mobile/engagements/{eid}/deliveries/{did}/acceptance', 'customer', {'expected_version': engagement['row_version'], 'decision': decision, 'feedback': feedback}, key=f'process-accept-{key}-{version}')
            api.messages(thread, [('customer', feedback), ('provider', '検収の記録を確認しました。履歴を保存し、この会話に対応内容を残します。' if decision == 'accepted' else '收到修改意见，将在新版本说明中补充重复校验的预期结果，并重新提交内部检查。')])
    return scenarios


def seed_process_demo(settings=None, root=ROOT, credentials_path=Path('.local/demo-credentials.json')):
    settings = settings or Settings()
    root = Path(root)
    assets = load_assets(root)
    credentials = json.loads(Path(credentials_path).read_text(encoding='utf-8'))
    manifest_path = root / 'seed-manifest.json'
    with psycopg.connect(settings.database_url, row_factory=dict_row) as conn:
        identity = conn.execute("""SELECT shobj_description(d.oid,'pg_database') AS marker,
            r.rolsuper AS superuser,r.rolcreatedb AS createdb,r.rolcreaterole AS createrole
            FROM pg_database d JOIN pg_roles r ON r.rolname=current_user WHERE d.datname=current_database()""").fetchone()
        target = validate_target(settings.database_url, identity)
        if credentials.get('schema') != SCHEMA or credentials.get('state') != 'ready' or credentials.get('database') != target:
            raise ValueError('演示账号清单与受限本机库不匹配')
        conn.execute('SELECT pg_advisory_xact_lock(184920,21)')
        if manifest_path.exists():
            manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
            if manifest.get('schema') != PROCESS_SCHEMA or manifest.get('database') != target:
                raise ValueError('批次清单归属不匹配')
            if set(manifest.get('scenarios', {})) != {s[0] for s in SCENARIOS} or not manifest.get('uploads'):
                raise ValueError('批次清单不完整，拒绝覆盖')
            ids = [s['request_id'] for s in manifest['scenarios'].values()]
            present = conn.execute('SELECT count(*) AS n FROM opc.requests WHERE id=ANY(%s::uuid[])', (ids,)).fetchone()['n']
            if present == len(ids):
                file_ids = [r['id'] for r in manifest['uploads'].values()]
                files = conn.execute('SELECT id,storage_key,size_bytes,sha256 FROM opc.files WHERE id=ANY(%s::uuid[])', (file_ids,)).fetchall()
                if len(files) != len(file_ids):
                    raise ValueError('批次附件记录缺失，拒绝自动重建')
                for file in files:
                    stored = storage_path(settings.storage_root, file['storage_key'])
                    if not stored.is_file() or stored.stat().st_size != file['size_bytes'] or sha256(stored.read_bytes()).hexdigest() != file['sha256']:
                        raise ValueError('批次原件缺失或损坏，拒绝自动覆盖')
                return manifest
            if present:
                raise ValueError('批次部分记录缺失，拒绝覆盖或自动重建')
            # An interrupted outer commit can leave a manifest but zero records.
        app = create_app(settings.model_copy(update={'assignment_mode': 'record_confirmed'}), SeedDatabase(conn))
        try:
            with TestClient(app) as client:
                api = ProcessAPI(client, credentials['accounts'], conn, assets)
                scenarios = create_scenarios(api)
                api.logout()
                manifest = {'schema': PROCESS_SCHEMA, 'database': target, 'scenarios': scenarios, 'uploads': api.uploads}
                write_manifest(manifest_path, manifest)
        except Exception:
            # Files are not transactional. Clean only keys inserted by this batch.
            # The outer transaction might be aborted, so capture keys from HTTP
            # responses rather than running SQL in the failed transaction.
            for key in getattr(locals().get('api'), 'created_keys', []):
                storage_path(settings.storage_root, key).unlink(missing_ok=True)
            raise
    return manifest


def main():
    try:
        result = seed_process_demo()
    except (ValueError, psycopg.Error) as exc:
        raise SystemExit(str(exc) if isinstance(exc, ValueError) else '数据库操作失败；未输出连接配置') from None
    print(f"流程演示就绪：{len(result['scenarios'])} 条新增需求，{len(result['uploads'])} 个原件记录；凭据和既有进度未重置。")


if __name__ == '__main__':
    main()
