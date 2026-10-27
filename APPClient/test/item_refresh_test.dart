import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/features/api_work_page.dart';
import 'package:opc_app/features/api_workspace.dart' show ApiWorkspace;
import 'package:opc_app/data/models.dart';

import 'api_repository_test.dart'
    show Server, requestRow, engagementRow, errorCode, now;
import 'api_ui_test.dart' show LiveUiRepository, host;

class _RefreshCountingRepository extends LiveUiRepository {
  int fullReads = 0;
  int itemReads = 0;
  @override
  Future<void> refresh() async {
    fullReads++;
  }

  @override
  Future<WorkItem> refreshItem(String id) async {
    itemReads++;
    return item;
  }
}

void main() {
  testWidgets('resuming detail never refreshes the hidden workspace account', (
    tester,
  ) async {
    final repo = _RefreshCountingRepository();
    final app = AppController(repo);
    await tester.pumpWidget(host(app, ApiWorkspace(app: app)));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ApiWorkspace))).push(
      MaterialPageRoute<void>(
        builder: (_) => ApiWorkPage(app: app, id: 'request-1'),
      ),
    );
    await tester.pumpAndSettle();
    final fullReads = repo.fullReads;
    final itemReads = repo.itemReads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.fullReads, fullReads);
    expect(repo.itemReads, itemReads + 1);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  test(
    'target recovery does not silently validate a failed account snapshot',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('x', 'y');
      server.unavailable = true;
      await expectLater(
        repo.refresh(),
        throwsA(errorCode('database_unavailable')),
      );
      server.unavailable = false;
      server.requests.clear();
      await repo.refreshItem('request-1');
      expect(repo.detail('request-1').id, 'request-1');
      expect(server.requests, hasLength(4));
      expect(repo.myRequests, throwsA(errorCode('database_unavailable')));
    },
  );
  test(
    'detail fetches only the selected request, without files or account refresh',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('x', 'y');
      server.requests.clear();
      await repo.refreshItem('request-1');
      expect(server.requests.map((r) => r.url.path), [
        '/api/v1/mobile/auth/me',
        '/api/v1/mobile/requests/request-1',
        '/api/v1/mobile/engagements',
        '/api/v1/mobile/threads',
      ]);
      for (final r in server.requests.skip(2)) {
        expect(r.url.queryParameters['request_id'], 'request-1');
      }
    },
  );

  test(
    'detail discovers a new cooperation and reads only its feedback',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('x', 'y');
      server.engagement = engagementRow();
      server.override = (r) {
        if (r.url.path.endsWith('/threads')) {
          return server.json({
            'items': [
              {'id': 'current', 'request_id': 'request-1'},
              {'id': 'unrelated', 'request_id': 'request-2'},
            ],
          });
        }
        if (r.url.path.endsWith('/current/messages')) {
          return server.json({
            'items': [
              {
                'author_id': 'provider-1',
                'body': 'current feedback',
                'sent_at': now,
              },
            ],
          });
        }
        return null;
      };
      server.requests.clear();
      final item = await repo.refreshItem('request-1');
      expect(item.engagementId, 'engagement-1');
      expect(item.messages.single.text, 'current feedback');
      expect(item.messages.single.authorId, 'provider-1');
      expect(
        server.requests.any((r) => r.url.path.contains('unrelated')),
        false,
      );
      expect(
        server.requests.any((r) => r.url.path.endsWith('/notifications')),
        false,
      );
      await repo.refreshItem('request-1');
      expect(repo.detail('request-1').messages, hasLength(1));
    },
  );

  test(
    'failed detail hides old content and retries without refreshing all requests',
    () async {
      final server = Server();
      final repo = server.repo();
      await repo.login('x', 'y');
      server.override = (r) => r.url.path.endsWith('/requests/request-1')
          ? server.failure('NOT_FOUND', 404)
          : null;
      await expectLater(
        repo.refreshItem('request-1'),
        throwsA(errorCode('not_found')),
      );
      expect(() => repo.detail('request-1'), throwsA(errorCode('not_found')));
      server.override = null;
      server.requests.clear();
      expect((await repo.refreshItem('request-1')).id, 'request-1');
      expect(server.requests, hasLength(4));
    },
  );

  test(
    'provider project detail works without requesting private intake or hall',
    () async {
      final server = Server()
        ..provider = true
        ..engagement = engagementRow();
      final repo = server.repo();
      await repo.login('x', 'y');
      server.requests.clear();
      expect(
        (await repo.refreshItem('request-1')).engagementId,
        'engagement-1',
      );
      expect(
        server.requests.any(
          (r) =>
              r.url.path.contains('/requests/') || r.url.path.contains('/hall'),
        ),
        false,
      );
      expect(server.requests[1].url.queryParameters['perspective'], 'provider');
    },
  );

  test('slow detail cannot restore data after logout', () async {
    final server = Server();
    final repo = server.repo();
    await repo.login('x', 'y');
    final started = Completer<void>();
    final response = Completer<http.Response>();
    server.override = (r) {
      if (r.url.path.endsWith('/requests/request-1')) {
        started.complete();
        return response.future;
      }
      return null;
    };
    final pending = repo.refreshItem('request-1');
    await started.future;
    await repo.logout();
    response.complete(server.json(requestRow()));
    await expectLater(pending, throwsA(errorCode('session_changed')));
    expect(repo.session, isNull);
  });

  test('slow detail cannot overwrite a newer full snapshot', () async {
    final server = Server();
    final repo = server.repo();
    await repo.login('x', 'y');
    final started = Completer<void>();
    final response = Completer<http.Response>();
    var first = true;
    server.override = (r) {
      if (first && r.url.path.endsWith('/requests/request-1')) {
        first = false;
        started.complete();
        return response.future;
      }
      return null;
    };
    final pending = repo.refreshItem('request-1');
    await started.future;
    server.row = requestRow(version: 15);
    await repo.refresh();
    response.complete(server.json(requestRow(version: 7)));
    await expectLater(pending, throwsA(errorCode('refresh_superseded')));
    expect(repo.detail('request-1').rowVersion, 15);
  });

  testWidgets(
    'opening during a workspace refresh waits, then leaves the spinner',
    (tester) async {
      final repository = LiveUiRepository();
      final app = AppController(repository);
      final gate = Completer<void>();
      final busy = app.run(() => gate.future);
      await tester.pumpWidget(
        host(app, ApiWorkPage(app: app, id: 'request-1')),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete();
      await busy;
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('顧客原文の予約システム'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
