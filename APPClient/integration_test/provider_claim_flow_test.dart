// Android 真实 HTTP + PostgreSQL；管理凭据仅用于新增合成需求的后台审核。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/data/api_repository.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/api_workspace.dart';
import 'package:opc_app/features/api_negotiation_page.dart';
import 'package:opc_app/main.dart';

import 'real_api_smoke_test.dart' as harness;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android provider overview, hall search, customer approval, claim and delivery',
    (tester) async {
      final customer = ApiOpcRepository(baseUrl: harness.baseUrl);
      final provider = ApiOpcRepository(baseUrl: harness.baseUrl);
      final customerApp = AppController(customer);
      final providerApp = AppController(provider);
      addTearDown(customer.close);
      addTearDown(provider.close);
      addTearDown(customerApp.dispose);
      addTearDown(providerApp.dispose);
      await customerApp.setLocale(const Locale('zh'));
      await providerApp.setLocale(const Locale('zh'));
      await customer.register(
        '承接流程验证客户 ${harness.runId}',
        harness.customerEmail,
        harness.customerPassword,
      );
      final item = await customer.submitRequest(
        RequestDraft(
          description: '模拟器完整验证用预约系统，新增合成需求 ${harness.runId}，保留既有业务。',
          timing: '2026年12月',
          budget: 'JPY 协商',
        ),
      );
      var record = await harness.admin('GET', '/requests/${item.id}');
      record = await harness.admin(
        'POST',
        '/requests/${item.id}/scopes',
        status: 201,
        body: {
          'expected_version': record['row_version'],
          'title': '承接流程验证 ${harness.runId}',
          'public_summary': '仅用于模拟器验证的预约工具',
          'category': 'Web',
          'goal': '保存和查询预约',
          'included_scope': '预约列表与保存',
          'excluded_scope': '付款服务',
          'deliverables': ['固定版本源码', '运行说明', '测试记录'],
          'acceptance_criteria': ['可保存预约'],
          'duration_text': '双方确认后两周',
          'revision_terms': '范围内修改一次',
          'file_ids': [],
        },
      );
      for (final kind in ['compliance', 'technical']) {
        record = await harness.admin(
          'POST',
          '/requests/${item.id}/reviews',
          status: 201,
          body: {
            'expected_version': record['row_version'],
            'scope_version': record['current_scope_version'],
            'kind': kind,
            'decision': 'approved',
            'reason': 'Synthetic Android claim workflow verification only',
          },
        );
      }
      await harness.admin(
        'POST',
        '/requests/${item.id}/publish',
        status: 201,
        body: {
          'expected_version': record['row_version'],
          'scope_version': record['current_scope_version'],
          'reason':
              'Synthetic Android verification, not a real customer approval',
        },
      );

      Future<void> show(AppController app) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(OpcApp(controller: app));
        await tester.pumpAndSettle();
      }

      Future<void> tap(String key) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await harness.tap(tester, key);
        await tester.pumpAndSettle();
      }

      Future<void> ready(AppController app) async {
        await harness.waitForApp(tester, app);
        // 路由读取不占用全局 busy；等待具体内容而非假定网络在单帧完成。
        for (
          var n = 0;
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
              n < 200;
          n++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      await show(providerApp);
      await tester.enterText(
        find.byKey(const Key('login-email')),
        harness.providerEmail,
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        harness.providerPassword,
      );
      await tap('auth-submit');
      await ready(providerApp);
      expect(find.byKey(const Key('provider-overview')), findsOneWidget);
      for (final stage in ['communicating', 'active', 'delivered']) {
        expect(
          find.descendant(
            of: find.byKey(Key('provider-stat-$stage')),
            matching: find.text('0'),
          ),
          findsOneWidget,
        );
      }
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('claim-01-provider-home');
      await tap('provider-open-hall');
      await ready(providerApp);
      await tester.enterText(
        find.byKey(const Key('api-hall-search')),
        harness.runId,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('api-item-${item.id}')), findsOneWidget);
      await binding.takeScreenshot('claim-02-hall-search');
      await tap('api-item-${item.id}');
      await ready(providerApp);
      await tap('api-start-negotiation');
      await ready(providerApp);
      expect(find.byType(ApiNegotiationPage), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('negotiation-message')),
        '已核对预约范围，请确认以下条款。',
      );
      await tap('negotiation-send');
      await ready(providerApp);
      await tester.enterText(
        find.byKey(const Key('negotiation-terms')),
        '按已审核预约范围交付固定源码、运行说明及实际测试材料。',
      );
      await tester.enterText(
        find.byKey(const Key('negotiation-amount')),
        '120000',
      );
      await tap('negotiation-propose');
      await ready(providerApp);
      expect(find.byKey(const Key('negotiation-claim')), findsNothing);
      final thread = provider.negotiations(item.id).single.id;
      await binding.takeScreenshot('claim-03-waiting-customer');

      await customer.refresh();
      await show(customerApp);
      await tap('tab-2');
      await ready(customerApp);
      await tap('api-item-${item.id}');
      await ready(customerApp);
      await tap('api-negotiation-$thread');
      await ready(customerApp);
      expect(find.text('预约列表与保存'), findsOneWidget);
      await tap('negotiation-approve');
      await tap('negotiation-confirm-dialog');
      await ready(customerApp);
      expect((await customer.negotiation(thread)).proposal!.confirmed, isTrue);
      await binding.takeScreenshot('claim-04-customer-confirmed');

      await provider.refresh();
      await show(providerApp);
      expect(
        find.byKey(ValueKey('provider-recent-${item.id}')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('provider-stat-communicating')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await tap('provider-stat-communicating');
      await ready(providerApp);
      await tap('api-item-${item.id}');
      await ready(providerApp);
      await tap('api-negotiation-$thread');
      await ready(providerApp);
      await tap('negotiation-claim');
      await tap('negotiation-confirm-dialog');
      await ready(providerApp);
      await harness.waitForKey(tester, 'api-open-delivery');
      final assigned = provider.detail(item.id);
      expect(assigned.providerId, harness.providerId);
      expect(assigned.status, WorkStatus.developing);
      expect(provider.hall().where((e) => e.id == item.id), isEmpty);
      await binding.takeScreenshot('claim-05-claimed-project');
      await provider.refresh();
      await show(providerApp);
      expect(
        find.descendant(
          of: find.byKey(const Key('provider-stat-active')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('provider-stat-communicating')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      await binding.takeScreenshot('claim-05b-active-summary');
      await tap('provider-stat-active');
      await ready(providerApp);
      await tap('api-item-delivery-${item.id}');
      await ready(providerApp);
      expect(find.byType(ApiDeliveryPage), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('api-source-repository')),
        'https://example.jp/synthetic-test-source',
      );
      await tester.enterText(
        find.byKey(const Key('api-source-commit')),
        'a' * 40,
      );
      await tester.enterText(
        find.byKey(const Key('api-source-archive-ref')),
        'Synthetic fixed archive evidence for this Android integration test only; not a production repository.',
      );
      await tester.enterText(
        find.byKey(const Key('api-delivery-guide')),
        '合成运行说明：安装依赖并运行测试命令。',
      );
      await tester.enterText(
        find.byKey(const Key('api-delivery-tests')),
        '本次为流程验证；未执行客户项目源码测试，不记为通过。',
      );
      await tester.enterText(
        find.byKey(const Key('api-delivery-note')),
        '模拟器端条款确认、承接和提交交付物流程验证。',
      );
      await tap('api-submit-delivery');
      await ready(providerApp);
      expect(provider.detail(item.id).status, WorkStatus.internalReview);
      expect(provider.detail(item.id).deliveries, hasLength(1));
      await binding.takeScreenshot('claim-06-delivery-submitted');
      await provider.refresh();
      await show(providerApp);
      expect(
        find.descendant(
          of: find.byKey(const Key('provider-stat-delivered')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('provider-stat-active')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      await binding.takeScreenshot('claim-06b-delivered-home');
      await tap('provider-stat-delivered');
      await ready(providerApp);
      expect(find.byKey(ValueKey('api-item-${item.id}')), findsOneWidget);
      await binding.takeScreenshot('claim-07-delivered-summary');
      final stored = await harness.admin(
        'GET',
        '/engagements/${assigned.engagementId}',
      );
      expect(stored['engagement']['provider_id'], harness.providerId);
      expect(stored['engagement']['status'], 'internal_review');
      expect((stored['confirmations'] as List).length, 2);
      expect((stored['deliveries'] as List).length, 1);
      binding.reportData = {
        ...?binding.reportData,
        'run': harness.runId,
        'request_id': item.id,
        'engagement_id': assigned.engagementId,
        'provider_id': harness.providerId,
        'thread_id': thread,
        'final_state': 'internal_review',
        'verified': [
          'provider_home',
          'hall_search',
          'customer_scope_confirmation',
          'one_click_claim',
          'delivery_form',
          'delivered_summary',
        ],
      };
    },
  );
}
