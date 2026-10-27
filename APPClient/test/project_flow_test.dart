import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/theme.dart';
import 'package:opc_app/core/widgets.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/project_pages.dart';
import 'package:opc_app/l10n/app_localizations.dart';

Future<AppController> _account({bool provider = false}) async {
  final repository = MockOpcRepository(delay: Duration.zero);
  await repository.login(
    provider ? 'member@opc.demo' : 'customer@opc.demo',
    'demo1234',
  );
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
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
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

PrimaryButton _primary(WidgetTester tester, String label) =>
    tester.widget<PrimaryButton>(
      find.byWidgetPredicate(
        (widget) => widget is PrimaryButton && widget.label == label,
      ),
    );

Future<void> _checkAll(WidgetTester tester) async {
  final check = find.byKey(const ValueKey('acceptance-check-2'));
  await tester.ensureVisible(check);
  await tester.tap(check);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'provider submits for internal review and customer sees no files',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final app = await _account(provider: true);
      addTearDown(app.dispose);
      await tester.pumpWidget(
        _host(app, ProjectPage(app: app, id: 'OPC-1028')),
      );
      await tester.tap(find.text('成果物を提出する'));
      await tester.pumpAndSettle();
      expect(find.byType(DeliveryPage), findsOneWidget);
      expect(find.text('18.4 MB · 選択済み'), findsOneWidget);
      await tester.tap(find.text('運営に確認を依頼する'));
      await tester.pumpAndSettle();

      final submitted = app.repository.detail('OPC-1028');
      expect(submitted.status, WorkStatus.internalReview);
      expect(submitted.deliveries, hasLength(1));
      expect(submitted.deliveries.single.published, isFalse);
      expect(submitted.deliveries.single.sourceRef, 'v0.3.0 · 8f3a2c1');
      expect(find.byType(DeliveryPage), findsNothing);
      expect(_primary(tester, '運営の確認待ち').onPressed, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await app.repository.logout();
        await app.repository.login('customer@opc.demo', 'demo1234');
      });
      expect(app.repository.detail('OPC-1028').deliveries, isEmpty);
      await tester.pumpWidget(
        _host(app, ProjectPage(app: app, id: 'OPC-1028')),
      );
      await tester.tap(find.text('ファイル'));
      await tester.pumpAndSettle();
      expect(find.text('opc-faq-v0.3.0.zip'), findsNothing);
      expect(find.text('成果物を提出する'), findsNothing);
      expect(find.text('お客様向けの納品ファイルは、運営の確認後に表示されます。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('acceptance needs every check and an explicit confirmation', (
    tester,
  ) async {
    _viewport(tester, const Size(390, 844));
    final app = await _account();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      _host(app, AcceptancePage(app: app, id: 'OPC-1017')),
    );
    expect(find.text('2 / 3'), findsOneWidget);
    expect(_primary(tester, '検収を完了する').onPressed, isNull);
    await _checkAll(tester);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(_primary(tester, '検収を完了する').onPressed, isNotNull);
    await tester.tap(find.text('検収を完了する'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      app.repository.detail('OPC-1017').status,
      WorkStatus.awaitingAcceptance,
    );
    await tester.tap(find.widgetWithText(TextButton, '戻る'));
    await tester.pumpAndSettle();
    expect(
      app.repository.detail('OPC-1017').status,
      WorkStatus.awaitingAcceptance,
    );
    await tester.tap(find.text('検収を完了する'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '検収を完了する').last);
    await tester.pumpAndSettle();
    expect(app.repository.detail('OPC-1017').status, WorkStatus.completed);
    expect(_primary(tester, '検収完了').onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'revision requires a reason and prevents accepting that release',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final app = await _account();
      addTearDown(app.dispose);
      await tester.pumpWidget(
        _host(app, AcceptancePage(app: app, id: 'OPC-1017')),
      );
      await tester.tap(find.text('修正を依頼する'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '修正を依頼する'));
      await tester.pumpAndSettle();
      expect(find.text('修正してほしい内容を入力してください'), findsOneWidget);
      expect(
        app.repository.detail('OPC-1017').status,
        WorkStatus.awaitingAcceptance,
      );
      const reason = '問い合わせ一覧の担当者で絞り込めるようにしてください。';
      await tester.enterText(find.byType(TextFormField), reason);
      await tester.tap(find.widgetWithText(FilledButton, '修正を依頼する'));
      await tester.pumpAndSettle();
      final item = app.repository.detail('OPC-1017');
      expect(item.status, WorkStatus.revision);
      expect(item.messages.last.text, contains(reason));
      expect(_primary(tester, '検収を完了する').onPressed, isNull);
      for (final tile in tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      )) {
        expect(tile.onChanged, isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a stale confirmation cannot accept a newer published version', (
    tester,
  ) async {
    _viewport(tester, const Size(390, 844));
    final app = await _account();
    addTearDown(app.dispose);
    final repository = app.repository as MockOpcRepository;
    await tester.pumpWidget(
      _host(app, AcceptancePage(app: app, id: 'OPC-1017')),
    );
    await _checkAll(tester);
    await tester.tap(find.text('検収を完了する'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await repository.requestRevision('OPC-1017', 1, '検索表示を調整してください。');
      await repository.logout();
      await repository.login('member@opc.demo', 'demo1234');
      await repository.submitDelivery(
        'OPC-1017',
        const Delivery(
          version: 2,
          sourceName: 'opc-inquiry-v1.0.1.zip',
          sourceRef: 'v1.0.1 · c76493e',
          guideName: '操作説明書-v1.0.1.pdf',
          testName: '確認資料-v1.0.1.pdf',
          note: '検索表示を調整しました。',
        ),
      );
      await repository.simulateDeliveryPublication('OPC-1017');
      await repository.logout();
      await repository.login('customer@opc.demo', 'demo1234');
    });
    await tester.tap(find.widgetWithText(FilledButton, '検収を完了する').last);
    await tester.pumpAndSettle();
    expect(repository.detail('OPC-1017').status, WorkStatus.awaitingAcceptance);
    expect(find.text('公開中の最新納品バージョンを確認してください。'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);
    expect(_primary(tester, '検収を完了する').onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('message and file previews stay within the mobile app', (
    tester,
  ) async {
    _viewport(tester, const Size(320, 640));
    final app = await _account();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      _host(app, ProjectPage(app: app, id: 'OPC-1028'), textScale: 1.5),
    );
    await tester.tap(find.text('メッセージを送る'));
    await tester.pumpAndSettle();
    const message = '説明書の検索手順について確認したいです。';
    await tester.enterText(find.byType(TextFormField), message);
    await tester.ensureVisible(find.byTooltip('メッセージを送信'));
    await tester.tap(find.byTooltip('メッセージを送信'));
    await tester.pumpAndSettle();
    expect(app.repository.detail('OPC-1028').messages.last.text, message);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _host(app, AcceptancePage(app: app, id: 'OPC-1017'), textScale: 1.5),
    );
    await tester.ensureVisible(find.text('納品ファイル・操作説明書'));
    await tester.tap(find.text('納品ファイル・操作説明書'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('操作説明書-v1.0.pdf'));
    await tester.tap(find.text('操作説明書-v1.0.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Mock プレビュー'), findsNothing);
    final delivery = app.repository.detail('OPC-1017').deliveries.single;
    expect(find.text('対象バージョン：${delivery.sourceRef}'), findsOneWidget);
    expect(find.text('実ファイルの取得・配信は、今後の API 接続で対応します。'), findsOneWidget);
    expect(find.textContaining('操作説明のサンプル'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  const sizes = [Size(320, 640), Size(390, 844), Size(844, 390)];
  for (final size in sizes) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.5]) {
        for (final screen in ['project', 'delivery', 'acceptance']) {
          testWidgets(
            '$screen fits ${size.width}x${size.height} ${brightness.name} text $scale',
            (tester) async {
              _viewport(tester, size);
              final app = await _account(provider: screen != 'acceptance');
              addTearDown(app.dispose);
              final Widget page = switch (screen) {
                'project' => ProjectPage(app: app, id: 'OPC-1028'),
                'delivery' => DeliveryPage(app: app, id: 'OPC-1028'),
                _ => AcceptancePage(app: app, id: 'OPC-1017'),
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
            },
          );
        }
      }
    }
  }
}
