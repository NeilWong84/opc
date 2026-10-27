import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/widgets.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/hall_pages.dart';
import 'package:opc_app/features/customer_pages.dart';
import 'package:opc_app/features/home_shell.dart';
import 'package:opc_app/main.dart';

class _DeferredMessageRepository extends MockOpcRepository {
  _DeferredMessageRepository() : super(delay: Duration.zero);

  final messageGate = Completer<void>();

  @override
  Future<void> sendMessage(String id, String text) async {
    await messageGate.future;
    await super.sendMessage(id, text);
  }
}

void _phoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _openDirectPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => page)),
              child: const Text('テストの入口'),
            ),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('テストの入口'));
}

void main() {
  testWidgets(
    'leaving a message route during send does not use its disposed input',
    (tester) async {
      _phoneViewport(tester);
      final repository = _DeferredMessageRepository();
      final app = AppController(repository);
      await repository.login('customer@opc.demo', 'demo1234');
      await tester.pumpWidget(OpcApp(controller: app));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('tab-2')));
      await _tap(tester, find.text('OPC-1028'));
      expect(find.byType(ConversationPage), findsOneWidget);

      const message = '送信中に前の画面へ戻る場合も内容を記録します。';
      await tester.enterText(find.byType(TextField), message);
      await tester.ensureVisible(find.text('送信する'));
      await tester.tap(find.text('送信する'));
      await tester.pump();
      expect(app.busy, isTrue);

      await tester.tap(find.byTooltip('戻る'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ConversationPage), findsNothing);

      repository.messageGate.complete();
      await tester.pumpAndSettle();
      expect(repository.detail('OPC-1028').messages.last.text, message);
      expect(app.busy, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    },
  );

  testWidgets(
    'a newly reviewed AI request does not inherit quote or CRM scope',
    (tester) async {
      _phoneViewport(tester);
      final repository = MockOpcRepository(delay: Duration.zero);
      final app = AppController(repository);
      await repository.login('customer@opc.demo', 'demo1234');
      const description = '社内 FAQ の開発を相談したいです。資料を探す時間を減らしたいです。';
      final request = await repository.submitRequest(
        RequestDraft(description: description),
      );
      await repository.simulateReview(request.id);
      await repository.login('member@opc.demo', 'demo1234');
      await tester.pumpWidget(OpcApp(controller: app));
      await tester.pumpAndSettle();
      await _tap(tester, find.text(request.id));

      expect(find.byType(TaskDetailPage), findsOneWidget);
      expect(find.text(request.title), findsOneWidget);
      expect(find.text(description), findsOneWidget);
      expect(find.text('入力フォームと見積計算'), findsNothing);
      expect(find.text('PDF の生成・出力'), findsNothing);
      expect(find.textContaining('対象外：外部会計サービス'), findsNothing);
      expect(find.textContaining('対象外：外部 CRM'), findsNothing);
      expect(find.text('具体的な機能・対象範囲は、公開された説明をもとに運営と確認します。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    },
  );

  testWidgets(
    'the two design fixtures keep their own reviewed scope examples',
    (tester) async {
      _phoneViewport(tester);
      final repository = MockOpcRepository(delay: Duration.zero);
      final app = AppController(repository);
      await repository.login('member@opc.demo', 'demo1234');
      await tester.pumpWidget(OpcApp(controller: app));
      await tester.pumpAndSettle();

      await _tap(tester, find.text('DEV-1036'));
      expect(find.text('問い合わせの登録・一覧・検索'), findsOneWidget);
      expect(find.text('入力フォームと見積計算'), findsNothing);
      await _tap(tester, find.byTooltip('戻る'));
      await _tap(tester, find.text('DEV-1039'));
      expect(find.text('入力フォームと見積計算'), findsOneWidget);
      expect(find.text('問い合わせの登録・一覧・検索'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    },
  );

  for (final pageName in ['hall', 'detail', 'review', 'messages', 'profile']) {
    testWidgets('$pageName safely refreshes when account access is withdrawn', (
      tester,
    ) async {
      _phoneViewport(tester);
      final repository = MockOpcRepository(delay: Duration.zero);
      final app = AppController(repository);
      final provider = pageName == 'hall' || pageName == 'detail';
      await repository.login(
        provider ? 'member@opc.demo' : 'customer@opc.demo',
        'demo1234',
      );
      final page = switch (pageName) {
        'hall' => HallPage(app: app, onOpen: (_) {}, onNotifications: () {}),
        'detail' => TaskDetailPage(app: app, id: 'DEV-1036'),
        'review' => ReviewPage(app: app, id: 'REQ-1042'),
        'messages' => ConversationPage(app: app, id: 'OPC-1028'),
        _ => HomeShell(app: app),
      };
      await _openDirectPage(tester, page);
      if (pageName == 'profile') {
        await _tap(tester, find.byKey(const ValueKey('tab-3')));
        expect(find.text('customer@opc.demo'), findsOneWidget);
      }

      await app.run(
        () => provider
            ? repository.simulateAccountAccess(authorized: false)
            : repository.simulateAccountAccess(active: false),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RepositoryUnavailablePage), findsOneWidget);
      expect(
        find.text(provider ? '有効な内部承接権限が必要です。' : 'このアカウントは停止中です。'),
        findsOneWidget,
      );
      expect(find.text('customer@opc.demo'), findsNothing);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.byTooltip('戻る'));
      expect(find.text('テストの入口'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    });
  }

  testWidgets(
    'a profile route handles an empty session without a null assertion',
    (tester) async {
      _phoneViewport(tester);
      final repository = MockOpcRepository(delay: Duration.zero);
      final app = AppController(repository);
      await repository.login('customer@opc.demo', 'demo1234');
      await _openDirectPage(tester, HomeShell(app: app));
      await _tap(tester, find.byKey(const ValueKey('tab-3')));
      await app.run(repository.logout);
      await tester.pumpAndSettle();
      expect(find.byType(RepositoryUnavailablePage), findsOneWidget);
      expect(find.text('ログインしてください。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.byTooltip('戻る'));
      expect(find.text('テストの入口'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    },
  );

  for (final (size, keyboard) in [
    (const Size(390, 844), 300.0),
    (const Size(320, 640), 260.0),
  ]) {
    for (final pageName in ['request', 'messages']) {
      testWidgets(
        '$pageName action remains reachable with $keyboard keyboard at $size',
        (tester) async {
          _phoneViewport(tester);
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetViewInsets);
          final repository = MockOpcRepository(delay: Duration.zero);
          final app = AppController(repository);
          await repository.login('customer@opc.demo', 'demo1234');
          await tester.pumpWidget(
            MaterialApp(
              home: pageName == 'request'
                  ? RequestFormPage(app: app)
                  : ConversationPage(app: app, id: 'OPC-1028'),
            ),
          );
          await tester.pumpAndSettle();
          final input = find.byType(EditableText).first;
          await tester.ensureVisible(input);
          await tester.tap(input);
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
          await tester.pumpAndSettle();

          final label = pageName == 'request' ? '確認画面へ' : '送信する';
          final action = find.widgetWithText(FilledButton, label);
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget);
          expect(
            tester.getBottomRight(action).dy,
            lessThanOrEqualTo(size.height - keyboard),
          );
          expect(tester.takeException(), isNull);

          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget);
          expect(
            tester.getBottomRight(action).dy,
            greaterThan(size.height - 160),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          app.dispose();
        },
      );
    }
  }
}
