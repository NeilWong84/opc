import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/theme.dart';
import 'package:opc_app/core/widgets.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/hall_pages.dart';
import 'package:opc_app/features/reference_pages.dart';
import 'package:opc_app/features/reference_preview_page.dart';
import 'package:opc_app/features/reference_widgets.dart';
import 'package:opc_app/l10n/app_localizations.dart';

class _DeferredReferenceRepository extends MockOpcRepository {
  _DeferredReferenceRepository() : super(delay: Duration.zero);

  final gate = Completer<void>();

  @override
  Future<void> simulateReferenceState(
    String taskId,
    String referenceId,
    ReferencePreviewState state,
  ) async {
    await gate.future;
    await super.simulateReferenceState(taskId, referenceId, state);
  }
}

void _viewport(WidgetTester tester, {double width = 390, double scale = 1}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<AppController> _provider({MockOpcRepository? repository}) async {
  final data = repository ?? MockOpcRepository(delay: Duration.zero);
  await data.login('member@opc.demo', 'demo1234');
  final app = AppController(data);
  addTearDown(app.dispose);
  return app;
}

Widget _host(AppController app, Widget page) => AnimatedBuilder(
  animation: app,
  builder: (context, _) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: app.locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: opcTheme(Brightness.light),
    darkTheme: opcTheme(Brightness.dark),
    themeMode: app.themeMode,
    home: page,
  ),
);

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

HallPage _hall(AppController app) =>
    HallPage(app: app, onOpen: (_) {}, onNotifications: () {});

Finder _summary(String taskId) => find.byWidgetPredicate(
  (widget) => widget is HallReferenceSummary && widget.item.id == taskId,
);

WorkItem _textTask() => WorkItem(
  id: 'TEXT-ONLY',
  title: '予約管理の開発相談',
  description: '参考ファイルを使わない文章のみの依頼です。',
  category: 'Web アプリ',
  duration: '相談して決めたい',
  status: WorkStatus.published,
  ownerId: 'demo-client-text',
  publishedVersion: 1,
  complianceApproved: true,
  technicalApproved: true,
  createdAt: DateTime.utc(2026, 10, 13),
);

void main() {
  testWidgets('text-only tasks reserve no media space in hall or detail', (
    tester,
  ) async {
    _viewport(tester);
    final app = await _provider(
      repository: MockOpcRepository(
        delay: Duration.zero,
        taskFixtures: [_textTask()],
      ),
    );
    await tester.pumpWidget(_host(app, _hall(app)));
    await tester.pumpAndSettle();
    expect(tester.getSize(_summary('TEXT-ONLY')).height, 0);
    expect(
      find.byKey(const ValueKey('hall-references-TEXT-ONLY')),
      findsNothing,
    );

    await tester.pumpWidget(
      _host(app, TaskDetailPage(app: app, id: 'TEXT-ONLY')),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TaskReferenceSection)).height, 0);
    expect(find.byKey(const Key('task-reference-section')), findsNothing);
    expect(find.byType(ReferenceThumbnail), findsNothing);
    expect(find.byKey(const Key('reference-view-all')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attachment-only tasks use a file row without a thumbnail area', (
    tester,
  ) async {
    _viewport(tester);
    final app = await _provider();
    await tester.pumpWidget(_host(app, _hall(app)));
    await tester.pumpAndSettle();
    final summary = _summary('DEV-1039');
    expect(
      find.descendant(of: summary, matching: find.byType(ReferenceThumbnail)),
      findsNothing,
    );
    expect(
      find.descendant(of: summary, matching: find.byType(ReferenceFileRow)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('見積テンプレート.xlsx')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('資料 1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hall shows published 2 image, 1 video and 6 attachment counts in both languages',
    (tester) async {
      _viewport(tester);
      final app = await _provider();
      await tester.pumpWidget(_host(app, _hall(app)));
      await tester.pumpAndSettle();
      final summary = _summary('DEV-1036');
      expect(
        find.descendant(of: summary, matching: find.byType(ReferenceThumbnail)),
        findsNWidgets(3),
      );
      expect(find.text('画像 2 · 動画 1 · 資料 6'), findsOneWidget);
      expect(find.text('未公開_顧客メモ.md'), findsNothing);
      expect(find.text('旧版_画面イメージ.png'), findsNothing);
      await app.setLocale(const Locale('zh'));
      await tester.pumpAndSettle();
      expect(find.text('图片 2 · 视频 1 · 附件 6'), findsOneWidget);
      expect(find.text('画像 2 · 動画 1 · 資料 6'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detail view-all opens the list and each reference preview route',
    (tester) async {
      _viewport(tester);
      final app = await _provider();
      final repository = app.repository as MockOpcRepository;
      // Native ready-video initialization and playback run in integration_test.
      await repository.simulateReferenceState(
        'DEV-1036',
        'workflow-video',
        ReferencePreviewState.failed,
      );
      await tester.pumpWidget(
        _host(app, TaskDetailPage(app: app, id: 'DEV-1036')),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('reference-view-all')));
      expect(find.byType(ReferenceListPage), findsOneWidget);
      expect(find.byType(ReferenceFileRow), findsNWidgets(6));
      expect(find.text('未公開_顧客メモ.md'), findsNothing);
      expect(find.text('旧版_画面イメージ.png'), findsNothing);

      for (final reference in repository.references('DEV-1036')) {
        final media =
            reference.kind == ReferenceKind.image ||
            reference.kind == ReferenceKind.video;
        final entry = ValueKey(
          '${media ? 'reference-thumb' : 'reference-open'}-${reference.id}',
        );
        await _tap(tester, find.byKey(entry));
        expect(find.byType(ReferencePreviewPage), findsOneWidget);
        final preview = tester.widget<ReferencePreviewPage>(
          find.byType(ReferencePreviewPage),
        );
        expect(preview.taskId, 'DEV-1036');
        expect(preview.referenceId, reference.id);
        expect(find.text(reference.fileName), findsWidgets);
        expect(
          find.byKey(ValueKey('download-start-${reference.id}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, find.byTooltip('戻る'));
        expect(find.byType(ReferenceListPage), findsOneWidget);
      }
    },
  );

  testWidgets(
    'reference scenarios await their state change before opening a preview',
    (tester) async {
      _viewport(tester);
      final repository = _DeferredReferenceRepository();
      final app = await _provider(repository: repository);
      await tester.pumpWidget(_host(app, ReferenceScenariosPage(app: app)));
      await tester.pumpAndSettle();
      final button = find.text('プレビューを準備中').first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.byType(ReferencePreviewPage), findsNothing);
      expect(app.busy, isTrue);
      repository.gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ReferencePreviewPage), findsOneWidget);
      expect(
        repository.reference('DEV-1036', 'requirements').previewState,
        ReferencePreviewState.preparing,
      );
      expect(repository.detail('DEV-1036').publishedVersion, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TXT previews preserve literal punctuation instead of rendering Markdown',
    (tester) async {
      _viewport(tester);
      const original = '# 見出しとして変換しない原文\n**強調せず、そのまま表示**\n客户原文';
      final fixture = _textTask().copyWith(
        references: [
          TaskReference(
            id: 'plain-text',
            fileName: '補足事項.txt',
            kind: ReferenceKind.text,
            sizeBytes: 559,
            assetPath: 'assets/references/notes.txt',
            publishedVersion: 1,
            text: original,
          ),
        ],
      );
      final app = await _provider(
        repository: MockOpcRepository(
          delay: Duration.zero,
          taskFixtures: [fixture],
        ),
      );
      await tester.pumpWidget(
        _host(
          app,
          ReferencePreviewPage(
            app: app,
            taskId: fixture.id,
            referenceId: 'plain-text',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('TXT'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('preview-text-formatted')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('preview-text-raw')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == original,
        ),
        findsOneWidget,
      );
      await app.setLocale(const Locale('zh'));
      await tester.pumpAndSettle();
      expect(find.text('補足事項.txt'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == original,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('revoking an account removes visible list names and thumbnails', (
    tester,
  ) async {
    _viewport(tester);
    final app = await _provider();
    final repository = app.repository as MockOpcRepository;
    await tester.pumpWidget(
      _host(app, ReferenceListPage(app: app, taskId: 'DEV-1036')),
    );
    await tester.pumpAndSettle();
    expect(find.text('要件整理_v1.docx'), findsOneWidget);
    await app.run(() => repository.simulateAccountAccess(authorized: false));
    await tester.pumpAndSettle();
    expect(find.byType(RepositoryUnavailablePage), findsOneWidget);
    expect(find.byType(ReferenceThumbnail), findsNothing);
    expect(find.byType(ReferenceFileRow), findsNothing);
    expect(find.text('要件整理_v1.docx'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'withdrawing a viewed reference clears its contents and download action',
    (tester) async {
      _viewport(tester);
      final app = await _provider();
      final repository = app.repository as MockOpcRepository;
      await tester.pumpWidget(
        _host(
          app,
          ReferencePreviewPage(
            app: app,
            taskId: 'DEV-1036',
            referenceId: 'notes',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('補足事項.md'), findsOneWidget);
      await app.run(
        () => repository.simulateReferenceWithdrawal('DEV-1036', 'notes'),
      );
      await tester.pumpAndSettle();
      expect(find.text('補足事項.md'), findsNothing);
      expect(find.byKey(const ValueKey('preview-text-paper')), findsNothing);
      expect(find.byKey(const ValueKey('download-start-notes')), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  for (final referenceId in ['private-client-memo', 'old-screen']) {
    testWidgets(
      '$referenceId cannot leak its filename through a direct route',
      (tester) async {
        _viewport(tester);
        final app = await _provider();
        await tester.pumpWidget(
          _host(
            app,
            ReferencePreviewPage(
              app: app,
              taskId: 'DEV-1036',
              referenceId: referenceId,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReferenceDownloadButton), findsNothing);
        expect(find.byType(ReferenceThumbnail), findsNothing);
        expect(find.text('未公開_顧客メモ.md'), findsNothing);
        expect(find.text('旧版_画面イメージ.png'), findsNothing);
        expect(find.byIcon(Icons.lock_outline), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in ['ja', 'zh']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final screen in ['hall', 'detail', 'list', 'attachment-only']) {
        testWidgets(
          '$screen fits $language ${mode.name} at 320 with 1.5 text scale',
          (tester) async {
            _viewport(tester, width: 320, scale: 1.5);
            final app = await _provider();
            await app.setLocale(Locale(language));
            app.setTheme(mode);
            final Widget page = switch (screen) {
              'hall' => _hall(app),
              'detail' => TaskDetailPage(app: app, id: 'DEV-1036'),
              'list' => ReferenceListPage(app: app, taskId: 'DEV-1036'),
              _ => ReferenceListPage(app: app, taskId: 'DEV-1039'),
            };
            await tester.pumpWidget(_host(app, page));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, -2600),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byType(Banner), findsNothing);
          },
        );
      }
    }
  }
}
