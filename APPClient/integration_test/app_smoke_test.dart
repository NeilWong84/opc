import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/preferences.dart';
import 'package:opc_app/core/theme.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/features/auth_page.dart';
import 'package:opc_app/features/customer_pages.dart';
import 'package:opc_app/features/hall_pages.dart';
import 'package:opc_app/features/home_shell.dart';
import 'package:opc_app/features/project_pages.dart';
import 'package:opc_app/l10n/app_localizations.dart';
import 'package:opc_app/main.dart';

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _selectLanguage(WidgetTester tester, String language) async {
  await _tap(tester, find.byKey(const Key('language-menu')));
  await _tap(tester, find.byKey(Key('language-$language')));
}

String _input(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real language menus preserve input and persist Chinese across controllers',
    (tester) async {
      final repository = MockOpcRepository(delay: Duration.zero);
      final app = AppController(
        repository,
        preferences: SharedPreferencesAppPreferences(),
      );
      addTearDown(app.dispose);
      // Normalize the emulator's prior setting before exercising the real UI.
      expect(await app.setLocale(const Locale('ja')), isTrue);
      await tester.pumpWidget(OpcApp(controller: app));
      await tester.pumpAndSettle();
      final loginState = tester.state(find.byType(AuthPage));
      await tester.enterText(
        find.byKey(const Key('login-email')),
        'language-test@example.jp',
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'input-is-not-persisted',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _selectLanguage(tester, 'zh');
      expect(app.locale, const Locale('zh'));
      expect(find.text('登录'), findsOneWidget);
      expect(tester.state(find.byType(AuthPage)), same(loginState));
      expect(_input(tester, 'login-email'), 'language-test@example.jp');
      expect(_input(tester, 'login-password'), 'input-is-not-persisted');
      expect(find.byType(Banner), findsNothing);

      await app.run(() => repository.login('customer@opc.demo', 'demo1234'));
      await tester.pumpAndSettle();
      final session = repository.session;
      final title = repository.detail('OPC-1028').title;
      await _tap(tester, find.byKey(const Key('tab-3')));
      await _selectLanguage(tester, 'ja');
      expect(app.locale, const Locale('ja'));
      await _selectLanguage(tester, 'zh');
      expect(app.locale, const Locale('zh'));
      expect(find.text('账号与显示设置'), findsOneWidget);
      expect(repository.session, same(session));
      expect(repository.detail('OPC-1028').title, title);
      // This queued write waits for the menu's saves before recreating the app.
      expect(await app.setLocale(app.locale), isTrue);
      expect(await SharedPreferencesAppPreferences().readLanguage(), 'zh');
      expect(find.byType(Banner), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      final restarted = AppController(
        MockOpcRepository(delay: Duration.zero),
        preferences: SharedPreferencesAppPreferences(),
      );
      addTearDown(restarted.dispose);
      await restarted.restorePreferences();
      expect(restarted.locale, const Locale('zh'));
      await tester.pumpWidget(OpcApp(controller: restarted));
      await tester.pumpAndSettle();
      expect(find.text('登录'), findsOneWidget);
      expect(restarted.repository.session, isNull);
      expect(_input(tester, 'login-email'), isEmpty);
      expect(_input(tester, 'login-password'), isEmpty);
      expect(find.byType(Banner), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'nine MasterGo screens render in Japanese and Chinese in both themes',
    (tester) async {
      final repository = MockOpcRepository(delay: Duration.zero);
      final app = AppController(repository);
      addTearDown(app.dispose);
      var surfaceConverted = false;

      Future<void> capture(
        String name,
        Widget page,
        Brightness brightness,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: app.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: opcTheme(brightness),
            home: page,
          ),
        );
        await tester.pumpAndSettle();
        if (!surfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
          await tester.pumpAndSettle();
        }
        final context = tester.element(find.byType(Scaffold).first);
        expect(Localizations.localeOf(context), app.locale);
        expect(
          AppLocalizations.of(context)!.localeName,
          app.locale.languageCode,
        );
        expect(Theme.of(context).brightness, brightness);
        expect(find.byType(Banner), findsNothing);
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(name);
      }

      for (final language in ['ja', 'zh']) {
        expect(await app.setLocale(Locale(language)), isTrue);
        for (final brightness in Brightness.values) {
          final prefix = '$language-${brightness.name}';
          await repository.logout();
          await capture('$prefix-01-login', AuthPage(app: app), brightness);
          await repository.login('customer@opc.demo', 'demo1234');
          await capture('$prefix-02-home', HomeShell(app: app), brightness);
          await capture(
            '$prefix-03-request',
            RequestFormPage(app: app),
            brightness,
          );
          await capture(
            '$prefix-04-review',
            ReviewPage(app: app, id: 'REQ-1042'),
            brightness,
          );
          await capture(
            '$prefix-09-acceptance',
            AcceptancePage(app: app, id: 'OPC-1017'),
            brightness,
          );
          await repository.login('member@opc.demo', 'demo1234');
          await capture('$prefix-05-hall', HomeShell(app: app), brightness);
          await capture(
            '$prefix-06-detail',
            TaskDetailPage(app: app, id: 'DEV-1036'),
            brightness,
          );
          await capture(
            '$prefix-07-project',
            ProjectPage(app: app, id: 'OPC-1028'),
            brightness,
          );
          await capture(
            '$prefix-08-delivery',
            DeliveryPage(app: app, id: 'OPC-1028'),
            brightness,
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
