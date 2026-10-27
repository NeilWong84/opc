import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ReferenceDownloadState { idle, loading, completed, cancelled, failed }

/// Stores bytes in the application's private directory. Handles are opaque and
/// must never be interpreted as arbitrary filesystem paths by a platform store.
abstract class ReferenceFileStore {
  Future<String> begin(String fileName, String mimeType, int totalBytes);
  Future<void> append(String handle, Uint8List bytes);
  Future<void> finish(String handle, int totalBytes);
  Future<void> remove(String handle);
  Future<bool> open(String handle, String mimeType);
  Future<bool> export(String handle, String fileName, String mimeType);
}

class PlatformReferenceFileStore implements ReferenceFileStore {
  const PlatformReferenceFileStore({
    this.channel = const MethodChannel('opc/reference_files'),
  });

  final MethodChannel channel;

  static final Map<String, FutureOr<void> Function()> _authorizations = {};

  /// The native export chooser can outlive the initiating call. It asks again
  /// immediately before reading the private file after the user picks a target.
  void bindAuthorization(String handle, FutureOr<void> Function() authorize) {
    _authorizations[handle] = authorize;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'authorize') throw MissingPluginException();
      final handle = call.arguments as String;
      try {
        final check = _authorizations[handle];
        if (check == null) return false;
        await check();
        return true;
      } catch (_) {
        return false;
      }
    });
  }

  void unbindAuthorization(String handle) => _authorizations.remove(handle);

  @override
  Future<String> begin(String fileName, String mimeType, int totalBytes) async {
    final handle = await channel.invokeMethod<String>('begin', {
      'fileName': fileName,
      'mimeType': mimeType,
      'totalBytes': totalBytes,
    });
    if (handle == null || handle.isEmpty) {
      throw StateError('The platform did not create a file.');
    }
    return handle;
  }

  @override
  Future<void> append(String handle, Uint8List bytes) =>
      channel.invokeMethod<void>('append', {'handle': handle, 'bytes': bytes});

  @override
  Future<void> finish(String handle, int totalBytes) =>
      channel.invokeMethod<void>('finish', {
        'handle': handle,
        'totalBytes': totalBytes,
      });

  @override
  Future<void> remove(String handle) =>
      channel.invokeMethod<void>('remove', {'handle': handle});

  @override
  Future<bool> open(String handle, String mimeType) async =>
      await channel.invokeMethod<bool>('open', {
        'handle': handle,
        'mimeType': mimeType,
      }) ??
      false;

  @override
  Future<bool> export(String handle, String fileName, String mimeType) async =>
      await channel.invokeMethod<bool>('export', {
        'handle': handle,
        'fileName': fileName,
        'mimeType': mimeType,
      }) ??
      false;
}

class _DownloadCancelled implements Exception {}

/// Downloads bundled reference bytes into an actual local file. [authorize] is
/// deliberately re-run at every asynchronous boundary; a previously authorized
/// read never grants permission for a later save, open or export.
class ReferenceDownloadController extends ChangeNotifier {
  ReferenceDownloadController({
    required this.load,
    required this.fileName,
    required this.mimeType,
    required this.authorize,
    this.authorizeRemote,
    ReferenceFileStore? store,
  }) : _store = store ?? const PlatformReferenceFileStore();

  final Future<ByteData> Function() load;
  final String fileName;
  final String mimeType;
  final void Function() authorize;

  /// Live adapters revalidate with the server before bytes or saved files leave
  /// the app, including after a native export chooser returns.
  final Future<void> Function()? authorizeRemote;
  final ReferenceFileStore _store;
  ReferenceDownloadState _state = ReferenceDownloadState.idle;
  double _progress = 0;
  String? _savedHandle;
  Object? _error;
  int _generation = 0;
  bool _disposed = false;
  bool _usingSaved = false;

  ReferenceDownloadState get state => _state;
  double get progress => _progress;
  String? get savedHandle => _savedHandle;
  Object? get error => _error;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) throw _DownloadCancelled();
    authorize();
  }

  Future<bool> start() async {
    if (_disposed || _state == ReferenceDownloadState.loading) return false;
    final generation = ++_generation;
    String? handle;
    _state = ReferenceDownloadState.loading;
    _progress = 0;
    _savedHandle = null;
    _error = null;
    _notify();
    try {
      _check(generation);
      if (authorizeRemote != null) await authorizeRemote!();
      _check(generation);
      if (fileName.trim().isEmpty ||
          fileName == '.' ||
          fileName == '..' ||
          RegExp(r'[/\\\x00-\x1f]').hasMatch(fileName)) {
        throw ArgumentError.value(fileName, 'fileName', 'Invalid filename');
      }
      final data = await load();
      _check(generation);
      if (authorizeRemote != null) await authorizeRemote!();
      _check(generation);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.isEmpty) throw StateError('The reference file is empty.');
      handle = await _store.begin(fileName, mimeType, bytes.length);
      _check(generation);
      const chunkSize = 16 * 1024;
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        _check(generation);
        final end = math.min(offset + chunkSize, bytes.length);
        await _store.append(handle, Uint8List.sublistView(bytes, offset, end));
        _check(generation);
        // 100% means a verified, atomically completed file, not just bytes sent.
        _progress = .99 * end / bytes.length;
        _notify();
        await Future<void>.delayed(Duration.zero);
      }
      _check(generation);
      await _store.finish(handle, bytes.length);
      _check(generation);
      if (authorizeRemote != null) await authorizeRemote!();
      _check(generation);
      _savedHandle = handle;
      _progress = 1;
      _state = ReferenceDownloadState.completed;
      _notify();
      return true;
    } catch (error) {
      if (handle != null) {
        try {
          await _store.remove(handle);
        } catch (_) {
          // A cleanup failure must not turn an incomplete save into success.
        }
      }
      if (!_disposed && generation == _generation) {
        _savedHandle = null;
        _error = error is _DownloadCancelled ? null : error;
        _state = error is _DownloadCancelled
            ? ReferenceDownloadState.cancelled
            : ReferenceDownloadState.failed;
        _notify();
      }
      return false;
    }
  }

  void cancel() {
    if (_disposed || _state != ReferenceDownloadState.loading) return;
    ++_generation;
    _state = ReferenceDownloadState.cancelled;
    _savedHandle = null;
    _error = null;
    _notify();
  }

  Future<bool> _useSaved({required bool exportFile}) async {
    if (_disposed ||
        _usingSaved ||
        _state != ReferenceDownloadState.completed) {
      return false;
    }
    final handle = _savedHandle;
    if (handle == null) return false;
    final generation = _generation;
    _usingSaved = true;
    try {
      _check(generation);
      if (authorizeRemote != null) await authorizeRemote!();
      _check(generation);
      _error = null;
      final store = _store;
      if (store is PlatformReferenceFileStore) {
        store.bindAuthorization(handle, () async {
          _check(generation);
          if (authorizeRemote != null) await authorizeRemote!();
          _check(generation);
        });
      }
      final success = exportFile
          ? await _store.export(handle, fileName, mimeType)
          : await _store.open(handle, mimeType);
      _check(generation);
      _notify();
      return success;
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _error = error;
        _notify();
      }
      // External copies already exported to another app cannot be withdrawn.
      return false;
    } finally {
      _usingSaved = false;
      final store = _store;
      if (store is PlatformReferenceFileStore) {
        store.unbindAuthorization(handle);
      }
    }
  }

  Future<bool> open() => _useSaved(exportFile: false);
  Future<bool> export() => _useSaved(exportFile: true);

  @override
  void dispose() {
    ++_generation;
    _disposed = true;
    super.dispose();
  }
}
