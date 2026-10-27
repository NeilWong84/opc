import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../core/app_controller.dart';
import '../core/document_renderer.dart';
import '../core/reference_download.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../l10n/strings.dart';
import 'api_workspace.dart';
import 'api_media_player.dart';

class ApiFilePage extends StatefulWidget {
  const ApiFilePage({
    super.key,
    required this.app,
    required this.fileId,
    this.fileStore,
    this.documentRenderer,
  });
  final AppController app;
  final String fileId;
  final ReferenceFileStore? fileStore;
  final DocumentRenderer? documentRenderer;
  @override
  State<ApiFilePage> createState() => _ApiFilePageState();
}

class _ApiFilePageState extends State<ApiFilePage> with WidgetsBindingObserver {
  RemoteFile? _file;
  RemotePreview? _preview;
  ReferenceDownloadController? _download;
  VideoPlayerController? _video;
  final _mediaAccess = ValueNotifier(MediaAccess.checking);
  bool _mediaCommandBusy = false;
  Directory? _temporaryVideo;
  Object? _error;
  Object? _previewError;
  late final DocumentRenderer _pdf =
      widget.documentRenderer ?? DocumentRenderer();
  Uint8List? _pdfPage;
  int _page = 0;
  bool _turningPage = false;
  bool _loading = true;
  bool _externalBusy = false;
  bool _checking = false;
  late final String? _accountId = widget.app.repository.session?.id;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(_sessionChanged);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _mediaAccess.value = MediaAccess.denied;
    WidgetsBinding.instance.removeObserver(this);
    widget.app.removeListener(_sessionChanged);
    _download?.dispose();
    _video?.dispose();
    _mediaAccess.dispose();
    _pdf.close().catchError((_) {});
    _temporaryVideo
        ?.delete(recursive: true)
        .catchError((_) => _temporaryVideo!);
    super.dispose();
  }

  void _sessionChanged() {
    if (widget.app.repository.session?.id == _accountId || !mounted) return;
    _generation++;
    _mediaAccess.value = MediaAccess.denied;
    _download?.cancel();
    _video?.pause();
    setState(() {
      _file = null;
      _preview = null;
      _pdfPage = null;
      _pdf.close().catchError((_) {});
      _loading = false;
      _error = const RepositoryException('unauthenticated', 'Session expired');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _mediaAccess.value = MediaAccess.checking;
      _video?.pause();
      if (mounted) setState(() => _checking = true);
    } else if (!_externalBusy) {
      _recheck();
    }
  }

  void _authorizeLocal() {
    if (!mounted || widget.app.repository.session?.id != _accountId) {
      throw const RepositoryException('unauthenticated', 'Session changed');
    }
  }

  Future<T> _read<T>(Future<T> Function() action) async {
    try {
      return await action();
    } finally {
      if (mounted && widget.app.repository.session == null) {
        widget.app.syncSession();
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _authorizeRemote() async {
    _authorizeLocal();
    final fresh = await _read(
      () => remote(widget.app).fileMetadata(widget.fileId),
    );
    _authorizeLocal();
    if (!fresh.isReady) {
      throw const RepositoryException('file_not_ready', 'File is unavailable');
    }
  }

  Future<void> _recheck() async {
    _mediaAccess.value = MediaAccess.checking;
    if (mounted) setState(() => _checking = true);
    try {
      await _authorizeRemote();
    } catch (error) {
      ++_generation;
      _download?.cancel();
      _video?.pause();
      if (mounted) {
        setState(() {
          _file = null;
          _preview = null;
          _pdfPage = null;
          _pdf.close().catchError((_) {});
          _error = error;
          _loading = false;
        });
      }
    } finally {
      if (mounted) {
        _mediaAccess.value = _error == null && _previewError == null
            ? MediaAccess.allowed
            : MediaAccess.denied;
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _mediaAccess.value = MediaAccess.checking;
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
      _previewError = null;
      _pdfPage = null;
    });
    _download?.dispose();
    _download = null;
    await _video?.dispose();
    _video = null;
    await _temporaryVideo?.delete(recursive: true);
    _temporaryVideo = null;
    try {
      await _pdf.close();
    } catch (_) {
      /* 已释放的原生预览无需阻断重新读取。 */
    }
    try {
      final repo = remote(widget.app);
      final file = await _read(() => repo.fileMetadata(widget.fileId));
      _authorizeLocal();
      if (!mounted || generation != _generation) return;
      _file = file;
      if (!file.isReady) {
        throw const RepositoryException(
          'file_not_ready',
          'Awaiting safety review',
        );
      }
      _download = ReferenceDownloadController(
        fileName: file.name,
        mimeType: file.mediaType,
        authorize: _authorizeLocal,
        authorizeRemote: _authorizeRemote,
        store: widget.fileStore,
        load: () async {
          final bytes = await _read(() => repo.downloadFile(widget.fileId));
          return ByteData.sublistView(bytes);
        },
      );
      final preview = await _read(() => repo.previewFile(widget.fileId));
      _authorizeLocal();
      if (!mounted || generation != _generation) return;
      _preview = preview;
      if (preview.mediaType == 'application/pdf' && preview.bytes != null) {
        await _pdf.open(preview.bytes!);
        _authorizeLocal();
        if (!mounted || generation != _generation) {
          await _pdf.close();
          return;
        }
        _page = 0;
        final firstPage = await _pdf.render(0);
        _authorizeLocal();
        if (!mounted || generation != _generation) {
          await _pdf.close();
          return;
        }
        _pdfPage = firstPage;
      }
      if ((preview.mediaType.startsWith('video/') ||
              preview.mediaType.startsWith('audio/')) &&
          preview.bytes != null) {
        final parent = await getTemporaryDirectory();
        final dir = await parent.createTemp('opc-media-');
        if (!mounted || generation != _generation) {
          await dir.delete(recursive: true);
          return;
        }
        _temporaryVideo = dir;
        final videoFile = await File(
          '${dir.path}/${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}',
        ).writeAsBytes(preview.bytes!, flush: true);
        final video = VideoPlayerController.file(videoFile);
        try {
          await video.initialize();
        } catch (_) {
          await video.dispose();
          rethrow;
        }
        if (!mounted || generation != _generation) {
          await video.dispose();
          return;
        }
        _video = video;
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        // 文件已授权时，转换或解码失败仍允许保存原件；权限失效必须清空。
        if (_download != null) {
          try {
            await _authorizeRemote();
            if (!mounted || generation != _generation) return;
            _previewError = error;
          } catch (accessError) {
            if (!mounted || generation != _generation) return;
            _file = null;
            _preview = null;
            _pdfPage = null;
            _error = accessError;
          }
        } else {
          _file = null;
          _preview = null;
          _error = error;
        }
      }
    } finally {
      if (mounted && generation == _generation) {
        _mediaAccess.value = _error == null && _previewError == null
            ? MediaAccess.allowed
            : MediaAccess.denied;
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _mediaCommand(
    Future<void> Function(VideoPlayerController) action,
  ) async {
    final video = _video;
    if (_mediaCommandBusy ||
        video == null ||
        _mediaAccess.value != MediaAccess.allowed) {
      return false;
    }
    _mediaCommandBusy = true;
    try {
      await _authorizeRemote();
      if (!mounted ||
          video != _video ||
          _mediaAccess.value != MediaAccess.allowed) {
        return false;
      }
      await action(video);
      return true;
    } catch (error) {
      try {
        await video.pause();
      } catch (_) {
        /* 会话退出时解码器可能已释放。 */
      }
      if (mounted) {
        _mediaAccess.value = MediaAccess.denied;
        _download?.cancel();
        setState(() {
          _file = null;
          _preview = null;
          _error = error;
        });
      }
      return false;
    } finally {
      _mediaCommandBusy = false;
    }
  }

  Future<void> _useFile(bool export) async {
    if (_externalBusy) return;
    setState(() => _externalBusy = true);
    final download = _download!;
    final ok = export ? await download.export() : await download.open();
    if (!mounted) return;
    setState(() => _externalBusy = false);
    await _recheck();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (export
                    ? l10n(context).apiExportDone
                    : l10n(context).apiOpenFile)
              : download.error == null
              ? l10n(context).apiFileActionFailed
              : apiError(context, download.error!),
        ),
      ),
    );
  }

  Future<void> _saveToPhone() async {
    if (_externalBusy || _download == null) return;
    if (_download!.state != ReferenceDownloadState.completed &&
        !await _download!.start()) {
      return;
    }
    if (!mounted) return;
    await _useFile(true);
  }

  Future<void> _turnPage(int page) async {
    if (_turningPage) return;
    final generation = _generation;
    setState(() => _turningPage = true);
    try {
      await _authorizeRemote();
      final bytes = await _pdf.render(page);
      _authorizeLocal();
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = page;
        _pdfPage = bytes;
      });
    } catch (_) {
      await _recheck();
      if (mounted) {
        setState(
          () => _previewError = const RepositoryException(
            'preview_failed',
            'Page failed',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _turningPage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = l10n(context);
    return OpcPage(
      title: _file?.name ?? s.apiFilePreview,
      actions: [
        IconButton(
          tooltip: s.apiRefresh,
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: _loading || _checking
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  InfoNote(apiError(context, _error!), warning: true),
                  const Gap(16),
                  PrimaryButton(label: s.apiRetry, onPressed: _load),
                ],
                if (_error == null && _file != null) ...[
                  if (_previewError != null)
                    InfoNote(s.filePreviewFailed, warning: true)
                  else if (_preview != null)
                    _previewContent(context, _preview!),
                  const Gap(20),
                  if (_download != null)
                    AnimatedBuilder(
                      animation: _download!,
                      builder: (context, _) => _downloadControls(context),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _previewContent(BuildContext context, RemotePreview preview) {
    final s = l10n(context);
    if (_pdfPage != null) {
      return Column(
        children: [
          SizedBox(
            height: 440,
            child: InteractiveViewer(
              key: ValueKey('pdf-page-$_page'),
              minScale: .5,
              maxScale: 6,
              child: ColoredBox(
                color: Colors.white,
                child: Image.memory(_pdfPage!, fit: BoxFit.contain),
              ),
            ),
          ),
          const Gap(10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('pdf-previous'),
                tooltip: s.previewPrevious,
                onPressed: _page > 0 && !_turningPage
                    ? () => _turnPage(_page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(child: Text('${_page + 1} / ${_pdf.pages}')),
              IconButton(
                key: const Key('pdf-next'),
                tooltip: s.previewNext,
                onPressed: _page + 1 < _pdf.pages && !_turningPage
                    ? () => _turnPage(_page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (_turningPage) const LinearProgressIndicator(),
        ],
      );
    }
    if (preview.mediaType.startsWith('image/') && preview.bytes != null) {
      return SizedBox(
        height: 420,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(
            preview.bytes!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => InfoNote(s.apiNoPreview),
          ),
        ),
      );
    }
    if (_video != null) {
      return ApiMediaPlayer(
        controller: _video!,
        name: _file!.name,
        access: _mediaAccess,
        onCommand: _mediaCommand,
        audio: preview.mediaType.startsWith('audio/'),
      );
    }
    if (preview.text.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpcCard(child: SelectableText(preview.text)),
          if (preview.truncated) ...[
            const Gap(12),
            InfoNote(s.apiTextTruncated),
          ],
        ],
      );
    }
    if (_file?.mediaType == 'application/pdf' ||
        const [
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
        ].contains(_file?.name.split('.').last.toLowerCase())) {
      return InfoNote(s.filePreviewFailed);
    }
    return InfoNote(s.apiNoPreview);
  }

  Widget _downloadControls(BuildContext context) {
    final download = _download!;
    final s = l10n(context);
    if (download.state == ReferenceDownloadState.loading) {
      return Column(
        children: [
          LinearProgressIndicator(value: download.progress),
          const Gap(8),
          Text('${(download.progress * 100).floor()}%'),
          TextButton(onPressed: download.cancel, child: Text(s.apiCancel)),
        ],
      );
    }
    if (download.state == ReferenceDownloadState.completed) {
      return Column(
        children: [
          InfoNote(s.apiDownloadDone),
          const Gap(16),
          PrimaryButton(
            key: const Key('api-file-open'),
            label: s.apiOpenFile,
            onPressed: _externalBusy ? null : () => _useFile(false),
          ),
          const Gap(10),
          PrimaryButton(
            key: const Key('api-file-export'),
            label: s.fileSaveToPhone,
            secondary: true,
            onPressed: _externalBusy ? null : () => _useFile(true),
          ),
        ],
      );
    }
    return Column(
      children: [
        if (download.error != null) ...[
          InfoNote(apiError(context, download.error!), warning: true),
          const Gap(12),
        ],
        PrimaryButton(
          key: const Key('api-file-download'),
          label: s.fileSaveToPhone,
          icon: Icons.download_outlined,
          onPressed: _externalBusy ? null : _saveToPhone,
        ),
      ],
    );
  }
}
