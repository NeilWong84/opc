import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/api_workspace.dart';

import 'api_ui_test.dart' show LiveUiRepository, host, tapKey;
import 'customer_overview_test.dart' show overviewItem, visibleDelivery;

class HomeRepository extends LiveUiRepository {
  List<WorkItem> records = [];
  @override
  List<WorkItem> myRequests() {
    super.myRequests(); // 保留离线读取失败语义。
    return records;
  }

  @override
  WorkItem detail(String id) => records.firstWhere((item) => item.id == id);
  @override
  Future<WorkItem> refreshItem(String id) async {
    await refresh();
    return detail(id);
  }
}

List<WorkItem> homeRecords() => [
  overviewItem('review', owner: 'customer-1', question: '请确认使用人数'),
  overviewItem(
    'working',
    owner: 'customer-1',
    project: true,
    status: WorkStatus.developing,
    messages: [
      ChatMessage(
        author: '担当者',
        authorId: 'provider',
        text: '画面の実装が完了しました。',
        sentAt: DateTime.utc(2026, 10, 25, 9),
      ),
      ChatMessage(
        author: '客户',
        authorId: 'customer-1',
        text: '自己的消息不充当反馈',
        sentAt: DateTime.utc(2026, 10, 25, 10),
      ),
    ],
  ),
  overviewItem(
    'accept',
    owner: 'customer-1',
    project: true,
    status: WorkStatus.awaitingAcceptance,
    deliveries: [visibleDelivery],
  ),
];

void main() {
  testWidgets(
    'home is a dashboard; metric opens filtered requests and bottom tab resets it',
    (tester) async {
      final repo = HomeRepository()..records = homeRecords();
      final app = AppController(repo);
      addTearDown(app.dispose);
      await app.setLocale(const Locale('zh'));
      await tester.pumpWidget(host(app, ApiWorkspace(app: app)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer-overview')), findsOneWidget);
      expect(find.byKey(const Key('api-item-review')), findsNothing);
      expect(find.text('我的项目总览'), findsOneWidget);
      expect(
        find.byKey(const Key('home-todo-review-clarification')),
        findsOneWidget,
      );
      await tapKey(tester, 'home-stat-acceptance');
      expect(find.byKey(const Key('customer-overview')), findsNothing);
      expect(find.byKey(const Key('api-item-accept')), findsOneWidget);
      expect(find.byKey(const Key('api-item-working')), findsNothing);
      await tapKey(tester, 'home-clear-filter');
      expect(find.byKey(const Key('api-item-working')), findsOneWidget);
      await tapKey(tester, 'tab-0');
      await tapKey(tester, 'home-stat-active');
      expect(find.byKey(const Key('api-item-working')), findsOneWidget);
      expect(find.byKey(const Key('api-item-accept')), findsNothing);
      await tapKey(tester, 'tab-1');
      expect(find.byKey(const Key('api-item-accept')), findsOneWidget);
    },
  );

  testWidgets(
    'feedback opens existing conversation, return refreshes overview',
    (tester) async {
      final repo = HomeRepository()..records = homeRecords();
      final app = AppController(repo);
      addTearDown(app.dispose);
      await tester.pumpWidget(host(app, ApiWorkspace(app: app)));
      await tester.pumpAndSettle();
      expect(find.text('自己的消息不充当反馈'), findsNothing);
      final feedback = find.byKey(
        const Key('home-feedback-working-2026-10-25T09:00:00.000Z'),
      );
      await tester.ensureVisible(feedback);
      await tester.tap(feedback);
      await tester.pumpAndSettle();
      expect(find.byType(ApiWorkPage), findsOneWidget);
      expect(
        tester.widget<ApiWorkPage>(find.byType(ApiWorkPage)).showMessages,
        isTrue,
      );
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer-overview')), findsOneWidget);
      repo.offline = true;
      await tapKey(tester, 'api-refresh');
      expect(find.byKey(const Key('customer-overview')), findsNothing);
      expect(find.textContaining('サーバーに接続できません'), findsOneWidget);
    },
  );

  for (final language in ['ja', 'zh']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'customer overview $language $brightness fits 320px with large text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 740);
          tester.platformDispatcher.textScaleFactorTestValue = 1.4;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final repo = HomeRepository()..records = homeRecords();
          final app = AppController(repo);
          addTearDown(app.dispose);
          await app.setLocale(Locale(language));
          await tester.pumpWidget(
            host(app, ApiWorkspace(app: app), brightness: brightness),
          );
          await tester.pumpAndSettle();
          expect(find.text('画面の実装が完了しました。'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'new customer sees onboarding; provider overview links to the task hall',
    (tester) async {
      final repo = HomeRepository();
      final app = AppController(repo);
      addTearDown(app.dispose);
      await app.setLocale(const Locale('zh'));
      await tester.pumpWidget(host(app, ApiWorkspace(app: app)));
      await tester.pumpAndSettle();
      expect(find.text('从第一个需求开始'), findsOneWidget);
      expect(find.byKey(const Key('home-stat-active')), findsOneWidget);
      repo.user = const UserSession(
        id: 'provider',
        name: '担当者',
        email: 'p@example.test',
        role: UserRole.provider,
        authorized: true,
      );
      app.syncSession();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer-overview')), findsNothing);
      expect(find.byKey(const Key('provider-overview')), findsOneWidget);
      await tapKey(tester, 'provider-open-hall');
      expect(find.byKey(const Key('api-hall-search')), findsOneWidget);
    },
  );
}
