import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/api_workspace.dart';

import 'api_ui_test.dart' show host, tapKey;
import 'customer_home_ui_test.dart' show HomeRepository;
import 'request_date_picker_helpers.dart';

const catalog = RequestClassifications(
  platforms: [
    RequestClassification(code: 'web', nameZh: 'Web开发', nameJa: 'Webアプリ開発'),
    RequestClassification(
      code: 'android',
      nameZh: 'Android开发',
      nameJa: 'Androidアプリ開発',
    ),
  ],
  developmentTypes: [
    RequestClassification(code: 'crm', nameZh: 'CRM', nameJa: '顧客管理（CRM）'),
    RequestClassification(code: 'hr', nameZh: 'HR人力系统', nameJa: '人事管理システム（HR）'),
  ],
);

class ClassificationRepository extends HomeRepository {
  bool failCatalog = false;
  @override
  Future<RequestClassifications> requestClassifications() async {
    if (failCatalog) {
      throw const RepositoryException('network_error', 'offline');
    }
    return catalog;
  }
}

WorkItem classified(String id, String? platform, String? type) => WorkItem(
  id: id,
  title: id,
  description: '客户原文不随分类显示语言变化。',
  category: 'development',
  duration: '',
  status: WorkStatus.reviewing,
  ownerId: 'customer-1',
  createdAt: DateTime.utc(2026),
  platformCode: platform,
  developmentTypeCode: type,
);

Future<void> select(WidgetTester tester, String prefix, String label) async {
  final field = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        w.key.toString().contains(prefix),
  );
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'combined classification filters preserve all and unclassified requests',
    (tester) async {
      final repo = ClassificationRepository()
        ..records = [
          classified('web-crm', 'web', 'crm'),
          classified('web-hr', 'web', 'hr'),
          classified('android-crm', 'android', 'crm'),
          classified('legacy', null, null),
        ];
      final app = AppController(repo);
      addTearDown(app.dispose);
      await app.setLocale(const Locale('zh'));
      await tester.pumpWidget(host(app, ApiWorkspace(app: app)));
      await tester.pumpAndSettle();
      await tapKey(tester, 'tab-1');
      await select(tester, 'classification-platform', 'Web开发');
      expect(find.byKey(const Key('api-item-web-crm')), findsOneWidget);
      expect(find.byKey(const Key('api-item-android-crm')), findsNothing);
      await select(tester, 'classification-type', 'CRM');
      expect(find.byKey(const Key('api-item-web-hr')), findsNothing);
      await tapKey(tester, 'api-new-request');
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('api-item-web-crm')), findsOneWidget);
      expect(find.byKey(const Key('api-item-web-hr')), findsNothing);
      await tapKey(tester, 'classification-clear');
      expect(find.byKey(const Key('api-item-legacy')), findsOneWidget);
      await select(tester, 'classification-platform', '未分类');
      expect(find.byKey(const Key('api-item-legacy')), findsOneWidget);
      expect(find.byKey(const Key('api-item-web-crm')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'classified draft restores stable codes across UI languages and submits',
    (tester) async {
      final repo = ClassificationRepository();
      final app = AppController(repo);
      addTearDown(app.dispose);
      await app.setLocale(const Locale('zh'));
      await tester.pumpWidget(host(app, ApiWorkspace(app: app)));
      await tester.pumpAndSettle();
      await tapKey(tester, 'api-new-request');
      await select(tester, 'classification-platform', 'Web开发');
      await select(tester, 'classification-type', 'CRM');
      await tester.enterText(
        find.byKey(const Key('api-request-description')),
        '开发内部客户资料查询系统，保留中文原文。',
      );
      await chooseCompletionDate(tester);
      await tester.enterText(
        find.byKey(const Key('api-request-budget')),
        'JPY 要相談',
      );
      await tapKey(tester, 'api-save-draft');
      expect(repo.saved!.platformCode, 'web');
      expect(repo.saved!.developmentTypeCode, 'crm');
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      await app.setLocale(const Locale('ja'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'api-new-request');
      expect(find.text('Webアプリ開発'), findsWidgets);
      expect(find.text('顧客管理（CRM）'), findsWidgets);
      await tapKey(tester, 'api-submit-request');
      expect(repo.submitted!.platformCode, 'web');
      expect(repo.submitted!.developmentTypeCode, 'crm');
      expect(repo.submitted!.description, contains('保留中文原文'));
      expect(find.byType(ApiRequestPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ja', 'zh']) {
    for (final brightness in Brightness.values) {
      testWidgets('classification fields fit $language $brightness at 320px', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 740);
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final app = AppController(ClassificationRepository());
        addTearDown(app.dispose);
        await app.setLocale(Locale(language));
        await tester.pumpWidget(
          host(app, ApiWorkspace(app: app), brightness: brightness),
        );
        await tester.pumpAndSettle();
        await tapKey(tester, 'tab-1');
        await select(
          tester,
          'classification-type',
          language == 'zh' ? 'HR人力系统' : '人事管理システム（HR）',
        );
        await tapKey(tester, 'api-new-request');
        await select(
          tester,
          'classification-platform',
          language == 'zh' ? 'Android开发' : 'Androidアプリ開発',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
