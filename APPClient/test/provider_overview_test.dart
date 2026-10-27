import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/data/provider_overview.dart';
import 'package:opc_app/features/api_workspace.dart';

import 'api_ui_test.dart' show host, tapKey;
import 'provider_delivery_entry_test.dart' show EntryRepository, provider;

WorkItem project(
  String id, {
  bool assigned = true,
  WorkStatus status = WorkStatus.developing,
  String providerId = 'provider-1',
  String state = '',
  bool pending = false,
}) => WorkItem(
  id: id,
  title: '项目 $id',
  description: '已审核的预约开发',
  category: 'development',
  duration: '',
  ownerId: 'customer-1',
  providerId: assigned ? providerId : null,
  engagementId: assigned ? 'engagement-$id' : null,
  createdAt: DateTime.utc(2026, 10, 26),
  status: status,
  intakeState: state,
  pendingConfirmation: pending,
);

class OverviewRepository extends EntryRepository {
  final projects = [
    project('active'),
    project('revision', status: WorkStatus.revision),
    project('review', status: WorkStatus.internalReview),
    project('accept', status: WorkStatus.awaitingAcceptance),
    project('done', status: WorkStatus.completed),
  ];
  final discussions = [
    project('chat', assigned: false, status: WorkStatus.published),
  ];
  @override
  List<WorkItem> myRequests() => projects;
  @override
  List<WorkItem> conversationRequests() => [...projects, ...discussions];
  @override
  List<WorkItem> hall({String query = '', String category = 'すべて'}) =>
      discussions.where((i) => i.title.contains(query)).toList();
}

void main() {
  test(
    'provider totals deduplicate discussions and separate active from submitted delivery stages',
    () {
      final repo = OverviewRepository();
      final overview = ProviderOverview(
        [
          ...repo.projects,
          project('other', providerId: 'another-provider'),
          project('cancelled', state: 'cancelled'),
        ],
        repo.conversationRequests(),
        provider.id,
      );
      expect(
        overview.filtered(ProviderProjectFilter.communicating).map((i) => i.id),
        ['chat'],
      );
      expect(
        overview
            .filtered(ProviderProjectFilter.active)
            .map((i) => i.id)
            .toSet(),
        {'active', 'revision'},
      );
      expect(
        overview
            .filtered(ProviderProjectFilter.delivered)
            .map((i) => i.id)
            .toSet(),
        {'review', 'accept', 'done'},
      );
      expect(overview.items.where((i) => i.id == 'active'), hasLength(1));
    },
  );

  for (final locale in ['zh', 'ja']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '$locale $brightness provider dashboard links its statistics and separate searchable hall',
        (tester) async {
          tester.view.physicalSize = const Size(320, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = OverviewRepository();
          final app = AppController(repo);
          addTearDown(app.dispose);
          await app.setLocale(Locale(locale));
          await tester.pumpWidget(
            host(app, ApiWorkspace(app: app), brightness: brightness),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('provider-overview')), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const Key('provider-stat-active')),
              matching: find.text('2'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const Key('provider-stat-delivered')),
              matching: find.text('3'),
            ),
            findsOneWidget,
          );
          await tapKey(tester, 'provider-stat-communicating');
          expect(find.byKey(const Key('api-item-chat')), findsOneWidget);
          expect(find.byKey(const Key('api-item-active')), findsNothing);
          await tapKey(tester, 'tab-0');
          await tapKey(tester, 'provider-stat-delivered');
          expect(find.byKey(const Key('api-item-review')), findsOneWidget);
          expect(find.byKey(const Key('api-item-active')), findsNothing);
          await tapKey(tester, 'tab-0');
          await tapKey(tester, 'provider-open-hall');
          await tester.enterText(
            find.byKey(const Key('api-hall-search')),
            'chat',
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('api-item-chat')), findsOneWidget);
          await tester.enterText(
            find.byKey(const Key('api-hall-search')),
            'missing',
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('api-item-chat')), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
