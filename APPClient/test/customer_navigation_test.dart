import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/api_workspace.dart';

import 'api_ui_test.dart' show host, tapKey;
import 'customer_home_ui_test.dart' show HomeRepository, homeRecords;
import 'request_date_picker_helpers.dart';

void main() {
  testWidgets('customer submit shortcut preserves the current request filter', (
    tester,
  ) async {
    final repo = HomeRepository()..records = homeRecords();
    final app = AppController(repo);
    addTearDown(app.dispose);
    await app.setLocale(const Locale('zh'));
    await tester.pumpWidget(host(app, ApiWorkspace(app: app)));
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.cast<NavigationDestination>().map((d) => d.label), [
      '首页',
      '需求',
      '提交需求',
      '沟通记录',
      '个人设置',
    ]);
    for (final status in ['reviewing', 'active', 'acceptance', 'completed']) {
      await tapKey(tester, 'home-stat-$status');
      // The request list contains no repeated submit/review hero card.
      expect(find.text('提交开发需求'), findsNothing);
      expect(find.byKey(const Key('home-new-request')), findsNothing);
      expect(find.byKey(const Key('api-new-request')), findsOneWidget);
      await tapKey(tester, 'tab-0');
    }
    await tapKey(tester, 'home-stat-active');
    await tapKey(tester, 'api-new-request');
    expect(find.byType(ApiRequestPage), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-item-working')), findsOneWidget);
    expect(find.byKey(const Key('api-item-accept')), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tapKey(tester, 'tab-2');
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    await tapKey(tester, 'tab-3');
    expect(find.byKey(const Key('api-logout')), findsOneWidget);
    await tapKey(tester, 'api-new-request');
    await tester.enterText(
      find.byKey(const Key('api-request-description')),
      '客户希望开发日本国内预约管理系统，支持预约登记和查询。',
    );
    await chooseCompletionDate(tester);
    await tester.enterText(
      find.byKey(const Key('api-request-budget')),
      'JPY 要相談',
    );
    await tapKey(tester, 'api-save-draft');
    expect(repo.saved?.description, contains('预约管理系统'));
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await tapKey(tester, 'api-new-request');
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('api-request-description')),
          )
          .controller!
          .text,
      repo.saved!.description,
    );
    await tapKey(tester, 'api-submit-request');
    expect(repo.submitted?.description, repo.saved!.description);
    expect(find.byType(ApiRequestPage), findsNothing);
    expect(find.byKey(const Key('api-logout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ja', 'zh']) {
    for (final brightness in Brightness.values) {
      testWidgets('customer navigation $language $brightness fits 320px', (
        tester,
      ) async {
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
        expect(find.byType(NavigationDestination), findsNWidgets(5));
        expect(find.text(language == 'zh' ? '提交需求' : '依頼する'), findsOneWidget);
        await tapKey(tester, 'tab-2');
        await tapKey(tester, 'api-new-request');
        expect(find.byType(ApiRequestPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('provider has five destinations without customer submit', (
    tester,
  ) async {
    final repo = HomeRepository()
      ..user = const UserSession(
        id: 'provider',
        name: '担当者',
        email: 'p@example.test',
        role: UserRole.provider,
        authorized: true,
      );
    final app = AppController(repo);
    addTearDown(app.dispose);
    await tester.pumpWidget(host(app, ApiWorkspace(app: app)));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.byKey(const Key('api-new-request')), findsNothing);
    await tapKey(tester, 'tab-2');
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    await tapKey(tester, 'tab-4');
    expect(find.byKey(const Key('api-logout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
