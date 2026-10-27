"""Snapshot old rows, or verify committed batch via the running localhost API.

Prints counts only. Tokens, passwords and connection strings never leave memory.
"""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import sys

import httpx
import psycopg
from psycopg.rows import dict_row

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.config import Settings  # noqa: E402
from app.demo_seed import validate_target  # noqa: E402
from app.process_demo import ROOT  # noqa: E402


def old_rows(conn):
    return {'requests': {str(r['id']): {k: str(v) for k, v in r.items()} for r in conn.execute('SELECT id,row_version,intake_status,current_request_version,current_scope_version FROM opc.requests')},
            'passwords': {str(r['account_id']): sha256(r['password_hash'].encode()).hexdigest() for r in conn.execute('SELECT account_id,password_hash FROM opc.password_credentials')}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--snapshot', action='store_true')
    args = parser.parse_args()
    settings = Settings()
    root = ROOT
    with psycopg.connect(settings.database_url, row_factory=dict_row) as conn:
        identity = conn.execute("""SELECT shobj_description(d.oid,'pg_database') AS marker,r.rolsuper AS superuser,
            r.rolcreatedb AS createdb,r.rolcreaterole AS createrole FROM pg_database d
            JOIN pg_roles r ON r.rolname=current_user WHERE d.datname=current_database()""").fetchone()
        target = validate_target(settings.database_url, identity)
        current = old_rows(conn)
        if args.snapshot:
            path = root / 'before-seed.json'
            if path.exists():
                raise SystemExit('已有原始快照，拒绝覆盖')
            path.write_text(json.dumps({'database': target, **current}, ensure_ascii=False, indent=2), encoding='utf-8')
            print(f"已保存原始快照：{len(current['requests'])} 条既有需求；未输出密码。")
            return
        before = json.loads((root / 'before-seed.json').read_text(encoding='utf-8'))
        assert before['database'] == target
        for group in ['requests', 'passwords']:
            assert all(current[group].get(key) == value for key, value in before[group].items()), '既有记录发生变化：' + group
        manifest = json.loads((root / 'seed-manifest.json').read_text(encoding='utf-8'))
        scenarios = manifest['scenarios']
        ids = [s['request_id'] for s in scenarios.values()]
        counts = {}
        queries = {
            'requests': 'SELECT count(*) AS n FROM opc.requests WHERE id=ANY(%s::uuid[])',
            'reviews': 'SELECT count(*) AS n FROM opc.review_decisions WHERE request_id=ANY(%s::uuid[])',
            'scope_versions': 'SELECT count(*) AS n FROM opc.scope_versions WHERE request_id=ANY(%s::uuid[])',
            'clarifications': 'SELECT count(*) AS n FROM opc.clarifications WHERE request_id=ANY(%s::uuid[])',
            'threads': 'SELECT count(*) AS n FROM opc.conversation_threads WHERE request_id=ANY(%s::uuid[])',
            'messages': 'SELECT count(*) AS n FROM opc.messages m JOIN opc.conversation_threads t ON t.id=m.thread_id WHERE t.request_id=ANY(%s::uuid[])',
            'engagements': 'SELECT count(*) AS n FROM opc.engagements WHERE request_id=ANY(%s::uuid[])',
            'deliveries': 'SELECT count(*) AS n FROM opc.deliveries d JOIN opc.engagements e ON e.id=d.engagement_id WHERE e.request_id=ANY(%s::uuid[])',
            'delivery_reviews': 'SELECT count(*) AS n FROM opc.delivery_reviews q JOIN opc.deliveries d ON d.id=q.delivery_id JOIN opc.engagements e ON e.id=d.engagement_id WHERE e.request_id=ANY(%s::uuid[])',
            'acceptances': 'SELECT count(*) AS n FROM opc.acceptance_decisions a JOIN opc.deliveries d ON d.id=a.delivery_id JOIN opc.engagements e ON e.id=d.engagement_id WHERE e.request_id=ANY(%s::uuid[])',
        }
        for key, query in queries.items():
            counts[key] = conn.execute(query, (ids,)).fetchone()['n']
        counts['files'] = len(manifest['uploads'])
        counts['asset_bytes'] = sum(r['size_bytes'] for r in manifest['uploads'].values())
        for key, scenario in scenarios.items():
            row = current['requests'][scenario['request_id']]
            if key == 'completed':
                assert row['intake_status'] == 'closed'
        ordered = conn.execute('''SELECT t.id,count(*) AS n,count(DISTINCT m.sent_at) AS times FROM opc.conversation_threads t
            JOIN opc.messages m ON m.thread_id=t.id WHERE t.request_id=ANY(%s::uuid[]) GROUP BY t.id''', (ids,)).fetchall()
        assert all(row['n'] == row['times'] for row in ordered)
    credentials = json.loads(Path('.local/demo-credentials.json').read_text(encoding='utf-8'))['accounts']
    headers = {}
    checks = []
    with httpx.Client(base_url='http://127.0.0.1:8001/api/v1', timeout=30) as client:
        try:
            for actor, account in credentials.items():
                audience = 'admin' if actor == 'admin' else 'mobile'
                response = client.post(f'/{audience}/auth/login', json={'email': account['email'], 'password': account['password']})
                assert response.status_code == 200, '登录失败：' + actor
                headers[actor] = {'Authorization': 'Bearer ' + response.json()['access_token']}
            def get(path, actor='admin', status=200):
                response = client.get(path, headers=headers[actor])
                assert response.status_code == status, f'{path}: {response.status_code}'
                return response
            for name, record in manifest['uploads'].items():
                owner, filename = name.split(':', 1)
                content = get(f"/mobile/files/{record['id']}/download", owner).content
                assert len(content) == record['size_bytes'] and sha256(content).hexdigest() == record['sha256']
                assert content == (root / 'assets' / filename).read_bytes()
            checks.append('所有原件经正在运行的8001鉴权下载，大小/SHA-256/本地源逐字节一致')
            hall = get('/mobile/hall?limit=100', 'provider').json()['items']
            hall_ids = {row['request_id'] for row in hall}
            assert {scenarios[key]['request_id'] for key in ['hall_booking', 'hall_media']} <= hall_ids
            assert not {scenarios[key]['request_id'] for key in ['pending', 'needs_info', 'reviewing']} & hall_ids
            checks.append('双审发布后可见；待审/待补充/单审不在大厅')
            for scenario in scenarios.values():
                get('/admin/requests/' + scenario['request_id'])
                for actor in ['customer', 'provider']:
                    get(f"/mobile/threads/{scenario['internal_thread_id']}/messages", actor, 404)
            private = scenarios['hall_media']['private_file_id']
            for ending in ['', '/download', '/preview']:
                get('/mobile/files/' + private + ending, 'provider', 404)
            checks.append('内部会话和客户私有附件的元数据/下载/预览不可越权')
            for filename, media_type in [('media-screen.png', 'image/png'), ('landscape.jpg', 'image/jpeg'), ('sample-road.mp4', 'video/mp4')]:
                fid = manifest['uploads']['customer:' + filename]['id']
                preview = get('/mobile/files/' + fid + '/preview', 'provider')
                assert preview.headers['content-type'].startswith(media_type)
            for filename in ['sample-tone.mp3', 'media-requirements.docx', 'media-data.xlsx', 'media-overview.pptx', 'media-acceptance.pdf']:
                fid = manifest['uploads']['customer:' + filename]['id']
                assert get('/mobile/files/' + fid + '/preview', 'provider').json()['state'] == 'unsupported'
            checks.append('图片/MP4真实预览；音频与Office/PDF明确返回现有转换限制，原件可下载')
            complete = scenarios['completed']
            detail = get('/admin/engagements/' + complete['engagement_id']).json()
            assert detail['engagement']['status'] == 'completed' and len(detail['deliveries']) == 2
            assert {row['decision'] for row in detail['acceptances']} == {'accepted', 'revision_requested'}
            pending = scenarios['internal_review']
            eid = pending['engagement_id']
            private_delivery = get('/mobile/engagements/' + eid, 'customer').json()
            assert private_delivery['deliveries'] == []
            checks.append('保留两次交付和修改/验收历史；未对客发布的交付不向客户展示')
            for scenario in scenarios.values():
                if 'project_thread_id' in scenario:
                    rows = get(f"/mobile/threads/{scenario['project_thread_id']}/messages", 'customer').json()['items']
                    assert len(rows) >= 4 and rows[0]['author_id'] == credentials['customer']['id']
                    assert any('provider' == actor for actor, account in credentials.items() if account['id'] in {m['author_id'] for m in rows})
            checks.append('客户与承接者中日文消息顺序及双方作者可读取')
        finally:
            for actor, auth in headers.items():
                audience = 'admin' if actor == 'admin' else 'mobile'
                client.post(f'/{audience}/auth/logout', headers=auth)
    summary = {'database': target, 'counts': counts, 'checks': checks, 'preexisting_requests_unchanged': len(before['requests']), 'passwords_unchanged': True}
    (root / 'verification.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'counts': counts, 'checks_passed': len(checks), 'existing_rows_unchanged': True}, ensure_ascii=False))


if __name__ == '__main__':
    main()
