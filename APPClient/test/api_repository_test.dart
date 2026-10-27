import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opc_app/data/api_repository.dart';
import 'package:opc_app/data/models.dart';

const now = '2026-10-16T10:00:00+09:00';
Map<String, dynamic> requestRow({int version = 7}) => {
  'id': 'request-1',
  'public_code': 'REQ-1001',
  'row_version': version,
  'intake_status': 'submitted',
  'current_request_version': 1,
  'current_scope_version': null,
  'created_at': now,
  'original': {
    'original_description': '客户原文を保持した開発依頼です',
    'timing_text': '2026年11月',
    'budget_text': 'JPY 要相談',
  },
  'scope': null,
  'private_files': [fileRow()],
  'reviews': [],
  'clarifications': [],
  'publications': [],
};
Map<String, dynamic> fileRow({String scan = 'pending'}) => {
  'id': 'file-1',
  'original_name': '資料.txt',
  'size_bytes': 12,
  'media_type': 'text/plain',
  'scan_status': scan,
  'upload_status': 'ready',
  'sha256': 'abc',
};
Map<String, dynamic> engagementRow({
  String status = 'executing',
  dynamic amount = '100000',
}) => {
  'engagement': {
    'id': 'engagement-1',
    'request_id': 'request-1',
    'public_code': 'REQ-1001',
    'customer_id': 'customer-1',
    'provider_id': 'provider-1',
    'status': status,
    'row_version': 12,
    'created_at': now,
  },
  'agreements': [
    {
      'version': 3,
      'scope_version': 2,
      'terms': '双方確認用条款',
      'quoted_amount': amount,
      'scope': {
        'title': '予約管理',
        'goal': '予約を管理する',
        'included_scope': '入力と保存',
        'excluded_scope': '決済',
        'deliverables': ['ソース'],
        'acceptance_criteria': ['保存できる'],
        'revision_terms': '1回',
        'duration_text': '2週間',
        'reference_files': [],
      },
    },
  ],
  'confirmations': [],
  'deliveries': [],
  'acceptances': [],
};

class Server {
  bool provider = false;
  bool unauthorized = false;
  bool unavailable = false;
  Map<String, dynamic>? engagement;
  Map<String, dynamic> row = requestRow();
  Map<String, dynamic>? savedDraft;
  final requests = <http.Request>[];
  FutureOr<http.Response?> Function(http.Request)? override;
  http.Response json(Object body, [int code = 200]) => http.Response(
    jsonEncode(body),
    code,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  http.Response failure(String code, int status) => json({
    'error': {'code': code, 'message': 'service error'},
  }, status);
  late final client = MockClient((request) async {
    requests.add(request);
    final replacement = await override?.call(request);
    if (replacement != null) return replacement;
    final path = request.url.path.replaceFirst('/api/v1/', '');
    if (path == 'mobile/auth/login') {
      return json({'access_token': 'session-secret', 'audience': 'mobile'});
    }
    if (unauthorized) return failure('SESSION_REVOKED', 401);
    if (unavailable) return failure('DATABASE_UNAVAILABLE', 503);
    if (path == 'mobile/auth/me') {
      return json({
        'id': provider ? 'provider-1' : 'customer-1',
        'display_name': '日本語 Name',
        'email': provider ? 'member@example.test' : 'client@example.test',
        'roles': [provider ? 'provider' : 'customer'],
        'status': 'active',
        'internally_authorized': provider,
      });
    }
    if (path == 'mobile/auth/logout') return json({'revoked': true});
    if (path == 'mobile/draft' && request.method == 'GET') {
      return json({'draft': savedDraft});
    }
    if (path == 'mobile/draft' && request.method == 'PUT') {
      savedDraft = {
        ...jsonDecode(request.body) as Map<String, dynamic>,
        'row_version': 1,
        'files': [fileRow()],
      };
      return json({'draft': savedDraft});
    }
    if (path == 'mobile/requests' && request.method == 'POST') {
      return json(row, 201);
    }
    if (path == 'mobile/requests') {
      return json({
        'items': [
          {'id': 'request-1'},
        ],
        'total': 1,
      });
    }
    if (path == 'mobile/requests/request-1') return json(row);
    if (path == 'mobile/engagements') {
      return json({
        'items': engagement == null
            ? []
            : [
                {'id': 'engagement-1', 'request_id': 'request-1'},
              ],
      });
    }
    if (path == 'mobile/engagements/engagement-1') return json(engagement!);
    if (path == 'mobile/threads' || path == 'mobile/hall') {
      return json({'items': []});
    }
    if (path == 'mobile/notifications') {
      return json({
        'items': [
          {
            'id': 'notification-1',
            'template_key': 'request.submitted',
            'parameters': {'request_id': 'request-1'},
            'created_at': now,
            'read_at': null,
          },
        ],
      });
    }
    return failure('NOT_FOUND', 404);
  });
  ApiOpcRepository repo() =>
      ApiOpcRepository(baseUrl: 'http://localhost:8001', client: client);
}

Matcher errorCode(String code) =>
    isA<RepositoryException>().having((e) => e.code, 'code', code);

void main() {
  test(
    'message adapter preserves trusted sender identity for customer feedback',
    () async {
      final server = Server()..engagement = engagementRow();
      server.override = (request) {
        if (request.url.path.endsWith('/mobile/threads')) {
          return server.json({
            'items': [
              {'id': 'thread-1', 'request_id': 'request-1'},
            ],
          });
        }
        if (request.url.path.endsWith('/mobile/threads/thread-1/messages')) {
          return server.json({
            'items': [
              {
                'author_id': 'provider-1',
                'author_name': '担当者',
                'body': '確認をお願いします',
                'sent_at': now,
              },
            ],
          });
        }
        return null;
      };
      final repo = server.repo();
      await repo.login('x', 'y');
      final message = repo.detail('request-1').messages.single;
      expect(message.authorId, 'provider-1');
      expect(message.author, '担当者');
      expect(message.text, '確認をお願いします');
    },
  );
  test(
    'active cooperation preserves customer intake clarification and its request version',
    () async {
      final server = Server()..engagement = engagementRow();
      server.row = {
        ...requestRow(),
        'intake_status': 'needs_info',
        'clarifications': [
          {
            'id': 'clarification-1',
            'question': '既存予約の移行は必要ですか？',
            'answer': null,
          },
        ],
      };
      final repo = server.repo();
      await repo.login('x', 'y');
      expect(repo.detail('request-1').status, WorkStatus.developing);
      expect(repo.detail('request-1').question, '既存予約の移行は必要ですか？');
      server.override = (r) {
        if (r.url.path.endsWith('/clarifications/clarification-1/answer')) {
          expect(jsonDecode(r.body), {
            'answer': 'はい、必要です。',
            'expected_version': 7,
          });
          server.row = requestRow(version: 8);
          return server.json(server.row);
        }
        return null;
      };
      await repo.answerQuestion('request-1', 'はい、必要です。');
      expect(repo.detail('request-1').question, isNull);
      expect(repo.detail('request-1').status, WorkStatus.developing);
    },
  );

  test(
    'review rejection and cancelled cooperation are never reported as completed work',
    () async {
      final server = Server();
      server.row = {
        ...requestRow(),
        'intake_status': 'closed',
        'current_scope_version': 2,
        'reviews': [
          {'scope_version': 2, 'kind': 'compliance', 'decision': 'rejected'},
        ],
      };
      final repo = server.repo();
      await repo.login('x', 'y');
      expect(repo.detail('request-1').intakeState, 'rejected');
      expect(repo.detail('request-1').status, isNot(WorkStatus.completed));
      server.row = {...requestRow(), 'intake_status': 'withdrawn'};
      await repo.refresh();
      expect(repo.detail('request-1').intakeState, 'withdrawn');
      server.engagement = engagementRow(status: 'cancelled');
      await repo.refresh();
      expect(repo.detail('request-1').intakeState, 'cancelled');
      expect(repo.detail('request-1').status, isNot(WorkStatus.completed));
    },
  );

  test(
    'a slower previous login cannot erase the newer authenticated account',
    () async {
      final server = Server();
      final firstStarted = Completer<void>();
      final oldLogin = Completer<http.Response>();
      var first = true;
      server.override = (r) {
        if (r.url.path.endsWith('/auth/login') && first) {
          first = false;
          firstStarted.complete();
          return oldLogin.future;
        }
        return null;
      };
      final repo = server.repo();
      final old = repo.login('old@example.test', 'old password');
      await firstStarted.future;
      await repo.login('new@example.test', 'new password');
      oldLogin.complete(
        server.json({'access_token': 'old-secret', 'audience': 'mobile'}),
      );
      await expectLater(old, throwsA(errorCode('session_changed')));
      expect(repo.session, isNotNull);
      expect(repo.myRequests().single.id, 'request-1');
      await repo.refresh();
      expect(
        server.requests.last.headers['Authorization'],
        'Bearer session-secret',
      );
    },
  );

  test(
    'a slower earlier refresh cannot replace the newer server snapshot',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('x', 'y');
      final oldReachedEnd = Completer<void>();
      final oldNotifications = Completer<http.Response>();
      var first = true;
      server.override = (r) {
        if (r.url.path.endsWith('/notifications') && first) {
          first = false;
          oldReachedEnd.complete();
          return oldNotifications.future;
        }
        return null;
      };
      final old = repo.refresh();
      await oldReachedEnd.future;
      server.row = {
        ...requestRow(),
        'original': {
          'original_description': '最新版本の実際の内容',
          'timing_text': '11月',
          'budget_text': 'JPY',
        },
      };
      await repo.refresh();
      oldNotifications.complete(server.json({'items': []}));
      await expectLater(old, throwsA(errorCode('refresh_superseded')));
      expect(repo.detail('request-1').description, '最新版本の実際の内容');
    },
  );

  test(
    'mobile login hydrates actual private data and never requests an admin or customer hall route',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('client@example.test', 'a valid password');
      expect(repo.myRequests().single.id, 'request-1');
      expect(repo.detail('request-1').files.single.scanStatus, 'pending');
      expect(repo.detail('request-1').description, '客户原文を保持した開発依頼です');
      expect(repo.notifications().single.parameters['request_id'], 'request-1');
      expect(
        server.requests.any((r) => r.url.path.contains('/admin/')),
        isFalse,
      );
      expect(server.requests.any((r) => r.url.path.endsWith('/hall')), isFalse);
      for (final r in server.requests.skip(1)) {
        expect(r.headers['Authorization'], 'Bearer session-secret');
      }
      expect(server.requests.first.headers['Authorization'], isNull);
    },
  );

  test(
    'revoked sessions immediately discard private snapshots and draft',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('x', 'y');
      server.unauthorized = true;
      await expectLater(repo.refresh(), throwsA(errorCode('unauthenticated')));
      expect(repo.session, isNull);
      expect(repo.draft, isNull);
      expect(
        () => repo.detail('request-1'),
        throwsA(errorCode('unauthenticated')),
      );
    },
  );

  test(
    'failed refresh blocks stale reads and a successful retry restores the snapshot',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('x', 'y');
      server.unavailable = true;
      await expectLater(
        repo.refresh(),
        throwsA(errorCode('database_unavailable')),
      );
      expect(repo.myRequests, throwsA(errorCode('database_unavailable')));
      server.unavailable = false;
      await repo.refresh();
      expect(repo.myRequests().length, 1);
    },
  );

  test('lost create response reuses exact idempotency key and body', () async {
    final server = Server();
    final repo = server.repo();
    await repo.login('x', 'y');
    var attempts = 0;
    server.override = (r) {
      if (r.method == 'POST' && r.url.path.endsWith('/requests')) {
        if (attempts++ == 0) throw http.ClientException('response lost');
      }
      return null;
    };
    final draft = RequestDraft(
      description: '真实需求内容必须保持原文',
      timing: '11月',
      budget: 'JPY 10000',
    );
    await expectLater(
      repo.submitRequest(draft),
      throwsA(errorCode('network_unavailable')),
    );
    await repo.submitRequest(draft);
    final posts = server.requests
        .where((r) => r.method == 'POST' && r.url.path.endsWith('/requests'))
        .toList();
    expect(posts.length, 2);
    expect(
      posts[0].headers['Idempotency-Key'],
      posts[1].headers['Idempotency-Key'],
    );
    expect(posts[0].body, posts[1].body);
  });

  test(
    'mutation success followed by refresh failure still retries original idempotent command',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('x', 'y');
      var failRead = false;
      server.override = (r) {
        if (r.method == 'POST' && r.url.path.endsWith('/requests')) {
          failRead = true;
          return server.json(server.row, 201);
        }
        if (failRead && r.url.path.endsWith('/auth/me')) {
          return server.failure('NOT_FOUND', 404);
        }
        return null;
      };
      final draft = RequestDraft(
        description: 'lost refresh after committed request',
      );
      await expectLater(
        repo.submitRequest(draft),
        throwsA(errorCode('not_found')),
      );
      server.override = null;
      await repo.submitRequest(draft);
      final posts = server.requests
          .where((r) => r.method == 'POST' && r.url.path.endsWith('/requests'))
          .toList();
      expect(
        posts[0].headers['Idempotency-Key'],
        posts[1].headers['Idempotency-Key'],
      );
    },
  );

  test(
    'string Decimal JPY and full agreed scope map without treating confirmation as execution',
    () async {
      final server = Server()
        ..engagement = engagementRow(status: 'pending_confirmation');
      final repo = server.repo();
      await repo.login('x', 'y');
      final item = repo.detail('request-1');
      expect(item.quotedAmount, 100000);
      expect(item.pendingConfirmation, isTrue);
      expect(item.confirmedByMe, isFalse);
      expect(item.scope['excluded_scope'], '決済');
      expect(item.files.single.id, 'file-1');
      server.override = (r) => r.url.path.endsWith('/agreements/3/confirm')
          ? server.json({'status': 'pending_confirmation'})
          : null;
      await repo.confirmAgreement(item.id);
      final post = server.requests.lastWhere(
        (r) => r.url.path.endsWith('/confirm'),
      );
      expect(jsonDecode(post.body), {'expected_version': 12});
    },
  );

  test(
    'fractional JPY is rejected rather than rounded or coerced to zero',
    () async {
      final server = Server()..engagement = engagementRow(amount: '1.5');
      final repo = server.repo();
      await expectLater(
        repo.login('x', 'y'),
        throwsA(errorCode('invalid_response')),
      );
      expect(repo.session, isNull);
    },
  );

  test(
    'delivery retry retains original expected_version after a refreshed state',
    () async {
      final server = Server()
        ..provider = true
        ..engagement = engagementRow();
      final repo = server.repo();
      await repo.login('x', 'y');
      var attempts = 0;
      server.override = (r) {
        if (r.method == 'POST' && r.url.path.endsWith('/deliveries')) {
          if (attempts++ == 0) throw http.ClientException('response lost');
          return server.json({'delivery_id': 'delivery-1'}, 201);
        }
        return null;
      };
      const delivery = Delivery(
        version: 1,
        sourceName: 'source',
        sourceRef: 'abcdef',
        guideName: '本当に実行した手順',
        testName: '実際のテスト結果',
        note: '原文',
        repositoryUrl: 'https://example.test/repo',
        sourceArchiveRef: 'archive evidence',
      );
      await expectLater(
        repo.submitDelivery('request-1', delivery),
        throwsA(errorCode('network_unavailable')),
      );
      (server.engagement!['engagement'] as Map)['row_version'] = 15;
      await repo.refresh();
      await repo.submitDelivery('request-1', delivery);
      final posts = server.requests
          .where(
            (r) => r.method == 'POST' && r.url.path.endsWith('/deliveries'),
          )
          .toList();
      expect(jsonDecode(posts.last.body)['expected_version'], 12);
      expect(
        posts.first.headers['Idempotency-Key'],
        posts.last.headers['Idempotency-Key'],
      );
      expect(jsonDecode(posts.last.body)['guide_text'], '本当に実行した手順');
    },
  );

  test(
    'real uploads carry bytes and preserve pending inspection; unsupported preview is explicit',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('x', 'y');
      server.override = (r) {
        if (r.method == 'POST' && r.url.path.endsWith('/files')) {
          expect(r.headers['content-type'], contains('multipart/form-data'));
          expect(utf8.decode(r.bodyBytes), contains('真实文件字节'));
          return server.json(fileRow(), 201);
        }
        if (r.url.path.endsWith('/preview')) {
          return server.json({
            'state': 'unsupported',
            'error_code': 'PREVIEW_CONVERTER_NOT_CONFIGURED',
          });
        }
        if (r.url.path.endsWith('/download')) {
          return server.failure('FILE_NOT_CLEARED', 409);
        }
        return null;
      };
      final uploaded = await repo.uploadFile(
        '資料.txt',
        Uint8List.fromList(utf8.encode('真实文件字节')),
      );
      expect(uploaded.isReady, isFalse);
      await repo.saveDraft(
        RequestDraft(description: '本物の添付', files: [uploaded]),
      );
      final saved = server.requests.lastWhere((r) => r.method == 'PUT');
      expect(jsonDecode(saved.body)['file_ids'], ['file-1']);
      final preview = await repo.previewFile(uploaded.id);
      expect(preview.state, ReferencePreviewState.unsupported);
      expect(preview.bytes, isNull);
      expect(preview.text, isEmpty);
      await expectLater(
        repo.downloadFile(uploaded.id),
        throwsA(errorCode('file_not_cleared')),
      );
    },
  );

  test(
    'list pagination does not truncate messages or notifications at 100 records',
    () async {
      final server = Server();
      server.override = (r) {
        if (r.url.path.endsWith('/notifications')) {
          final offset = int.parse(r.url.queryParameters['offset']!);
          return server.json({
            'items': List.generate(
              offset == 0 ? 100 : 1,
              (i) => {
                'id': '${offset + i}',
                'template_key': 'request.submitted',
                'parameters': {},
                'created_at': now,
              },
            ),
          });
        }
        return null;
      };
      final repo = server.repo();
      await repo.login('x', 'y');
      expect(repo.notifications().length, 101);
      expect(
        server.requests
            .where((r) => r.url.path.endsWith('/notifications'))
            .map((r) => r.url.queryParameters['offset']),
        ['0', '100'],
      );
    },
  );

  test(
    'offline logout removes token but propagates failed revocation',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('x', 'y');
      server.unavailable = true;
      await expectLater(
        repo.logout(),
        throwsA(errorCode('database_unavailable')),
      );
      expect(repo.session, isNull);
      expect(repo.myRequests, throwsA(errorCode('unauthenticated')));
    },
  );

  test(
    'a response from the previous account cannot repopulate a cleared session',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('x', 'y');
      final received = Completer<void>();
      final delayed = Completer<http.Response>();
      server.override = (r) {
        if (r.url.path.endsWith('/auth/me')) {
          received.complete();
          return delayed.future;
        }
        return null;
      };
      final pending = repo.refresh();
      await received.future;
      await repo.logout();
      delayed.complete(
        server.json({
          'id': 'customer-1',
          'display_name': 'old',
          'email': 'old@example.test',
          'roles': ['customer'],
          'status': 'active',
          'internally_authorized': false,
        }),
      );
      await expectLater(pending, throwsA(errorCode('session_changed')));
      expect(repo.session, isNull);
    },
  );
}
