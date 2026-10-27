import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/theme.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/hall_pages.dart';
import 'package:opc_app/features/reference_pages.dart';
import 'package:opc_app/features/reference_preview_page.dart';
import 'package:opc_app/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() completed,
  String description,
) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (completed()) return;
  }
  fail('Timed out waiting for $description');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;
  setUp(() => surfaceConverted = false);

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot(name);
  }

  Future<void> showPage(
    WidgetTester tester,
    AppController app,
    Widget page, {
    Brightness brightness = Brightness.light,
  }) async {
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
  }

  testWidgets(
    'bundled video plays and original bytes save through the native store',
    (tester) async {
      final repository = MockOpcRepository(delay: Duration.zero);
      await repository.login('member@opc.demo', 'demo1234');
      final app = AppController(repository);
      addTearDown(app.dispose);
      await showPage(
        tester,
        app,
        ReferencePreviewPage(
          app: app,
          taskId: 'DEV-1036',
          referenceId: 'workflow-video',
        ),
      );
      await _waitFor(
        tester,
        () =>
            find.byType(VideoPlayer).evaluate().isNotEmpty &&
            tester
                .widget<VideoPlayer>(find.byType(VideoPlayer).first)
                .controller
                .value
                .isInitialized,
        'native video initialization',
      );
      final video = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer).first)
          .controller;
      expect(
        video.value.isPlaying,
        isFalse,
        reason: 'References never autoplay.',
      );
      expect(video.value.duration.inSeconds, greaterThanOrEqualTo(7));
      expect(video.value.duration.inSeconds, lessThanOrEqualTo(9));
      await _tap(tester, find.byKey(const ValueKey('preview-video-mute')));
      await _waitFor(
        tester,
        () => video.value.volume == 0,
        'video mute control',
      );
      await _tap(tester, find.byKey(const ValueKey('preview-fullscreen')));
      expect(
        find.byKey(const ValueKey('preview-exit-fullscreen')),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const ValueKey('preview-exit-fullscreen')));
      await _tap(tester, find.byKey(const ValueKey('preview-video-play')));
      await _waitFor(
        tester,
        () => video.value.position.inMilliseconds > 0,
        'real video playback',
      );
      expect(video.value.hasError, isFalse);
      await screenshot(tester, 'reference-native-video-playing');
      await tester.ensureVisible(
        find.byKey(const ValueKey('preview-video-play')),
      );
      await tester.tap(find.byKey(const ValueKey('preview-video-play')));
      await _waitFor(
        tester,
        () => !video.value.isPlaying,
        'video pause control',
      );
      await video.seekTo(const Duration(seconds: 2));
      expect(video.value.isPlaying, isFalse);
      expect(video.value.volume, 0);

      await showPage(
        tester,
        app,
        ReferencePreviewPage(
          app: app,
          taskId: 'DEV-1036',
          referenceId: 'notes',
        ),
      );
      await _tap(tester, find.byKey(const ValueKey('download-start-notes')));
      await _waitFor(
        tester,
        () => find.byKey(const Key('download-open')).evaluate().isNotEmpty,
        'native original-file completion',
      );
      expect(find.byKey(const Key('download-export')), findsOneWidget);
      expect(find.byKey(const Key('download-cancel')), findsNothing);
      expect(repository.reference('DEV-1036', 'notes').publishedVersion, 3);
      await tester.ensureVisible(find.byKey(const Key('download-open')));
      await tester.pumpAndSettle();
      await screenshot(tester, 'reference-native-download-completed');
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'reference formats and states render in both languages and themes',
    (tester) async {
      final repository = MockOpcRepository(delay: Duration.zero);
      await repository.login('member@opc.demo', 'demo1234');
      final app = AppController(repository);
      addTearDown(app.dispose);

      // Use a separate repository for TXT so the default hall remains at its
      // original two tasks and DEV-1036 keeps its nine published references.
      final txtData = await rootBundle.load('assets/references/notes.txt');
      final txtContents = utf8.decode(
        txtData.buffer.asUint8List(
          txtData.offsetInBytes,
          txtData.lengthInBytes,
        ),
      );
      final textRepository = MockOpcRepository(
        delay: Duration.zero,
        taskFixtures: [
          WorkItem(
            id: 'TEXT-REFERENCE',
            title: 'テキスト資料の確認',
            description: '公開済みの TXT 原文を確認する合成データです。',
            category: 'Web アプリ',
            duration: '相談して決めたい',
            status: WorkStatus.published,
            ownerId: 'sample-text-customer',
            publishedVersion: 1,
            complianceApproved: true,
            technicalApproved: true,
            createdAt: DateTime.utc(2026, 10, 13),
            references: [
              TaskReference(
                id: 'plain-text',
                fileName: '補足事項.txt',
                kind: ReferenceKind.text,
                sizeBytes: txtData.lengthInBytes,
                assetPath: 'assets/references/notes.txt',
                publishedVersion: 1,
                text: txtContents,
              ),
            ],
          ),
        ],
      );
      await textRepository.login('member@opc.demo', 'demo1234');
      final textApp = AppController(textRepository);
      addTearDown(textApp.dispose);

      for (final language in ['ja', 'zh']) {
        await app.setLocale(Locale(language));
        await textApp.setLocale(Locale(language));
        for (final brightness in Brightness.values) {
          final prefix = 'reference-$language-${brightness.name}';
          await showPage(
            tester,
            app,
            HallPage(app: app, onOpen: (_) {}, onNotifications: () {}),
            brightness: brightness,
          );
          expect(repository.hall(), hasLength(2));
          await screenshot(tester, '$prefix-00-hall');
          await tester.ensureVisible(
            find.byKey(const ValueKey('hall-references-DEV-1036')),
          );
          await tester.pumpAndSettle();
          await screenshot(tester, '$prefix-00-hall-references');

          await showPage(
            tester,
            app,
            TaskDetailPage(app: app, id: 'DEV-1036'),
            brightness: brightness,
          );
          await screenshot(tester, '$prefix-00-detail');
          await tester.ensureVisible(
            find.byKey(const Key('task-reference-section')),
          );
          await tester.pumpAndSettle();
          await screenshot(tester, '$prefix-00-detail-references');

          await showPage(
            tester,
            app,
            ReferenceListPage(app: app, taskId: 'DEV-1036'),
            brightness: brightness,
          );
          expect(find.text('未公開_顧客メモ.md'), findsNothing);
          expect(find.text('旧版_画面イメージ.png'), findsNothing);
          await screenshot(tester, '$prefix-01-list');

          const previews = <(String, String)>[
            ('02-image', 'inquiry-overview'),
            ('03-video', 'workflow-video'),
            ('04-word', 'requirements'),
            ('05-pdf', 'workflow-pdf'),
            ('06-table', 'fields'),
            ('07-slides', 'screens'),
            ('08-markdown', 'notes'),
            ('09-csv', 'sample-data'),
          ];
          for (final preview in previews) {
            await showPage(
              tester,
              app,
              ReferencePreviewPage(
                app: app,
                taskId: 'DEV-1036',
                referenceId: preview.$2,
              ),
              brightness: brightness,
            );
            if (preview.$2 == 'workflow-video') {
              await _waitFor(
                tester,
                () =>
                    find.byType(VideoPlayer).evaluate().isNotEmpty &&
                    tester
                        .widget<VideoPlayer>(find.byType(VideoPlayer).first)
                        .controller
                        .value
                        .isInitialized,
                'video preview initialization',
              );
              expect(
                tester
                    .widget<VideoPlayer>(find.byType(VideoPlayer).first)
                    .controller
                    .value
                    .isPlaying,
                isFalse,
              );
            }
            final context = tester.element(find.byType(Scaffold).first);
            expect(Localizations.localeOf(context).languageCode, language);
            expect(Theme.of(context).brightness, brightness);
            expect(find.byType(Banner), findsNothing);
            await screenshot(tester, '$prefix-${preview.$1}');
          }

          await showPage(
            tester,
            textApp,
            ReferencePreviewPage(
              app: textApp,
              taskId: 'TEXT-REFERENCE',
              referenceId: 'plain-text',
            ),
            brightness: brightness,
          );
          expect(find.text('補足事項.txt'), findsOneWidget);
          expect(find.byKey(const ValueKey('preview-text-raw')), findsNothing);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is SelectableText && widget.data == txtContents,
            ),
            findsOneWidget,
          );
          await screenshot(tester, '$prefix-10-txt');

          for (final state in [
            ReferencePreviewState.preparing,
            ReferencePreviewState.failed,
            ReferencePreviewState.unsupported,
          ]) {
            await repository.simulateReferenceState(
              'DEV-1036',
              'requirements',
              state,
            );
            await showPage(
              tester,
              app,
              ReferencePreviewPage(
                app: app,
                taskId: 'DEV-1036',
                referenceId: 'requirements',
              ),
              brightness: brightness,
            );
            expect(
              repository.reference('DEV-1036', 'requirements').previewState,
              state,
            );
            expect(
              find.byKey(const ValueKey('download-start-requirements')),
              findsOneWidget,
            );
            await screenshot(tester, '$prefix-state-${state.name}');
          }
          await repository.simulateReferenceState(
            'DEV-1036',
            'requirements',
            ReferencePreviewState.ready,
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
