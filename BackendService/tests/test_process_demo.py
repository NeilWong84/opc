from hashlib import sha256
import json

import pytest

from app.process_demo import load_assets, ProcessAPI, create_scenarios


def test_checked_asset_rejects_modified_bytes(tmp_path):
    (tmp_path / 'assets').mkdir()
    path = tmp_path / 'assets/example.txt'
    path.write_bytes(b'known fixture')
    (tmp_path / 'asset-manifest.json').write_text(json.dumps({
        'schema': 'opc.process-assets.v1', 'files': [{'name': path.name, 'size_bytes': 13,
        'sha256': sha256(b'known fixture').hexdigest(), 'inspection': 'known constant'}],
    }))
    assert load_assets(tmp_path)['example.txt'][0] == b'known fixture'
    path.write_bytes(b'changed bytes')
    with pytest.raises(ValueError, match='检查后发生变化'):
        load_assets(tmp_path)


@pytest.mark.integration
def test_process_scenarios_preserve_review_visibility_and_versions(integration_context):
    from conftest import TEST_PASSWORD
    ctx = integration_context
    accounts = {name: {**ctx.actors[name], 'password': TEST_PASSWORD} for name in ['admin', 'customer', 'provider']}
    names = [family + suffix for family in ['booking', 'media'] for suffix in ['-screen.png', '-requirements.docx', '-acceptance.pdf', '-data.xlsx', '-overview.pptx', '-sample.csv']]
    names += ['private-intake-note.txt', 'landscape.jpg', 'sample-tone.mp3', 'sample-road.mp4', 'media-sources.md', 'media-test-notes.txt', 'booking-source-v1.zip', 'booking-source-v2.zip']
    # These are isolated byte constants to exercise the fixture workflow; they
    # are never served as real media or installed into the persistent library.
    data = b'isolated test constant'
    assets = {name: (data, {'sha256': sha256(data).hexdigest(), 'inspection': 'isolated test byte constant, no scanner'}) for name in names}
    api = ProcessAPI(ctx.client, accounts, ctx.connection, assets)
    scenarios = create_scenarios(api)
    assert len(scenarios) == 10
    hall = api.call('GET', '/mobile/hall?limit=100', 'provider')['items']
    hall_ids = {r['request_id'] for r in hall}
    assert {scenarios[k]['request_id'] for k in ['hall_booking', 'hall_media']} <= hall_ids
    assert not {scenarios[k]['request_id'] for k in ['pending', 'needs_info', 'reviewing']} & hall_ids
    for scenario in scenarios.values():
        thread = scenario['internal_thread_id']
        denied = ctx.client.get(f'/api/v1/mobile/threads/{thread}/messages', headers=api.headers['customer'])
        assert denied.status_code == 404
    private = scenarios['hall_media']['private_file_id']
    assert ctx.client.get(f'/api/v1/mobile/files/{private}/download', headers=api.headers['provider']).status_code == 404
    complete = scenarios['completed']
    detail = api.call('GET', '/admin/engagements/' + complete['engagement_id'])
    assert detail['engagement']['status'] == 'completed'
    assert len(detail['deliveries']) == 2
    assert {r['decision'] for r in detail['acceptances']} == {'accepted', 'revision_requested'}
    messages = api.call('GET', f"/mobile/threads/{complete['project_thread_id']}/messages", 'customer')['items']
    assert messages[0]['author_id'] == accounts['customer']['id']
    assert len({r['sent_at'] for r in messages}) == len(messages)
    assert any('修正' in r['body'] or '修改' in r['body'] for r in messages)
    api.logout()
