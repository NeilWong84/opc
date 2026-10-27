from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

import pytest

from test_integration import call, published_request, deliver

pytestmark = pytest.mark.integration


def proposal(ctx, record, actor='provider'):
    thread = call(ctx, 'POST', f"/mobile/requests/{record['id']}/negotiation", actor)
    current = call(ctx, 'GET', f"/mobile/threads/{thread['id']}/negotiation", actor)
    row = call(ctx, 'POST', f"/mobile/threads/{thread['id']}/proposal", actor, payload={
        'publication_id': current['publication_id'], 'terms': '双方確認用の開発範囲と固定納品条件',
        'quoted_amount': 123456, 'due_at': '2026-12-01T00:00:00+09:00'}, key=uuid4().hex)
    return thread, row


def confirm(ctx, thread, row):
    detail = call(ctx, 'GET', f"/mobile/threads/{thread['id']}/negotiation", 'customer')
    call(ctx, 'POST', f"/mobile/claim-proposals/{row['id']}/confirm", 'customer',
         payload={'expected_version': detail['proposal']['row_version']})
    return call(ctx, 'GET', f"/mobile/threads/{thread['id']}/negotiation", 'provider')['proposal']['row_version']


def test_customer_confirmation_claim_delivery_and_private_threads(integration_context):
    ctx = integration_context
    record = published_request(ctx)
    thread, row = proposal(ctx, record)
    call(ctx, 'GET', f"/mobile/threads/{thread['id']}/negotiation", 'stranger', status=404)
    call(ctx, 'GET', f"/mobile/threads/{thread['id']}/negotiation", 'admin', status=401)
    for actor in ('customer', 'provider'):
        assert any(t['id'] == thread['id'] for t in call(ctx, 'GET', '/mobile/threads?limit=100', actor)['items'])
        call(ctx, 'POST', f"/mobile/threads/{thread['id']}/messages", actor, status=201,
             payload={'body': '范围和条款沟通原文', 'client_message_id': str(uuid4())})
    assert len(call(ctx, 'GET', f"/mobile/threads/{thread['id']}/messages", 'customer')['items']) == 2
    call(ctx, 'POST', f"/mobile/claim-proposals/{row['id']}/confirm", 'provider', status=403,
         payload={'expected_version': 1})
    call(ctx, 'POST', f"/mobile/claim-proposals/{row['id']}/claim", 'provider', status=409,
         payload={'expected_version': 1}, key=uuid4().hex)
    version = confirm(ctx, thread, row)
    call(ctx, 'POST', f"/mobile/claim-proposals/{row['id']}/claim", 'customer', status=403,
         payload={'expected_version': version}, key=uuid4().hex)
    key = uuid4().hex
    result = call(ctx, 'POST', f"/mobile/claim-proposals/{row['id']}/claim", 'provider', status=201,
                  payload={'expected_version': version}, key=key)
    assert result['status'] == 'executing'
    assert call(ctx, 'POST', f"/mobile/claim-proposals/{row['id']}/claim", 'provider', status=201,
                payload={'expected_version': version}, key=key) == result
    call(ctx, 'GET', f"/mobile/hall/{record['id']}", 'provider', status=404)
    detail = call(ctx, 'GET', f"/mobile/engagements/{result['engagement_id']}", 'provider')
    assert detail['engagement']['provider_id'] == ctx.actors['provider']['id']
    assert detail['agreements'][0]['quoted_amount'] == 123456
    assert {r['party']: r['confirmed_by'] for r in detail['confirmations']} == {
        'customer': ctx.actors['customer']['id'], 'provider': ctx.actors['provider']['id']}
    delivered, _ = deliver(ctx, result)
    assert delivered['status'] == 'internal_review'


def test_old_proposal_and_withdrawn_publication_cannot_be_claimed(integration_context):
    ctx = integration_context
    record = published_request(ctx)
    thread, old = proposal(ctx, record)
    _, current = proposal(ctx, record)
    call(ctx, 'POST', f"/mobile/claim-proposals/{old['id']}/confirm", 'customer', status=409,
         payload={'expected_version': 1})
    confirm(ctx, thread, current)
    call(ctx, 'POST', f"/admin/requests/{record['id']}/publication/withdraw", payload={
        'expected_version': record['row_version'], 'reason': 'isolated withdrawal verification'})
    call(ctx, 'POST', f"/mobile/claim-proposals/{current['id']}/claim", 'provider', status=404,
         payload={'expected_version': 2}, key=uuid4().hex)


def test_two_providers_cannot_claim_same_request(durable_context):
    ctx = durable_context
    # 独立测试库内给第二账号授予真实内部承接资格；客户端不能自行获得权限。
    for suffix, payload in [('roles', {'role': 'provider', 'reason': 'isolated concurrency test'}),
                            ('provider-authorization', {'reason': 'isolated concurrency test'})]:
        call(ctx, 'POST', f"/admin/accounts/{ctx.actors['stranger']['id']}/{suffix}", payload=payload)
    record = published_request(ctx)
    offers = []
    for actor in ('provider', 'stranger'):
        thread, row = proposal(ctx, record, actor)
        call(ctx, 'POST', f"/mobile/claim-proposals/{row['id']}/confirm", 'customer', payload={'expected_version': 1})
        offers.append((actor, row))
    start = Barrier(2)

    def attempt(offer):
        actor, row = offer
        start.wait(timeout=5)
        return ctx.client.post(f"/api/v1/mobile/claim-proposals/{row['id']}/claim",
            headers={**ctx.headers[actor], 'Idempotency-Key': uuid4().hex}, json={'expected_version': 2})

    with ThreadPoolExecutor(max_workers=2) as executor:
        responses = list(executor.map(attempt, offers))
    assert sorted(r.status_code for r in responses) in ([201, 404], [201, 409])
    assert ctx.connection.execute('SELECT count(*) AS n FROM opc.engagements WHERE request_id=%s AND closed_at IS NULL',
                                  (record['id'],)).fetchone()['n'] == 1
