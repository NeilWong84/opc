import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/auth_page.dart';
import 'package:opc_app/features/customer_pages.dart';
import 'package:opc_app/features/hall_pages.dart';
import 'package:opc_app/features/home_shell.dart';
import 'package:opc_app/main.dart';

void _viewport(WidgetTester tester, Size size, {double scale = 1}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _login(WidgetTester tester, String email) async {
  await tester.enterText(find.byKey(const Key('login-email')), email);
  await tester.enterText(find.byKey(const Key('login-password')), 'demo1234');
  await _tapVisible(tester, find.byKey(const Key('auth-submit')));
}

AppController _newApp() {
  final app = AppController(MockOpcRepository(delay: Duration.zero));
  addTearDown(app.dispose);
  return app;
}

void main() {
  testWidgets(
    'customer login, request navigation, theme and logout work together',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final app = _newApp();
      await tester.pumpWidget(OpcApp(controller: app));
      await _login(tester, 'customer@opc.demo');

      expect(app.repository.session?.role, UserRole.customer);
      expect(find.byType(AuthPage), findsNothing);
      expect(find.byType(CustomerHomePage), findsOneWidget);
      expect(find.byType(HallPage), findsNothing);
      await _tapVisible(tester, find.text('REQ-1042'));
      expect(find.byType(ReviewPage), findsOneWidget);
      await _tapVisible(tester, find.byTooltip('戻る'));
      expect(find.byType(CustomerHomePage), findsOneWidget);
      await _tapVisible(tester, find.byKey(const ValueKey('tab-3')));
      expect(find.text('お客様アカウント'), findsOneWidget);
      await _tapVisible(tester, find.text('ダーク'));
      expect(app.themeMode, ThemeMode.dark);
      expect(
        Theme.of(tester.element(find.text('画面の表示'))).brightness,
        Brightness.dark,
      );
      await _tapVisible(tester, find.text('ライト'));
      expect(app.themeMode, ThemeMode.light);
      await _tapVisible(tester, find.text('ログアウト'));
      expect(app.repository.session, isNull);
      expect(find.byType(AuthPage), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration enters an empty customer workspace without provider rights',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final app = _newApp();
      await tester.pumpWidget(OpcApp(controller: app));
      await _tapVisible(tester, find.text('新規登録して相談する'));
      expect(find.text('登録して相談をはじめる'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '佐々木');
      await tester.enterText(
        find.byKey(const Key('login-email')),
        'sasaki@example.jp',
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'new-password',
      );
      await _tapVisible(tester, find.byKey(const Key('auth-submit')));

      expect(app.repository.session?.name, '佐々木');
      expect(app.repository.session?.role, UserRole.customer);
      expect(app.repository.session?.authorized, isFalse);
      expect(find.text('まだご依頼はありません'), findsOneWidget);
      expect(find.byType(CustomerHomePage), findsOneWidget);
      expect(find.byType(HallPage), findsNothing);
      await _tapVisible(tester, find.text('開発を相談する'));
      expect(find.byType(RequestFormPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('internal hall search and consultation never assign the task', (
    tester,
  ) async {
    _viewport(tester, const Size(390, 844));
    final app = _newApp();
    await tester.pumpWidget(OpcApp(controller: app));
    await _login(tester, 'member@opc.demo');

    expect(app.repository.session?.role, UserRole.provider);
    expect(app.repository.session?.authorized, isTrue);
    expect(find.byType(HallPage), findsOneWidget);
    expect(find.text('REQ-1042'), findsNothing);
    expect(find.text('開発案件 2件'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('hall-search')), '該当なし123');
    await tester.pumpAndSettle();
    expect(find.text('該当する案件はありません'), findsOneWidget);
    expect(find.text('開発案件 0件'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('hall-search')), '');
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.widgetWithText(ChoiceChip, '業務自動化'));
    expect(find.text('開発案件 1件'), findsOneWidget);
    expect(find.text('DEV-1039'), findsOneWidget);
    expect(find.text('DEV-1036'), findsNothing);
    await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'すべて'));
    await _tapVisible(tester, find.text('DEV-1036'));
    expect(find.byType(TaskDetailPage), findsOneWidget);
    const consultation = 'Web アプリの開発経験があります。利用者数と権限について確認したいです。';
    await _tapVisible(tester, find.text('案件について相談する'));
    await tester.enterText(find.byType(TextFormField), consultation);
    await _tapVisible(tester, find.text('相談を送信する'));

    final item = app.repository.detail('DEV-1036');
    expect(item.providerId, isNull);
    expect(item.status, WorkStatus.published);
    expect(item.messages.last.text, consultation);
    expect(app.repository.hall(), hasLength(2));
    expect(find.text('相談を送信しました。担当はまだ確定していません。'), findsOneWidget);
    expect(find.byType(TaskDetailPage), findsOneWidget);
    await _tapVisible(tester, find.byTooltip('戻る'));
    expect(find.byType(HallPage), findsOneWidget);
    expect(find.text('開発案件 2件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pushed message route refreshes after a successful send', (
    tester,
  ) async {
    _viewport(tester, const Size(390, 844));
    final app = _newApp();
    await tester.runAsync(
      () => app.repository.login('customer@opc.demo', 'demo1234'),
    );
    await tester.pumpWidget(OpcApp(controller: app));
    await _tapVisible(tester, find.byKey(const ValueKey('tab-2')));
    await _tapVisible(tester, find.text('OPC-1028'));
    expect(find.byType(ConversationPage), findsOneWidget);
    const message = '確認用デモの共有をお願いします。';
    await tester.enterText(find.byType(TextField), message);
    await _tapVisible(tester, find.text('送信する'));

    expect(app.repository.detail('OPC-1028').messages.last.text, message);
    expect(find.text(message), findsOneWidget);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, isEmpty);
    expect(find.byType(ConversationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final screen in ['auth', 'hall', 'detail']) {
        testWidgets(
          '$screen fits ${size.width}x${size.height} ${mode.name} text 1.5',
          (tester) async {
            _viewport(tester, size, scale: 1.5);
            final app = _newApp();
            app.setTheme(mode);
            if (screen != 'auth') {
              await tester.runAsync(
                () => app.repository.login('member@opc.demo', 'demo1234'),
              );
            }
            await tester.pumpWidget(OpcApp(controller: app));
            await tester.pumpAndSettle();
            if (screen == 'detail') {
              await _tapVisible(tester, find.text('DEV-1036'));
            }
            expect(tester.takeException(), isNull);
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, -1800),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
