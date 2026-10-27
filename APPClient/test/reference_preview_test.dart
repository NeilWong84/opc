import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/theme.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/reference_preview_page.dart';
import 'package:opc_app/features/reference_widgets.dart';
import 'package:opc_app/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final calls = <String>[];
  final positions = <int, Duration>{};
  int nextId = 0;
  bool fail = false;

  @override
  Future<void> init() async {}

  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
    final id = nextId++;
    final stream = streams[id] = StreamController<VideoEvent>();
    calls.add('create:${options.dataSource.asset}');
    if (fail) {
      stream.addError(Exception('fixture playback unavailable'));
    } else {
      stream.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 8),
          size: const Size(640, 360),
        ),
      );
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose:$playerId');
    await streams[playerId]!.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async => calls.add('play:$playerId');

  @override
  Future<void> pause(int playerId) async => calls.add('pause:$playerId');

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      calls.add('volume:$volume');

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
    positions[playerId] = position;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}
}

Future<AppController> _provider() async {
  final repository = MockOpcRepository(delay: Duration.zero);
  await repository.login('member@opc.demo', 'demo1234');
  return AppController(repository);
}

void _viewport(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _host(
  AppController app,
  String referenceId, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => AnimatedBuilder(
  animation: app,
  builder: (context, _) => MaterialApp(
    locale: app.locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: opcTheme(brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: ReferencePreviewPage(
      app: app,
      taskId: 'DEV-1036',
      referenceId: referenceId,
    ),
  ),
);

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late _VideoPlatform videoPlatform;
  setUp(() {
    videoPlatform = _VideoPlatform();
    VideoPlayerPlatform.instance = videoPlatform;
  });

  testWidgets(
    'image swipe and thumbnails switch originals; zoomed pan does not',
    (tester) async {
      _viewport(tester);
      final app = await _provider();
      addTearDown(app.dispose);
      await tester.pumpWidget(_host(app, 'inquiry-overview'));
      await tester.pumpAndSettle();
      expect(find.text('画面イメージ_01.png'), findsWidgets);
      final viewer = find.byKey(const ValueKey('reference-image-viewer'));
      await tester.drag(viewer, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(find.text('画面イメージ_02.png'), findsWidgets);
      var interactive = tester.widget<InteractiveViewer>(viewer);
      interactive.transformationController!.value = Matrix4.diagonal3Values(
        2,
        2,
        1,
      );
      await tester.pump();
      await tester.drag(viewer, const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(find.text('画面イメージ_02.png'), findsWidgets);
      await _tap(tester, 'reference-image-inquiry-overview');
      expect(find.text('画面イメージ_01.png'), findsWidgets);
      interactive = tester.widget<InteractiveViewer>(viewer);
      expect(
        interactive.transformationController!.value.getMaxScaleOnAxis(),
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'document page jump validates and preserves white paper in dark Chinese',
    (tester) async {
      _viewport(tester);
      final app = await _provider();
      addTearDown(app.dispose);
      await app.setLocale(const Locale('zh'));
      await tester.pumpWidget(
        _host(app, 'requirements', brightness: Brightness.dark),
      );
      await tester.pumpAndSettle();
      expect(find.text('文档预览'), findsOneWidget);
      expect(find.text('お問い合わせ管理ツール · 要件整理書'), findsOneWidget);
      final paper = tester.widget<Container>(
        find.byKey(const ValueKey('reference-document-paper')),
      );
      expect(paper.color, Colors.white);
      await _tap(tester, 'preview-page-number');
      await tester.enterText(
        find.byKey(const ValueKey('preview-page-jump-field')),
        '99',
      );
      await tester.tap(find.widgetWithText(FilledButton, '跳转'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1 至 3 的页码'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('preview-page-jump-field')),
        '2',
      );
      await tester.tap(find.widgetWithText(FilledButton, '跳转'));
      await tester.pumpAndSettle();
      expect(find.text('02 対象範囲'), findsOneWidget);
      await tester.tap(find.byTooltip('放大'));
      await tester.pump();
      expect(
        tester
            .widget<InteractiveViewer>(
              find.byKey(const ValueKey('reference-document-viewer')),
            )
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        1.5,
      );
      await _tap(tester, 'preview-next-page');
      expect(find.text('03 確認ポイント'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'spreadsheet search selects matching cells and changes worksheets',
    (tester) async {
      _viewport(tester);
      final app = await _provider();
      addTearDown(app.dispose);
      await tester.pumpWidget(_host(app, 'fields'));
      await tester.pumpAndSettle();
      final horizontal = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('preview-table-horizontal')),
      );
      expect(horizontal.scrollDirection, Axis.horizontal);
      await tester.enterText(
        find.byKey(const ValueKey('preview-table-search')),
        '件名',
      );
      await tester.pumpAndSettle();
      expect(find.text('一致するセル 1 件'), findsOneWidget);
      expect(find.text('問い合わせID'), findsNothing);
      await tester.tap(find.widgetWithText(InkWell, '件名').last);
      await tester.pump();
      expect(find.text('A3   件名'), findsOneWidget);
      await tester.tap(find.byTooltip('検索をクリア'));
      await tester.pumpAndSettle();
      await _tap(tester, 'preview-sheet-1');
      expect(find.text('in_progress'), findsOneWidget);
      expect(find.text('問い合わせID'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('slides keep their page when entering and leaving fullscreen', (
    tester,
  ) async {
    _viewport(tester);
    final app = await _provider();
    addTearDown(app.dispose);
    await tester.pumpWidget(_host(app, 'screens'));
    await tester.pumpAndSettle();
    await _tap(tester, 'preview-slide-thumbnail-1');
    expect(find.text('2 / 3'), findsOneWidget);
    await _tap(tester, 'preview-fullscreen');
    expect(find.byType(ReferenceDownloadButton), findsNothing);
    await _tap(tester, 'preview-next-page');
    expect(find.text('3 / 3'), findsOneWidget);
    await _tap(tester, 'preview-exit-fullscreen');
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byType(ReferenceDownloadButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Markdown raw and formatted views preserve text and locale changes',
    (tester) async {
      _viewport(tester);
      final app = await _provider();
      addTearDown(app.dispose);
      final original = app.repository.reference('DEV-1036', 'notes').text;
      await tester.pumpWidget(_host(app, 'notes'));
      await tester.pumpAndSettle();
      await _tap(tester, 'preview-text-raw');
      expect(find.text(original), findsOneWidget);
      await _tap(tester, 'preview-font-larger');
      expect(
        tester
            .widget<SelectableText>(
              find.byWidgetPredicate(
                (widget) => widget is SelectableText && widget.data == original,
              ),
            )
            .style!
            .fontSize,
        16,
      );
      await app.setLocale(const Locale('zh'));
      await tester.pumpAndSettle();
      expect(find.text(original), findsOneWidget);
      expect(find.text('文本预览'), findsOneWidget);
      await _tap(tester, 'preview-text-formatted');
      expect(find.text(original), findsNothing);
      expect(app.repository.reference('DEV-1036', 'notes').text, original);
      expect(tester.takeException(), isNull);
    },
  );

  for (final state in [
    ReferencePreviewState.preparing,
    ReferencePreviewState.failed,
  ]) {
    testWidgets('$state can retry without disabling original downloads', (
      tester,
    ) async {
      _viewport(tester);
      final app = await _provider();
      addTearDown(app.dispose);
      await (app.repository as MockOpcRepository).simulateReferenceState(
        'DEV-1036',
        'requirements',
        state,
      );
      await tester.pumpWidget(_host(app, 'requirements'));
      await tester.pumpAndSettle();
      expect(find.byType(ReferenceDownloadButton), findsOneWidget);
      await tester.tap(
        find.text(state == ReferencePreviewState.preparing ? '準備状況を確認' : '再試行'),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reference-document-paper')),
        findsOneWidget,
      );
      expect(
        app.repository.reference('DEV-1036', 'requirements').previewState,
        ReferencePreviewState.ready,
      );
    });
  }

  testWidgets(
    'unsupported reference retains download while withdrawal clears content',
    (tester) async {
      _viewport(tester);
      final app = await _provider();
      addTearDown(app.dispose);
      final repository = app.repository as MockOpcRepository;
      await repository.simulateReferenceState(
        'DEV-1036',
        'requirements',
        ReferencePreviewState.unsupported,
      );
      await tester.pumpWidget(_host(app, 'requirements'));
      await tester.pumpAndSettle();
      expect(find.text('プレビュー非対応'), findsOneWidget);
      expect(find.byType(ReferenceDownloadButton), findsOneWidget);
      await app.run(
        () =>
            repository.simulateReferenceWithdrawal('DEV-1036', 'requirements'),
      );
      await tester.pumpAndSettle();
      expect(find.text('この資料へのアクセス権がありません'), findsOneWidget);
      expect(find.byType(ReferenceDownloadButton), findsNothing);
      expect(find.text('要件整理_v1.docx'), findsNothing);
    },
  );

  testWidgets(
    'video starts paused, seeks and mutes, then is disposed on fullscreen access loss',
    (tester) async {
      _viewport(tester);
      final app = await _provider();
      addTearDown(app.dispose);
      final repository = app.repository as MockOpcRepository;
      await tester.pumpWidget(_host(app, 'workflow-video'));
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(
        videoPlatform.calls.where((call) => call.startsWith('play:')),
        isEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('preview-video-play')));
      await tester.pump();
      expect(videoPlatform.calls, contains('play:0'));
      await tester.tap(find.byKey(const ValueKey('preview-video-play')));
      await tester.pumpAndSettle();
      await _tap(tester, 'preview-video-mute');
      expect(videoPlatform.calls, contains('volume:0.0'));
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('preview-video-seek')),
      );
      slider.onChangeStart!(3000);
      slider.onChanged!(3000);
      slider.onChangeEnd!(3000);
      await tester.pumpAndSettle();
      expect(videoPlatform.calls, contains('seek:3000'));
      await _tap(tester, 'preview-fullscreen');
      await tester.tap(find.byKey(const ValueKey('preview-video-play')));
      await tester.pump();
      await app.run(
        () => repository.simulateReferenceWithdrawal(
          'DEV-1036',
          'workflow-video',
        ),
      );
      await tester.pumpAndSettle();
      // video_player cancels its platform event stream asynchronously.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(videoPlatform.calls, contains('dispose:0'));
      expect(find.byType(VideoPlayer), findsNothing);
      expect(
        find.byKey(const ValueKey('preview-exit-fullscreen')),
        findsNothing,
      );
      expect(find.text('この資料へのアクセス権がありません'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('video pauses in background and is not restarted on resume', (
    tester,
  ) async {
    _viewport(tester);
    final app = await _provider();
    addTearDown(app.dispose);
    await tester.pumpWidget(_host(app, 'workflow-video'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preview-video-play')));
    await tester.pump();
    final plays = videoPlatform.calls
        .where((call) => call.startsWith('play:'))
        .length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller
          .value
          .isPlaying,
      isFalse,
    );
    expect(
      videoPlatform.calls.where((call) => call.startsWith('play:')).length,
      plays,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final locale in ['ja', 'zh']) {
    for (final brightness in Brightness.values) {
      for (final referenceId in [
        'requirements',
        'workflow-pdf',
        'fields',
        'sample-data',
        'screens',
        'notes',
        'workflow-video',
      ]) {
        testWidgets(
          '$referenceId $locale ${brightness.name} fits small large-text viewport',
          (tester) async {
            _viewport(tester, size: const Size(320, 640));
            final app = await _provider();
            addTearDown(app.dispose);
            await app.setLocale(Locale(locale));
            await tester.pumpWidget(
              _host(app, referenceId, brightness: brightness, textScale: 1.5),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, -1000),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  }
}
