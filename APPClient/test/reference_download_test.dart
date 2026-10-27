import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/reference_download.dart';

class _MemoryFiles extends ReferenceFileStore {
  final files = <String, List<int>>{};
  final complete = <String>{};
  final removed = <String>[];
  int sequence = 0;
  int opens = 0;
  int exports = 0;
  bool failAppend = false;
  bool failFinish = false;
  bool exportAccepted = true;
  Future<void> Function()? onAppend;
  Future<void> Function()? onFinish;

  @override
  Future<String> begin(String fileName, String mimeType, int totalBytes) async {
    final handle = '${sequence++}:$fileName';
    files[handle] = [];
    return handle;
  }

  @override
  Future<void> append(String handle, Uint8List bytes) async {
    if (failAppend) throw StateError('storage unavailable');
    files[handle]!.addAll(bytes);
    await onAppend?.call();
  }

  @override
  Future<void> finish(String handle, int totalBytes) async {
    if (failFinish) throw StateError('flush failed');
    expect(files[handle]!.length, totalBytes);
    complete.add(handle);
    await onFinish?.call();
  }

  @override
  Future<void> remove(String handle) async {
    files.remove(handle);
    complete.remove(handle);
    removed.add(handle);
  }

  @override
  Future<bool> open(String handle, String mimeType) async {
    if (!complete.contains(handle)) throw StateError('file is missing');
    opens++;
    return true;
  }

  @override
  Future<bool> export(String handle, String fileName, String mimeType) async {
    if (!complete.contains(handle)) throw StateError('file is missing');
    exports++;
    return exportAccepted;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'server revocation after bytes arrive prevents a completed live download',
    () async {
      final store = _MemoryFiles();
      var allowed = true;
      final download = ReferenceDownloadController(
        load: () async {
          allowed = false;
          return ByteData(7);
        },
        fileName: 'private.txt',
        mimeType: 'text/plain',
        authorize: () {},
        authorizeRemote: () async {
          if (!allowed) throw StateError('Server access revoked');
        },
        store: store,
      );
      addTearDown(download.dispose);
      expect(await download.start(), isFalse);
      expect(download.state, ReferenceDownloadState.failed);
      expect(download.savedHandle, isNull);
      expect(store.files, isEmpty);
    },
  );

  test(
    'live saved file cannot be opened or exported after server revocation',
    () async {
      final store = _MemoryFiles();
      var allowed = true;
      final download = ReferenceDownloadController(
        load: () async => ByteData(7),
        fileName: 'private.txt',
        mimeType: 'text/plain',
        authorize: () {},
        authorizeRemote: () async {
          if (!allowed) throw StateError('Server access revoked');
        },
        store: store,
      );
      addTearDown(download.dispose);
      expect(await download.start(), isTrue);
      allowed = false;
      expect(await download.open(), isFalse);
      expect(await download.export(), isFalse);
      expect(store.opens, 0);
      expect(store.exports, 0);
    },
  );

  ReferenceDownloadController controller(
    _MemoryFiles store, {
    Future<ByteData> Function()? load,
    void Function()? authorize,
    String fileName = '参考資料.txt',
  }) {
    final result = ReferenceDownloadController(
      load: load ?? () async => ByteData.sublistView(Uint8List(40001)),
      fileName: fileName,
      mimeType: 'text/plain',
      authorize: authorize ?? () {},
      store: store,
    );
    addTearDown(result.dispose);
    return result;
  }

  test(
    'writes all real bytes with monotonic progress and atomic completion',
    () async {
      final store = _MemoryFiles();
      final bytes = Uint8List.fromList(List.generate(40001, (i) => i % 256));
      final download = controller(
        store,
        load: () async => ByteData.sublistView(bytes),
      );
      final progress = <double>[];
      download.addListener(() => progress.add(download.progress));
      expect(await download.start(), isTrue);
      expect(download.state, ReferenceDownloadState.completed);
      expect(store.files[download.savedHandle], bytes);
      expect(store.complete, contains(download.savedHandle));
      expect(progress.last, 1);
      expect(progress.where((v) => v > 0 && v < 1).length, 3);
      expect(progress, orderedEquals([...progress]..sort()));
      expect(await download.open(), isTrue);
      expect(await download.export(), isTrue);
      expect(store.opens, 1);
      expect(store.exports, 1);
    },
  );

  test('ByteData view saves only its slice', () async {
    final store = _MemoryFiles();
    final bytes = Uint8List.fromList([9, 1, 2, 3, 9]);
    final download = controller(
      store,
      load: () async => ByteData.view(bytes.buffer, 1, 3),
    );
    expect(await download.start(), isTrue);
    expect(store.files[download.savedHandle], [1, 2, 3]);
  });

  test('cancel while reading does not begin a file', () async {
    final store = _MemoryFiles();
    final pending = Completer<ByteData>();
    final download = controller(store, load: () => pending.future);
    final action = download.start();
    download.cancel();
    pending.complete(ByteData(4));
    expect(await action, isFalse);
    expect(download.state, ReferenceDownloadState.cancelled);
    expect(download.savedHandle, isNull);
    expect(store.files, isEmpty);
  });

  test(
    'cancel after first chunk removes partial bytes and never completes',
    () async {
      final store = _MemoryFiles();
      final download = controller(store);
      store.onAppend = () async => download.cancel();
      expect(await download.start(), isFalse);
      expect(download.state, ReferenceDownloadState.cancelled);
      expect(download.progress, lessThan(1));
      expect(download.savedHandle, isNull);
      expect(store.files, isEmpty);
      expect(store.removed, hasLength(1));
      expect(await download.open(), isFalse);
    },
  );

  test(
    'failed disk write cleans up and retry creates a verified new file',
    () async {
      final store = _MemoryFiles()..failAppend = true;
      final download = controller(store);
      expect(await download.start(), isFalse);
      expect(download.state, ReferenceDownloadState.failed);
      expect(download.error, isA<StateError>());
      expect(store.files, isEmpty);
      store.failAppend = false;
      expect(await download.start(), isTrue);
      expect(download.error, isNull);
      expect(download.progress, 1);
      expect(store.files, hasLength(1));
    },
  );

  test(
    'failed atomic finish is never reported as a completed download',
    () async {
      final store = _MemoryFiles()..failFinish = true;
      final download = controller(store);
      expect(await download.start(), isFalse);
      expect(download.state, ReferenceDownloadState.failed);
      expect(download.progress, lessThan(1));
      expect(download.savedHandle, isNull);
      expect(store.files, isEmpty);
    },
  );

  test(
    'permission is checked before reading and cannot be bypassed by retry',
    () async {
      final store = _MemoryFiles();
      var reads = 0;
      final download = controller(
        store,
        authorize: () => throw StateError('denied'),
        load: () async {
          reads++;
          return ByteData(3);
        },
      );
      expect(await download.start(), isFalse);
      expect(await download.start(), isFalse);
      expect(reads, 0);
      expect(store.files, isEmpty);
    },
  );

  test('revocation during read blocks saving', () async {
    final store = _MemoryFiles();
    var allowed = true;
    final download = controller(
      store,
      authorize: () {
        if (!allowed) throw StateError('denied');
      },
      load: () async {
        allowed = false;
        return ByteData(3);
      },
    );
    expect(await download.start(), isFalse);
    expect(store.files, isEmpty);
  });

  for (final phase in ['chunk', 'finish']) {
    test(
      'revocation at $phase removes private file and does not report success',
      () async {
        final store = _MemoryFiles();
        var allowed = true;
        final download = controller(
          store,
          authorize: () {
            if (!allowed) throw StateError('denied');
          },
        );
        if (phase == 'chunk') {
          store.onAppend = () async => allowed = false;
        } else {
          store.onFinish = () async => allowed = false;
        }
        expect(await download.start(), isFalse);
        expect(download.savedHandle, isNull);
        expect(download.progress, lessThan(1));
        expect(store.files, isEmpty);
        expect(store.complete, isEmpty);
      },
    );
  }

  test(
    'open and export reauthorize a previously completed local file',
    () async {
      final store = _MemoryFiles();
      var allowed = true;
      final download = controller(
        store,
        authorize: () {
          if (!allowed) throw StateError('denied');
        },
      );
      expect(await download.start(), isTrue);
      allowed = false;
      expect(await download.open(), isFalse);
      expect(await download.export(), isFalse);
      expect(store.opens, 0);
      expect(store.exports, 0);
    },
  );

  test(
    'dismissing system export chooser returns false and preserves saved file',
    () async {
      final store = _MemoryFiles()..exportAccepted = false;
      final download = controller(store);
      await download.start();
      expect(await download.export(), isFalse);
      expect(download.state, ReferenceDownloadState.completed);
      expect(download.savedHandle, isNotNull);
    },
  );

  test(
    'missing file cannot claim that opening or exporting succeeded',
    () async {
      final store = _MemoryFiles();
      final download = controller(store);
      await download.start();
      await store.remove(download.savedHandle!);
      expect(await download.open(), isFalse);
      expect(await download.export(), isFalse);
      expect(download.error, isA<StateError>());
    },
  );

  test(
    'empty source and traversal names are rejected without saved handles',
    () async {
      final store = _MemoryFiles();
      for (final name in ['../a.txt', r'..\a.txt', '', '..']) {
        final download = controller(store, fileName: name);
        expect(await download.start(), isFalse);
        expect(download.savedHandle, isNull);
      }
      final empty = controller(store, load: () async => ByteData(0));
      expect(await empty.start(), isFalse);
      expect(store.files, isEmpty);
    },
  );

  test(
    'platform contract transports exact chunks and explicit finish',
    () async {
      const channel = MethodChannel('opc/reference_files_test');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'begin') return 'test-handle';
            if (call.method == 'open' || call.method == 'export') return true;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final download = ReferenceDownloadController(
        load: () async => ByteData.sublistView(Uint8List.fromList([1, 2, 3])),
        fileName: 'test.txt',
        mimeType: 'text/plain',
        authorize: () {},
        store: const PlatformReferenceFileStore(channel: channel),
      );
      addTearDown(download.dispose);
      expect(await download.start(), isTrue);
      expect(calls.map((e) => e.method), ['begin', 'append', 'finish']);
      expect((calls[1].arguments as Map)['bytes'], [1, 2, 3]);
      expect((calls[2].arguments as Map)['totalBytes'], 3);
      expect(await download.open(), isTrue);
      expect(await download.export(), isTrue);
    },
  );

  test('cancelled old operation cannot overwrite an immediate retry', () async {
    final store = _MemoryFiles();
    final firstRead = Completer<ByteData>();
    var reads = 0;
    final download = controller(
      store,
      load: () => reads++ == 0 ? firstRead.future : Future.value(ByteData(7)),
    );
    final first = download.start();
    download.cancel();
    expect(await download.start(), isTrue);
    final newHandle = download.savedHandle;
    firstRead.complete(ByteData(5));
    expect(await first, isFalse);
    expect(download.state, ReferenceDownloadState.completed);
    expect(download.savedHandle, newHandle);
    expect(store.files[newHandle], hasLength(7));
    expect(store.files, hasLength(1));
  });

  test(
    'disposing an in-flight save removes bytes without completion callbacks',
    () async {
      final store = _MemoryFiles();
      final chunkWait = Completer<void>();
      final chunkStarted = Completer<void>();
      store.onAppend = () async {
        chunkStarted.complete();
        await chunkWait.future;
      };
      final download = ReferenceDownloadController(
        load: () async => ByteData(7),
        fileName: 'test.txt',
        mimeType: 'text/plain',
        authorize: () {},
        store: store,
      );
      final action = download.start();
      await chunkStarted.future;
      download.dispose();
      chunkWait.complete();
      expect(await action, isFalse);
      expect(store.files, isEmpty);
      expect(store.complete, isEmpty);
    },
  );
}
