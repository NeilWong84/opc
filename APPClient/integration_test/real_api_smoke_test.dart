// Runs on Android against a real HTTP service and durable PostgreSQL.
// Administrator credentials are test-only and never imported by lib/main.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/data/api_repository.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/main.dart';

const baseUrl = String.fromEnvironment('OPC_API_BASE_URL');
const runId = String.fromEnvironment('OPC_E2E_RUN');
const customerEmail = String.fromEnvironment('OPC_E2E_CUSTOMER_EMAIL');
const customerPassword = String.fromEnvironment('OPC_E2E_CUSTOMER_PASSWORD');
const providerEmail = String.fromEnvironment('OPC_E2E_PROVIDER_EMAIL');
const providerPassword = String.fromEnvironment('OPC_E2E_PROVIDER_PASSWORD');
const providerId = String.fromEnvironment('OPC_E2E_PROVIDER_ID');
const adminToken = String.fromEnvironment('OPC_E2E_ADMIN_TOKEN');

Future<void> waitForApp(WidgetTester tester, AppController app) async {
  await tester.pump();
  for (var attempt = 0; app.busy && attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(app.busy, isFalse, reason: 'The real HTTP action must finish');
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> waitForKey(WidgetTester tester, String key) async {
  for (
    var attempt = 0;
    find.byKey(Key(key)).evaluate().isEmpty && attempt < 200;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.byKey(Key(key)), findsOneWidget);
  await tester.pumpAndSettle();
}

Future<Map<String, dynamic>> admin(
  String method,
  String path, {
  Map<String, dynamic>? body,
  int status = 200,
}) async {
  final request = http.Request(method, Uri.parse('$baseUrl/api/v1/admin$path'));
  request.headers.addAll({
    'Authorization': 'Bearer $adminToken',
    'Content-Type': 'application/json',
    'Idempotency-Key': '$runId-${DateTime.now().microsecondsSinceEpoch}',
  });
  if (body != null) request.body = jsonEncode(body);
  final client = http.Client();
  try {
    final response = await http.Response.fromStream(await client.send(request));
    expect(
      response.statusCode,
      status,
      reason: '$method $path: ${response.body}',
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> inspectFile(String id) async {
  final file = await admin('GET', '/files/$id');
  await admin(
    'POST',
    '/files/$id/inspection',
    body: {
      'expected_version': file['row_version'],
      'decision': 'clean',
      'reason':
          'Known synthetic UTF-8 test bytes reviewed by this test; no malware scanner claimed.',
    },
  );
}

Future<void> publishDelivery(String engagementId, String deliveryId) async {
  final detail = await admin('GET', '/engagements/$engagementId');
  final reviewed = await admin(
    'POST',
    '/engagements/$engagementId/deliveries/$deliveryId/review',
    body: {
      'expected_version': detail['engagement']['row_version'],
      'decision': 'approved',
      'evidence':
          'Synthetic fixture source, guide and test text inspected for Android integration only.',
    },
  );
  await admin(
    'POST',
    '/engagements/$engagementId/deliveries/$deliveryId/publish',
    body: {'expected_version': reviewed['row_version']},
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android real API: intake, publication, confirmation, files, delivery and acceptance persist',
    (tester) async {
      expect(baseUrl, isNotEmpty);
      expect(
        adminToken,
        isNotEmpty,
        reason:
            'Use the local integration launcher, never production credentials',
      );
      final customer = ApiOpcRepository(baseUrl: baseUrl);
      final provider = ApiOpcRepository(baseUrl: baseUrl);
      final app = AppController(customer);
      addTearDown(app.dispose);
      addTearDown(customer.close);
      addTearDown(provider.close);
      await app.setLocale(const Locale('zh'));

      // A real registration creates a customer only. Then log in through the UI.
      final created = await customer.register(
        'Android 顧客 $runId',
        customerEmail,
        customerPassword,
      );
      expect(created.role, UserRole.customer);
      expect(created.authorized, isFalse);
      await customer.logout();
      await tester.pumpWidget(OpcApp(controller: app));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('login-email')),
        customerEmail,
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        customerPassword,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('auth-submit')));
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      // HTTP processing can complete between frames on a physical device.
      for (
        var attempt = 0;
        customer.session == null && attempt < 100;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(customer.session?.id, created.id);
      expect(find.byType(Banner), findsNothing);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('api-01-customer-home');

      final content = Uint8List.fromList(utf8.encode('非公開の添付・真实字节 $runId'));
      final uploaded = await customer.uploadFile('private-$runId.txt', content);
      expect(uploaded.scanStatus, 'pending');
      await expectLater(
        customer.downloadFile(uploaded.id),
        throwsA(isA<RepositoryException>()),
      );
      // Intake can retain a pending private attachment; publication stays gated.
      final draft = RequestDraft(
        description: '日本国内の予約管理システムを開発したいです。Android 実機経路 $runId',
        timing: '2026-11-15',
        budget: 'JPY 要相談',
        files: [uploaded],
      );
      await customer.saveDraft(draft);
      final freshCustomer = ApiOpcRepository(baseUrl: baseUrl);
      await freshCustomer.login(customerEmail, customerPassword);
      expect(freshCustomer.draft?.description, draft.description);
      expect(freshCustomer.draft?.files.single.id, uploaded.id);
      await freshCustomer.logout();
      freshCustomer.close();
      await app.run(customer.refresh);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('api-new-request')));
      await tester.tap(find.byKey(const Key('api-new-request')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('api-request-description')),
            )
            .controller!
            .text,
        draft.description,
      );
      await tester.ensureVisible(find.byKey(const Key('api-submit-request')));
      await tester.tap(find.byKey(const Key('api-submit-request')));
      for (var attempt = 0; app.busy && attempt < 200; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      final request = customer.myRequests().singleWhere(
        (item) => item.description == draft.description,
      );
      final requestId = request.id;
      expect(request.status, WorkStatus.reviewing);
      await provider.login(providerEmail, providerPassword);
      expect(provider.hall().any((item) => item.id == requestId), isFalse);
      await expectLater(
        provider.refreshItem(requestId),
        throwsA(isA<RepositoryException>()),
      );
      await inspectFile(uploaded.id);
      expect(await customer.downloadFile(uploaded.id), content);
      expect(
        (await customer.previewFile(uploaded.id)).text,
        utf8.decode(content),
      );
      await tap(tester, 'api-item-$requestId');
      await waitForApp(tester, app);
      await tester.ensureVisible(find.text(uploaded.name));
      await tester.tap(find.text(uploaded.name));
      await tester.pump();
      await waitForKey(tester, 'api-file-download');
      await tap(tester, 'api-file-download');
      await waitForKey(tester, 'api-file-open');
      await binding.takeScreenshot('api-04-authenticated-file-saved');
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pumpAndSettle();
      await expectLater(
        provider.downloadFile(uploaded.id),
        throwsA(isA<RepositoryException>()),
      );

      var current = await admin('GET', '/requests/$requestId');
      await admin(
        'POST',
        '/requests/$requestId/clarifications',
        status: 201,
        body: {
          'expected_version': current['row_version'],
          'question': '同じ時間の予約は可能ですか？',
        },
      );
      await customer.refresh();
      expect(customer.detail(requestId).question, '同じ時間の予約は可能ですか？');
      await customer.answerQuestion(requestId, '同じ担当者の同じ時間帯は重複禁止です。');
      current = await admin('GET', '/requests/$requestId');
      expect(current['current_request_version'], 2);
      // Explicitly selected, inspected reference; original private files are not automatic public references.
      // The scope author uploads and selects an explicit public reference.
      final multipart =
          http.MultipartRequest(
              'POST',
              Uri.parse('$baseUrl/api/v1/admin/files'),
            )
            ..headers['Authorization'] = 'Bearer $adminToken'
            ..files.add(
              http.MultipartFile.fromString(
                'file',
                '公開した参照資料 $runId',
                filename: 'published-$runId.txt',
              ),
            );
      final referenceResponse = await http.Response.fromStream(
        await multipart.send(),
      );
      expect(referenceResponse.statusCode, 201);
      final referenceId =
          (jsonDecode(referenceResponse.body) as Map<String, dynamic>)['id']
              as String;
      await inspectFile(referenceId);
      current = await admin(
        'POST',
        '/requests/$requestId/scopes',
        status: 201,
        body: {
          'expected_version': current['row_version'],
          'title': 'Android 予約管理 $runId',
          'public_summary': '日本国内で利用する予約管理の開発。',
          'category': 'Web',
          'goal': '予約の重複を防止',
          'included_scope': '登録と一覧',
          'excluded_scope': '決済',
          'deliverables': ['固定ソース', '操作説明', 'テスト報告'],
          'acceptance_criteria': ['登録が保存される'],
          'duration_text': '2週間',
          'revision_terms': '合意範囲内で修正',
          'file_ids': [referenceId],
        },
      );
      for (final kind in ['compliance', 'technical']) {
        current = await admin(
          'POST',
          '/requests/$requestId/reviews',
          status: 201,
          body: {
            'expected_version': current['row_version'],
            'scope_version': current['current_scope_version'],
            'kind': kind,
            'decision': 'approved',
            'reason': 'Synthetic Android fixture $kind review only',
          },
        );
      }
      current = await admin(
        'POST',
        '/requests/$requestId/publish',
        status: 201,
        body: {
          'expected_version': current['row_version'],
          'scope_version': current['current_scope_version'],
          'reason': 'Publish reviewed synthetic Android fixture',
        },
      );
      await provider.refresh();
      expect(provider.hall().any((item) => item.id == requestId), isTrue);
      expect(
        provider.detail(requestId).attachmentNames,
        isNot(contains(uploaded.name)),
      );
      expect(provider.references(requestId).single.id, referenceId);
      expect(
        utf8.decode(await provider.downloadFile(referenceId)),
        '公開した参照資料 $runId',
      );
      await provider.consult(requestId, '公開範囲について確認します。');
      expect(provider.detail(requestId).engagementId, isNull);

      final engagement = await admin(
        'POST',
        '/engagements',
        status: 201,
        body: {
          'request_id': requestId,
          'provider_id': providerId,
          'expected_version': current['row_version'],
          'terms': '試験用に双方が確認する固定範囲 $runId',
          'reason':
              'Record a synthetic previously-confirmed relationship for Android test',
          'quoted_amount': 100000,
        },
      );
      final engagementId = engagement['engagement_id'] as String;
      await app.run(customer.refresh);
      await provider.refresh();
      expect(customer.detail(requestId).pendingConfirmation, isTrue);
      await tester.pumpAndSettle();
      await tap(tester, 'api-item-$requestId');
      await waitForApp(tester, app);
      await tap(tester, 'api-confirm-agreement');
      await tester.pumpAndSettle();
      await tap(tester, 'api-confirm-dialog');
      await waitForApp(tester, app);
      expect(customer.detail(requestId).confirmedByMe, isTrue);
      await binding.takeScreenshot('api-03-customer-confirmed-terms');
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pumpAndSettle();
      await provider.refreshItem(requestId);
      await provider.confirmAgreement(requestId);
      await customer.refreshItem(requestId);
      expect(customer.detail(requestId).pendingConfirmation, isFalse);

      // A later intake clarification must remain answerable during cooperation.
      current = await admin('GET', '/requests/$requestId');
      await admin(
        'POST',
        '/requests/$requestId/clarifications',
        status: 201,
        body: {
          'expected_version': current['row_version'],
          'question': '開発中の確認：利用者は日本国内だけですか？',
        },
      );
      await app.run(customer.refresh);
      expect(customer.detail(requestId).status, WorkStatus.developing);
      expect(customer.detail(requestId).question, isNotNull);
      await tester.pumpAndSettle();
      await tap(tester, 'api-item-$requestId');
      await waitForApp(tester, app);
      await tester.ensureVisible(find.byKey(const Key('api-message-input')));
      await tester.enterText(
        find.byKey(const Key('api-message-input')),
        'はい、日本国内のみです。',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap(tester, 'api-message-send');
      await waitForApp(tester, app);
      expect(customer.detail(requestId).question, isNull);
      current = await admin('GET', '/requests/$requestId');
      expect(current['current_request_version'], 3);
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pumpAndSettle();
      await provider.sendMessage(requestId, '固定版を準備します。$runId');
      await customer.refreshItem(requestId);
      expect(
        customer
            .detail(requestId)
            .messages
            .any((message) => message.text.contains(runId)),
        isTrue,
      );

      // Submit actual fixed source bytes, then require internal publication before customer visibility.
      final sourceBytes = Uint8List.fromList(
        utf8.encode('print("synthetic source $runId")\n'),
      );
      final source = await provider.uploadFile('source-$runId.py', sourceBytes);
      await inspectFile(source.id);
      Future<void> deliver(int version) async {
        await provider.refreshItem(requestId);
        await provider.submitDelivery(
          requestId,
          Delivery(
            version: version,
            sourceName: source.name,
            sourceRef: '',
            sourceFileId: source.id,
            guideName:
                'Python source fixture; read the text, do not execute automatically.',
            testName:
                'Fixture bytes inspected; business code behavior is not asserted.',
            note: 'Android integration delivery $version',
          ),
        );
      }

      await deliver(1);
      await customer.refreshItem(requestId);
      expect(customer.detail(requestId).deliveries, isEmpty);
      final delivery1 = provider.detail(requestId).deliveries.last;
      await publishDelivery(engagementId, delivery1.id!);
      await customer.refreshItem(requestId);
      expect(customer.detail(requestId).status, WorkStatus.awaitingAcceptance);
      expect(await customer.downloadFile(source.id), sourceBytes);
      await customer.requestRevision(requestId, 1, '操作説明に起動条件を追加してください。');
      await deliver(2);
      final delivery2 = provider.detail(requestId).deliveries.last;
      await publishDelivery(engagementId, delivery2.id!);
      await customer.refreshItem(requestId);
      await expectLater(
        customer.acceptDelivery(requestId, 1),
        throwsA(isA<RepositoryException>()),
      );
      await app.run(customer.refresh);
      await tester.pumpAndSettle();
      await tap(tester, 'api-item-$requestId');
      await waitForApp(tester, app);
      await tap(tester, 'api-accept-delivery');
      await tester.pumpAndSettle();
      await tap(tester, 'api-confirm-dialog');
      await waitForApp(tester, app);
      expect(customer.detail(requestId).status, WorkStatus.completed);
      expect(customer.notifications(), isNotEmpty);
      final notification = customer.notifications().first;
      await customer.markNotificationRead(notification.id);
      expect(
        customer
            .notifications()
            .firstWhere((item) => item.id == notification.id)
            .isRead,
        isTrue,
      );

      // A completely new adapter sees committed data: no singleton/in-memory business dependency.
      final restarted = ApiOpcRepository(baseUrl: baseUrl);
      await restarted.login(customerEmail, customerPassword);
      expect(restarted.detail(requestId).status, WorkStatus.completed);
      expect(restarted.detail(requestId).deliveries.last.version, 2);
      expect(await restarted.downloadFile(source.id), sourceBytes);
      await app.run(customer.refresh);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('api-02-persisted-completed');
      expect(tester.takeException(), isNull);
      binding.reportData = {
        ...?binding.reportData,
        'run_id': runId,
        'request_id': requestId,
        'engagement_id': engagementId,
        'delivery_id': delivery2.id,
        'status': 'completed',
        'source_file_id': source.id,
        'private_file_id': uploaded.id,
        'reference_file_id': referenceId,
      };
      await restarted.logout();
      restarted.close();
      await provider.logout();
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pumpAndSettle();
      await app.run(customer.logout);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-email')), findsOneWidget);
    },
  );
}
