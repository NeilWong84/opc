import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/theme.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/customer_pages.dart';

Future<AppController> _customer() async {
  final repository = MockOpcRepository(delay: Duration.zero);
  await repository.login('customer@opc.demo', 'demo1234');
  return AppController(repository);
}

Widget _host(
  AppController app,
  Widget home, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => AnimatedBuilder(
  animation: app,
  builder: (context, _) => MaterialApp(
    locale: const Locale('ja'),
    supportedLocales: const [Locale('ja')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: opcTheme(brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  ),
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

CustomerHomePage _home(AppController app, {VoidCallback? onCreate}) =>
    CustomerHomePage(
      app: app,
      onCreate: onCreate ?? () {},
      onOpen: (_) {},
      onNotifications: () {},
    );

void main() {
  testWidgets('a new customer has an empty home and can begin a request', (
    tester,
  ) async {
    _viewport(tester, const Size(390, 844));
    final repository = MockOpcRepository(delay: Duration.zero);
    await repository.register('新しいお客様', 'new@example.jp', 'password123');
    final app = AppController(repository);
    addTearDown(app.dispose);
    var started = false;
    await tester.pumpWidget(
      _host(app, _home(app, onCreate: () => started = true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('まだご依頼はありません'), findsOneWidget);
    expect(find.text('0件'), findsOneWidget);
    expect(find.text('社内資料を探せる AI FAQ'), findsNothing);
    await tester.tap(find.text('開発を相談する'));
    expect(started, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmation preserves the original and submission stays private',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final app = await _customer();
      addTearDown(app.dispose);
      final originalCount = app.repository.myRequests().length;
      const description = '予約の受付と変更をスマートフォンで管理できる社内システムを作りたいです。';
      await tester.pumpWidget(_host(app, RequestFormPage(app: app)));
      await tester.enterText(find.byType(TextFormField), description);
      await tester.tap(find.text('確認画面へ'));
      await tester.pumpAndSettle();

      expect(find.text('ご相談内容の確認'), findsOneWidget);
      expect(find.text(description), findsOneWidget);
      expect(app.repository.myRequests(), hasLength(originalCount));
      await tester.tap(find.text('内容を修正する'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, description), findsOneWidget);
      await tester.tap(find.text('確認画面へ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この内容で相談する'));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewPage), findsOneWidget);
      expect(find.byType(RequestFormPage), findsNothing);
      final created = app.repository.myRequests().last;
      expect(app.repository.myRequests(), hasLength(originalCount + 1));
      expect(created.description, description);
      expect(created.status, WorkStatus.reviewing);
      expect(created.isPublished, isFalse);
      expect(created.complianceApproved, isFalse);
      expect(created.technicalApproved, isFalse);
      expect(created.publishedVersion, isNull);
      expect(find.text('この依頼は、まだ案件一覧に公開されていません。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed submission keeps the confirmation available for retry',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final app = await _customer();
      addTearDown(app.dispose);
      final repository = app.repository as MockOpcRepository;
      final originalCount = repository.myRequests().length;
      await tester.pumpWidget(_host(app, RequestFormPage(app: app)));
      await tester.tap(find.text('確認画面へ'));
      await tester.pumpAndSettle();
      repository.failNext = true;
      await tester.tap(find.text('この内容で相談する'));
      await tester.pumpAndSettle();

      expect(find.text('ご相談内容の確認'), findsOneWidget);
      expect(repository.myRequests(), hasLength(originalCount));
      expect(app.busy, isFalse);
      expect(find.text('デモ通信に失敗しました。内容を確認して、もう一度お試しください。'), findsOneWidget);
      await tester.tap(find.text('この内容で相談する'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewPage), findsOneWidget);
      expect(repository.myRequests(), hasLength(originalCount + 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clarification replies are kept and still require a human review',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final app = await _customer();
      addTearDown(app.dispose);
      final before = app.repository.detail('REQ-1042');
      const answer = '利用者は30名です。社内公開のPDF資料のみを対象にし、個人情報は含みません。';
      await tester.pumpWidget(_host(app, ReviewPage(app: app, id: 'REQ-1042')));
      await tester.tap(find.text('質問に回答する'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), answer);
      await tester.tap(find.text('回答を送信'));
      await tester.pumpAndSettle();

      final after = app.repository.detail('REQ-1042');
      expect(after.messages, hasLength(before.messages.length + 1));
      expect(after.messages.last.text, answer);
      expect(after.version, before.version + 1);
      expect(after.status, WorkStatus.reviewing);
      expect(after.isPublished, isFalse);
      expect(after.technicalApproved, isFalse);
      expect(find.text('質問に回答する'), findsNothing);
      expect(find.text(answer), findsOneWidget);
      expect(find.text('ご依頼一覧へ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving a draft does not create a request and restores entered text',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final app = await _customer();
      addTearDown(app.dispose);
      final count = app.repository.myRequests().length;
      const description = '店舗ごとの在庫を確認できる管理画面を作りたいです。';
      await tester.pumpWidget(_host(app, RequestFormPage(app: app)));
      await tester.enterText(find.byType(TextFormField), description);
      await tester.tap(find.text('下書きとして保存'));
      await tester.pumpAndSettle();

      expect(app.repository.draft?.description, description);
      expect(app.repository.myRequests(), hasLength(count));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(app, RequestFormPage(app: app)));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, description), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  const sizes = [Size(320, 640), Size(390, 844), Size(844, 390)];
  for (final size in sizes) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.5]) {
        for (final screen in ['home', 'request', 'review']) {
          testWidgets(
            '$screen fits ${size.width}x${size.height} ${brightness.name} text $scale',
            (tester) async {
              _viewport(tester, size);
              final app = await _customer();
              addTearDown(app.dispose);
              final Widget page = switch (screen) {
                'home' => _home(app),
                'request' => RequestFormPage(app: app),
                _ => ReviewPage(app: app, id: 'REQ-1042'),
              };
              await tester.pumpWidget(
                _host(app, page, brightness: brightness, textScale: scale),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);

              await tester.drag(
                find.byType(SingleChildScrollView).first,
                const Offset(0, -1600),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              if (screen == 'request') {
                await tester.tap(find.text('確認画面へ'));
                await tester.pumpAndSettle();
                expect(find.text('ご相談内容の確認'), findsOneWidget);
                expect(tester.takeException(), isNull);
              }
            },
          );
        }
      }
    }
  }
}
