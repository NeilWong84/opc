import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/reference_download.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/features/reference_widgets.dart';
import 'package:opc_app/l10n/app_localizations.dart';

class _Store implements ReferenceFileStore {
  final files = <String, List<int>>{};
  final finished = <String>[];
  final removed = <String>[];
  final opened = <String>[];
  final exported = <String>[];
  Completer<void>? appendGate;
  Completer<void>? exportGate;
  int next = 0;

  @override
  Future<String> begin(String name, String mime, int size) async {
    final handle = '${next++}-$name';
    files[handle] = [];
    return handle;
  }

  @override
  Future<void> append(String handle, Uint8List bytes) async {
    await appendGate?.future;
    files[handle]!.addAll(bytes);
  }

  @override
  Future<void> finish(String handle, int size) async {
    expect(files[handle]!.length, size);
    finished.add(handle);
  }

  @override
  Future<void> remove(String handle) async {
    removed.add(handle);
    files.remove(handle);
  }

  @override
  Future<bool> open(String handle, String mime) async {
    opened.add(handle);
    return true;
  }

  @override
  Future<bool> export(String handle, String name, String mime) async {
    exported.add(handle);
    await exportGate?.future;
    return true;
  }
}

Future<AppController> _app() async {
  final repository = MockOpcRepository(delay: Duration.zero);
  await repository.login('member@opc.demo', 'demo1234');
  final app = AppController(repository);
  addTearDown(app.dispose);
  return app;
}

Widget _host(
  AppController app,
  _Store store, {
  String id = 'notes',
  bool compact = false,
  bool failFirst = false,
}) => MaterialApp(
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(
    body: SingleChildScrollView(
      child: ReferenceDownloadButton(
        app: app,
        taskId: 'DEV-1036',
        referenceId: id,
        store: store,
        compact: compact,
        failFirst: failFirst,
      ),
    ),
  ),
);

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (done()) return;
  }
  fail('Transfer did not reach expected state');
}

void main() {
  testWidgets(
    'an open sheet retains the original file when its row is reused',
    (tester) async {
      final app = await _app();
      final store = _Store()..appendGate = Completer<void>();
      final selected = ValueNotifier('notes');
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: selected,
              builder: (_, id, _) => ReferenceDownloadButton(
                app: app,
                taskId: 'DEV-1036',
                referenceId: id,
                compact: true,
                store: store,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reference-download-notes')));
      await _until(tester, () => store.files.isNotEmpty);
      selected.value = 'inquiry-detail';
      await tester.pump();
      await app.setLocale(const Locale('zh'));
      await tester.pump();
      expect(
        find.text(app.repository.reference('DEV-1036', 'notes').fileName),
        findsOneWidget,
      );
      expect(
        find.text(
          app.repository.reference('DEV-1036', 'inquiry-detail').fileName,
        ),
        findsNothing,
      );
      store.appendGate!.complete();
      await _until(tester, () => store.finished.isNotEmpty);
      expect(store.finished.single, endsWith('補足事項.md'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completion saves original bytes and open/export use saved handle',
    (tester) async {
      final app = await _app();
      final store = _Store();
      await tester.pumpWidget(_host(app, store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('download-start-notes')));
      await _until(tester, () => store.finished.isNotEmpty);
      await tester.pumpAndSettle();
      final source = await rootBundle.load('assets/references/notes.md');
      expect(
        store.files[store.finished.single],
        source.buffer.asUint8List(source.offsetInBytes, source.lengthInBytes),
      );
      await tester.tap(find.byKey(const Key('download-open')));
      await tester.pumpAndSettle();
      store.exportGate = Completer<void>();
      await tester.tap(find.byKey(const Key('download-export')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('download-export')));
      await tester.pump();
      expect(
        store.exported.length,
        1,
        reason: 'Only one system chooser may be active.',
      );
      store.exportGate!.complete();
      await tester.pumpAndSettle();
      expect(store.opened, store.finished);
      expect(store.exported, store.finished);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel pending write cleans the partial file and permits retry',
    (tester) async {
      final app = await _app();
      final store = _Store()..appendGate = Completer<void>();
      await tester.pumpWidget(_host(app, store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('download-start-notes')));
      await _until(tester, () => store.files.isNotEmpty);
      await tester.tap(find.byKey(const Key('download-cancel')));
      await tester.pump();
      store.appendGate!.complete();
      await _until(tester, () => store.removed.isNotEmpty);
      expect(store.finished, isEmpty);
      expect(find.byKey(const Key('download-open')), findsNothing);
      store.appendGate = null;
      await tester.tap(find.byKey(const ValueKey('download-start-notes')));
      await _until(tester, () => store.finished.isNotEmpty);
      expect(store.files.length, 1);
    },
  );

  testWidgets(
    'withdrawal clears the open sheet filename and cancels its write',
    (tester) async {
      final app = await _app();
      final store = _Store()..appendGate = Completer<void>();
      final name = app.repository.reference('DEV-1036', 'notes').fileName;
      await tester.pumpWidget(_host(app, store, compact: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reference-download-notes')));
      await _until(tester, () => store.files.isNotEmpty);
      expect(find.text(name), findsOneWidget);
      await app.run(
        () => (app.repository as MockOpcRepository).simulateReferenceWithdrawal(
          'DEV-1036',
          'notes',
        ),
      );
      await tester.pump();
      store.appendGate!.complete();
      await _until(tester, () => store.removed.isNotEmpty);
      expect(find.text(name), findsNothing);
      expect(find.byKey(const Key('download-open')), findsNothing);
      expect(store.finished, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing image discards old in-flight download state', (
    tester,
  ) async {
    final app = await _app();
    final store = _Store()..appendGate = Completer<void>();
    await tester.pumpWidget(_host(app, store, id: 'inquiry-overview'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('download-start-inquiry-overview')),
    );
    await _until(tester, () => store.files.isNotEmpty);
    await tester.pumpWidget(_host(app, store, id: 'inquiry-detail'));
    await tester.pump();
    store.appendGate!.complete();
    await _until(tester, () => store.removed.isNotEmpty);
    expect(store.finished, isEmpty);
    expect(
      find.byKey(const ValueKey('download-start-inquiry-detail')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('download-open')), findsNothing);
  });

  testWidgets(
    'failed read offers retry and never reports saved before finish',
    (tester) async {
      final app = await _app();
      final store = _Store();
      await tester.pumpWidget(_host(app, store, failFirst: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('download-start-notes')));
      await tester.pumpAndSettle();
      expect(store.files, isEmpty);
      expect(find.byKey(const Key('download-open')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('download-start-notes')));
      await _until(tester, () => store.finished.isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('download-open')), findsOneWidget);
    },
  );
}
