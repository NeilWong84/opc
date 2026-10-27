import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/theme.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/auth_page.dart';
import 'package:opc_app/features/customer_pages.dart';
import 'package:opc_app/features/hall_pages.dart';
import 'package:opc_app/features/home_shell.dart';
import 'package:opc_app/features/project_pages.dart';
import 'package:opc_app/l10n/app_localizations.dart';
import 'package:opc_app/main.dart';

void _viewport(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

AppController _app() {
  final app = AppController(MockOpcRepository(delay: Duration.zero));
  addTearDown(app.dispose);
  return app;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _selectLanguage(WidgetTester tester, String language) async {
  await _tap(tester, find.byKey(const ValueKey('language-menu')));
  await _tap(tester, find.byKey(ValueKey('language-$language')));
}

String _input(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

List<String?> _errors(WidgetTester tester) => tester
    .stateList<FormFieldState<String>>(find.byType(TextFormField))
    .map((state) => state.errorText)
    .toList();

Widget _localizedPage(AppController app, Widget page) => AnimatedBuilder(
  animation: app,
  builder: (context, _) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: app.locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: opcTheme(Brightness.light),
    darkTheme: opcTheme(Brightness.dark),
    themeMode: app.themeMode,
    home: page,
  ),
);

void main() {
  testWidgets(
    'the real language menu switches both ways and preserves login input',
    (tester) async {
      _viewport(tester);
      final app = _app();
      await tester.pumpWidget(OpcApp(controller: app));
      await tester.pumpAndSettle();
      final initialState = tester.state(find.byType(AuthPage));
      await tester.enterText(
        find.byKey(const Key('login-email')),
        'original@example.jp',
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'abc123456',
      );
      expect(find.text('ログインする'), findsOneWidget);
      expect(find.byType(Banner), findsNothing);

      await _selectLanguage(tester, 'zh');
      expect(app.locale.languageCode, 'zh');
      expect(find.text('登录'), findsOneWidget);
      expect(find.text('ログインする'), findsNothing);
      expect(tester.state(find.byType(AuthPage)), same(initialState));
      expect(_input(tester, 'login-email'), 'original@example.jp');
      expect(_input(tester, 'login-password'), 'abc123456');
      expect(
        Localizations.localeOf(
          tester.element(find.byType(AuthPage)),
        ).languageCode,
        'zh',
      );

      await _selectLanguage(tester, 'ja');
      expect(app.locale.languageCode, 'ja');
      expect(find.text('ログインする'), findsOneWidget);
      expect(find.text('登录'), findsNothing);
      expect(tester.state(find.byType(AuthPage)), same(initialState));
      expect(_input(tester, 'login-email'), 'original@example.jp');
      expect(_input(tester, 'login-password'), 'abc123456');
      expect(find.byType(Banner), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('registration validates in Chinese without creating an account', (
    tester,
  ) async {
    _viewport(tester);
    final app = _app();
    await tester.pumpWidget(OpcApp(controller: app));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('新規登録して相談する'));
    await _selectLanguage(tester, 'zh');
    await tester.enterText(find.byKey(const Key('login-email')), 'invalid');
    await tester.enterText(find.byKey(const Key('login-password')), '123');
    await _tap(tester, find.byKey(const Key('auth-submit')));

    expect(_errors(tester), ['请输入姓名', '请检查电子邮箱格式', '请输入密码（注册时至少 8 位）']);
    expect(find.text('お名前を入力してください'), findsNothing);
    expect(find.text('メールアドレスを確認してください'), findsNothing);
    expect(app.repository.session, isNull);
    expect(_input(tester, 'login-email'), 'invalid');
    expect(_input(tester, 'login-password'), '123');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'visible registration errors change language without losing input',
    (tester) async {
      _viewport(tester);
      final app = _app();
      await tester.pumpWidget(OpcApp(controller: app));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('新規登録して相談する'));
      await tester.enterText(find.byKey(const Key('login-email')), 'invalid');
      await tester.enterText(find.byKey(const Key('login-password')), '123');
      await _tap(tester, find.byKey(const Key('auth-submit')));
      const japaneseErrors = [
        'お名前を入力してください',
        'メールアドレスを確認してください',
        'パスワードを入力してください（登録時は8文字以上）',
      ];
      expect(_errors(tester), japaneseErrors);
      final originalState = tester.state(find.byType(AuthPage));

      await _selectLanguage(tester, 'zh');
      expect(_errors(tester), ['请输入姓名', '请检查电子邮箱格式', '请输入密码（注册时至少 8 位）']);
      expect(find.text('メールアドレスを確認してください'), findsNothing);
      expect(_input(tester, 'login-email'), 'invalid');
      expect(_input(tester, 'login-password'), '123');
      expect(tester.state(find.byType(AuthPage)), same(originalState));
      expect(app.repository.session, isNull);

      await _selectLanguage(tester, 'ja');
      expect(_errors(tester), japaneseErrors);
      expect(find.text('请检查电子邮箱格式'), findsNothing);
      expect(_input(tester, 'login-email'), 'invalid');
      expect(_input(tester, 'login-password'), '123');
      expect(tester.state(find.byType(AuthPage)), same(originalState));
      expect(app.repository.session, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repository login failure is displayed in Chinese by error code',
    (tester) async {
      _viewport(tester);
      final app = _app();
      await tester.pumpWidget(OpcApp(controller: app));
      await tester.pumpAndSettle();
      await _selectLanguage(tester, 'zh');
      await tester.enterText(
        find.byKey(const Key('login-email')),
        'customer@opc.demo',
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'incorrect-password',
      );
      await _tap(tester, find.byKey(const Key('auth-submit')));

      expect(_errors(tester), [null, null]);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('请检查邮箱或密码。'), findsOneWidget);
      expect(find.text('メールアドレスまたはパスワードをご確認ください。'), findsNothing);
      expect(app.repository.session, isNull);
      expect(app.busy, isFalse);
      expect(_input(tester, 'login-email'), 'customer@opc.demo');
      expect(_input(tester, 'login-password'), 'incorrect-password');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile language changes preserve identity, business text and draft',
    (tester) async {
      _viewport(tester);
      final app = _app();
      await app.repository.login('customer@opc.demo', 'demo1234');
      const originalMessage = '客户原文：日本語の仕様をそのまま保持してください。';
      final draft = RequestDraft(
        description: '保留原文的草稿。日本語と中文が混在しても変更しません。',
        timing: '2〜3か月以内を希望',
        budget: '10万〜30万円',
        attachmentNames: ['原始资料.pdf'],
      );
      await app.repository.saveDraft(draft);
      await app.repository.sendMessage('OPC-1028', originalMessage);
      final user = app.repository.session;
      final before = app.repository.detail('OPC-1028');
      await tester.pumpWidget(OpcApp(controller: app));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('tab-3')));
      await _selectLanguage(tester, 'zh');

      expect(find.text('账号与显示设置'), findsOneWidget);
      expect(find.text('客户账号'), findsOneWidget);
      expect(app.repository.session, same(user));
      expect(app.repository.session!.role, UserRole.customer);
      expect(app.repository.session!.authorized, isFalse);
      expect(app.repository.draft!.description, draft.description);
      expect(app.repository.draft!.timing, draft.timing);
      expect(app.repository.draft!.budget, draft.budget);
      expect(app.repository.draft!.attachmentNames, draft.attachmentNames);
      final after = app.repository.detail('OPC-1028');
      expect(after.title, before.title);
      expect(after.description, before.description);
      expect(after.duration, before.duration);
      expect(after.budget, before.budget);
      expect(after.status, before.status);
      expect(after.version, before.version);

      await _tap(tester, find.byKey(const ValueKey('tab-2')));
      await _tap(tester, find.text('OPC-1028'));
      expect(find.byType(ConversationPage), findsOneWidget);
      expect(find.text(originalMessage), findsOneWidget);
      expect(find.text('发送'), findsOneWidget);
      expect(find.byType(Banner), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'language changes preserve a pushed form and stable choice values',
    (tester) async {
      _viewport(tester);
      final app = _app();
      await app.repository.login('customer@opc.demo', 'demo1234');
      await tester.pumpWidget(OpcApp(controller: app));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('開発を相談する'));
      const original = '我希望开发一套预约系统。お客様の原文を翻訳しないでください。';
      await tester.enterText(find.byType(TextFormField).first, original);
      final formState = tester.state(find.byType(RequestFormPage));
      final values = tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .map((field) => field.value)
          .toList();

      await app.setLocale(const Locale('zh'));
      await tester.pumpAndSettle();
      expect(find.byType(RequestFormPage), findsOneWidget);
      expect(tester.state(find.byType(RequestFormPage)), same(formState));
      expect(find.widgetWithText(TextFormField, original), findsOneWidget);
      expect(find.text('开发咨询'), findsOneWidget);
      expect(
        tester
            .widgetList<DropdownButton<String>>(
              find.byType(DropdownButton<String>),
            )
            .map((field) => field.value)
            .toList(),
        values,
      );
      await _tap(tester, find.text('前往确认'));
      expect(find.text('希望 1 个月内'), findsOneWidget);
      expect(find.text('希望协商决定'), findsOneWidget);
      expect(find.text(original), findsOneWidget);
      expect(app.repository.draft, isNull);

      await app.setLocale(const Locale('ja'));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(RequestFormPage)), same(formState));
      expect(find.text('ご相談内容の確認'), findsOneWidget);
      expect(find.text(original), findsOneWidget);
      await _tap(tester, find.text('内容を修正する'));
      await _tap(tester, find.text('下書きとして保存'));
      expect(app.repository.draft!.description, original);
      expect(app.repository.draft!.timing, '1か月以内を希望');
      expect(app.repository.draft!.budget, '相談して決めたい');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'translated hall filters retain their stored category and search',
    (tester) async {
      _viewport(tester);
      final app = _app();
      await app.repository.login('member@opc.demo', 'demo1234');
      await tester.pumpWidget(OpcApp(controller: app));
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(ChoiceChip, '業務自動化'));
      await tester.enterText(find.byKey(const Key('hall-search')), '見積');
      await tester.pumpAndSettle();
      final hallState = tester.state(find.byType(HallPage));
      expect(find.text('DEV-1039'), findsOneWidget);
      expect(find.text('DEV-1036'), findsNothing);

      await app.setLocale(const Locale('zh'));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(HallPage)), same(hallState));
      expect(find.widgetWithText(TextField, '見積'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '业务自动化'))
            .selected,
        isTrue,
      );
      expect(find.text('DEV-1039'), findsOneWidget);
      expect(find.text('DEV-1036'), findsNothing);
      expect(find.text('見積書作成の自動化'), findsOneWidget);
      expect(app.repository.detail('DEV-1039').providerId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  const screens = [
    'auth',
    'customer-home',
    'request',
    'review',
    'hall',
    'detail',
    'project',
    'delivery',
    'acceptance',
  ];
  for (final language in ['ja', 'zh']) {
    for (final screen in screens) {
      testWidgets('$screen renders in $language at 320x640 without overflow', (
        tester,
      ) async {
        _viewport(tester, size: const Size(320, 640));
        final app = _app();
        await app.setLocale(Locale(language));
        if (screen != 'auth') {
          final provider = [
            'hall',
            'detail',
            'project',
            'delivery',
          ].contains(screen);
          await app.repository.login(
            provider ? 'member@opc.demo' : 'customer@opc.demo',
            'demo1234',
          );
        }
        final Widget page = switch (screen) {
          'auth' => AuthPage(app: app),
          'customer-home' => CustomerHomePage(
            app: app,
            onCreate: () {},
            onOpen: (_) {},
            onNotifications: () {},
          ),
          'request' => RequestFormPage(app: app),
          'review' => ReviewPage(app: app, id: 'REQ-1042'),
          'hall' => HallPage(app: app, onOpen: (_) {}, onNotifications: () {}),
          'detail' => TaskDetailPage(app: app, id: 'DEV-1036'),
          'project' => ProjectPage(app: app, id: 'OPC-1028'),
          'delivery' => DeliveryPage(app: app, id: 'OPC-1028'),
          _ => AcceptancePage(app: app, id: 'OPC-1017'),
        };
        await tester.pumpWidget(_localizedPage(app, page));
        await tester.pumpAndSettle();
        expect(
          AppLocalizations.of(
            tester.element(find.byType(Scaffold).last),
          )!.localeName,
          language,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(Banner), findsNothing);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -2200),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
