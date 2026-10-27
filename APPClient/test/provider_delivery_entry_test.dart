import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/api_workspace.dart';

import 'api_ui_test.dart' show LiveUiRepository, host, record, tapKey;

const provider = UserSession(
  id: 'provider-1',
  name: '承接者',
  email: 'provider@example.jp',
  role: UserRole.provider,
  authorized: true,
);

class EntryRepository extends LiveUiRepository {
  EntryRepository() {
    user = provider;
  }

  int itemReads = 0;
  WorkItem? refreshedItem;
  bool failItemRead = false;

  @override
  Future<WorkItem> refreshItem(String id) async {
    itemReads++;
    if (failItemRead) {
      throw const RepositoryException('network_unavailable', 'Offline');
    }
    return item = refreshedItem ?? item;
  }
}

void main() {
  test(
    'delivery requires active authorized current provider and executable project',
    () {
      expect(record().canSubmitDeliveryBy(provider), isTrue);
      expect(
        record()
            .copyWith(status: WorkStatus.revision)
            .canSubmitDeliveryBy(provider),
        isTrue,
      );
      for (final status in [
        WorkStatus.reviewing,
        WorkStatus.published,
        WorkStatus.internalReview,
        WorkStatus.awaitingAcceptance,
        WorkStatus.completed,
      ]) {
        expect(
          record().copyWith(status: status).canSubmitDeliveryBy(provider),
          isFalse,
        );
      }
      expect(record(pending: true).canSubmitDeliveryBy(provider), isFalse);
      expect(record().canSubmitDeliveryBy(null), isFalse);
      for (final user in [
        const UserSession(
          id: 'provider-1',
          name: '',
          email: '',
          role: UserRole.customer,
          authorized: true,
        ),
        const UserSession(
          id: 'other',
          name: '',
          email: '',
          role: UserRole.provider,
          authorized: true,
        ),
        const UserSession(
          id: 'provider-1',
          name: '',
          email: '',
          role: UserRole.provider,
        ),
        const UserSession(
          id: 'provider-1',
          name: '',
          email: '',
          role: UserRole.provider,
          authorized: true,
          active: false,
        ),
      ]) {
        expect(record().canSubmitDeliveryBy(user), isFalse);
      }
      final hallItem = WorkItem(
        id: 'hall',
        title: '',
        description: '',
        category: 'development',
        duration: '',
        status: WorkStatus.developing,
        ownerId: 'customer-1',
        providerId: provider.id,
        createdAt: DateTime.utc(2026),
      );
      expect(hallItem.canSubmitDeliveryBy(provider), isFalse);
    },
  );

  for (final locale in ['zh', 'ja']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '$locale $brightness project and message entries open delivery after fresh read',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = EntryRepository();
          final app = AppController(repo);
          addTearDown(app.dispose);
          await app.setLocale(Locale(locale));
          await tester.pumpWidget(
            host(app, ApiWorkspace(app: app), brightness: brightness),
          );
          await tester.pumpAndSettle();
          const entry = 'api-item-delivery-request-1';
          expect(find.byKey(const Key(entry)), findsNothing); // 大厅不新增交付入口。
          for (final tab in [2, 3]) {
            await tapKey(tester, 'tab-$tab');
            expect(
              find.text(locale == 'zh' ? '提交交付物' : '納品物を提出'),
              findsOneWidget,
            );
            final before = repo.itemReads;
            await tapKey(tester, entry);
            expect(repo.itemReads, before + 1);
            expect(find.byType(ApiDeliveryPage), findsOneWidget);
            expect(
              find.byKey(const Key('api-source-repository')),
              findsOneWidget,
            );
            await tester.tap(find.byIcon(Icons.chevron_left));
            await tester.pumpAndSettle();
            expect(find.byType(ApiDeliveryPage), findsNothing); // 返回不再次自动打开。
            expect(repo.itemReads, before + 2);
            await tester.tap(find.byIcon(Icons.chevron_left));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'stale project entry cannot open delivery once internal review begins',
    (tester) async {
      final repo = EntryRepository()
        ..refreshedItem = record().copyWith(status: WorkStatus.internalReview);
      final app = AppController(repo);
      addTearDown(app.dispose);
      await tester.pumpWidget(host(app, ApiWorkspace(app: app)));
      await tapKey(tester, 'tab-2');
      await tapKey(tester, 'api-item-delivery-request-1');
      expect(find.byType(ApiDeliveryPage), findsNothing);
      expect(find.byKey(const Key('api-open-delivery')), findsNothing);
      expect(find.byType(ApiWorkPage), findsOneWidget);
    },
  );

  testWidgets(
    'failed fresh read shows retry and never opens a stale delivery form',
    (tester) async {
      final repo = EntryRepository()..failItemRead = true;
      final app = AppController(repo);
      addTearDown(app.dispose);
      await tester.pumpWidget(host(app, ApiWorkspace(app: app)));
      await tapKey(tester, 'tab-3');
      await tapKey(tester, 'api-item-delivery-request-1');
      expect(find.byType(ApiDeliveryPage), findsNothing);
      expect(find.text('再試行'), findsOneWidget);
      repo.failItemRead = false;
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(find.byType(ApiDeliveryPage), findsOneWidget);
    },
  );
}
