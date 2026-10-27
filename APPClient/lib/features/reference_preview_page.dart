import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/app_controller.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../l10n/strings.dart';
import 'reference_widgets.dart';

/// Read-only reference viewing. Office pages are supplied by the repository;
/// this screen does not claim to parse or convert arbitrary Office originals.
class ReferencePreviewPage extends StatefulWidget {
  const ReferencePreviewPage({
    super.key,
    required this.app,
    required this.taskId,
    required this.referenceId,
  });

  final AppController app;
  final String taskId;
  final String referenceId;

  @override
  State<ReferencePreviewPage> createState() => _ReferencePreviewPageState();
}

class _ReferencePreviewPageState extends State<ReferencePreviewPage>
    with WidgetsBindingObserver {
  late String _referenceId;
  final _transform = TransformationController();
  final _tableScroll = ScrollController();
  final _search = TextEditingController();
  VideoPlayerController? _video;
  String? _videoAsset;
  bool _videoFailed = false;
  bool _retrying = false;
  bool _fullscreen = false;
  bool _raw = false;
  bool _resumeAfterSeek = false;
  bool _foreground = true;
  double? _seekValue;
  double _fontSize = 14;
  int _page = 0;
  int _sheet = 0;
  String _selectedCell = '';
  String _selectedValue = '';
  RepositoryException? _retryError;
  String? _sessionId;
  Offset? _imageSwipeStart;
  int _imagePointers = 0;

  @override
  void initState() {
    super.initState();
    _referenceId = widget.referenceId;
    _sessionId = widget.app.repository.session?.id;
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(_appChanged);
    _initializeMedia();
  }

  @override
  void didUpdateWidget(ReferencePreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.removeListener(_appChanged);
      widget.app.addListener(_appChanged);
    }
    if (oldWidget.app != widget.app ||
        oldWidget.taskId != widget.taskId ||
        oldWidget.referenceId != widget.referenceId) {
      _referenceId = widget.referenceId;
      _sessionId = widget.app.repository.session?.id;
      _resetView();
      _initializeMedia();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      _resumeAfterSeek = false;
      final video = _video;
      if (video != null) unawaited(video.pause());
    } else {
      _appChanged();
    }
  }

  TaskReference _read() {
    // A different account must reopen the reference, even when both accounts
    // are entitled to it. Do not keep the old account's active playback.
    if (_sessionId != widget.app.repository.session?.id) {
      throw const RepositoryException('session_changed', '');
    }
    return widget.app.repository.reference(widget.taskId, _referenceId);
  }

  void _appChanged() {
    if (!mounted) return;
    try {
      final reference = _read();
      if (reference.kind != ReferenceKind.video ||
          reference.previewState != ReferencePreviewState.ready) {
        _releaseVideo();
      } else if (_videoAsset != reference.assetPath) {
        _initializeMedia();
      }
    } on RepositoryException {
      _releaseVideo();
      _search.clear();
      _selectedCell = '';
      _selectedValue = '';
      _fullscreen = false;
    }
    setState(() {});
  }

  void _resetView() {
    _releaseVideo();
    _page = 0;
    _sheet = 0;
    _fullscreen = false;
    _raw = false;
    _retryError = null;
    _selectedCell = '';
    _selectedValue = '';
    _search.clear();
    _transform.value = Matrix4.identity();
  }

  void _initializeMedia() {
    final TaskReference reference;
    try {
      reference = _read();
    } on RepositoryException {
      _releaseVideo();
      return;
    }
    if (reference.kind != ReferenceKind.video ||
        reference.previewState != ReferencePreviewState.ready) {
      return;
    }
    if (_videoAsset == reference.assetPath && _video != null) return;
    _releaseVideo();
    _videoFailed = false;
    _videoAsset = reference.assetPath;
    final controller = VideoPlayerController.asset(reference.assetPath);
    _video = controller;
    controller.addListener(_videoChanged);
    unawaited(
      controller
          .initialize()
          .then((_) async {
            if (!mounted || _video != controller) return;
            try {
              _read();
            } on RepositoryException {
              _releaseVideo();
              if (mounted) setState(() {});
              return;
            }
            // Initialization never starts playback, including a failed retry.
            await controller.setLooping(false);
            if (mounted && _video == controller) setState(() {});
          })
          .catchError((Object _) {
            if (mounted && _video == controller) {
              setState(() => _videoFailed = true);
            }
          }),
    );
  }

  void _videoChanged() {
    if (mounted) setState(() {});
  }

  void _releaseVideo() {
    final controller = _video;
    _video = null;
    _videoAsset = null;
    _seekValue = null;
    _resumeAfterSeek = false;
    if (controller != null) {
      controller.removeListener(_videoChanged);
      // Stop immediately; dispose then releases the texture and native player.
      unawaited(controller.pause().catchError((Object _) {}));
      unawaited(controller.dispose());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.removeListener(_appChanged);
    _releaseVideo();
    _transform.dispose();
    _tableScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_retrying || widget.app.busy) return;
    setState(() {
      _retrying = true;
      _retryError = null;
    });
    try {
      _read();
      await widget.app.run(
        () =>
            widget.app.repository.prepareReference(widget.taskId, _referenceId),
      );
      if (!mounted) return;
      _read();
      _releaseVideo();
      _initializeMedia();
    } on RepositoryException catch (error) {
      if (mounted) _retryError = error;
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  String _title(TaskReference reference) => switch (reference.kind) {
    ReferenceKind.image => l10n(context).previewImageTitle,
    ReferenceKind.video => l10n(context).previewVideoTitle,
    ReferenceKind.document => l10n(context).previewDocumentTitle,
    ReferenceKind.pdf => l10n(context).previewPdfTitle,
    ReferenceKind.spreadsheet => l10n(context).previewTableTitle,
    ReferenceKind.presentation => l10n(context).previewSlidesTitle,
    ReferenceKind.text => l10n(context).previewTextTitle,
    ReferenceKind.other => l10n(context).previewTitle,
  };

  @override
  Widget build(BuildContext context) {
    final TaskReference reference;
    try {
      // Revalidation is deliberately repeated for every displayed frame/state.
      reference = _read();
    } on RepositoryException {
      _releaseVideo();
      return OpcPage(
        title: l10n(context).previewTitle,
        child: _StatePanel(
          icon: Icons.lock_outline,
          title: l10n(context).previewAccessDenied,
          message: l10n(context).previewAccessDeniedHint,
        ),
      );
    }
    if (_fullscreen && reference.previewState == ReferencePreviewState.ready) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) setState(() => _fullscreen = false);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    key: const ValueKey('preview-exit-fullscreen'),
                    tooltip: l10n(context).previewExitFullscreen,
                    color: Colors.white,
                    onPressed: () => setState(() => _fullscreen = false),
                    icon: const Icon(Icons.fullscreen_exit),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: reference.kind == ReferenceKind.video
                        ? _videoSurface(reference)
                        : _slideSurface(reference, fullscreen: true),
                  ),
                ),
                Theme(
                  data: opcTheme(Brightness.dark),
                  child: reference.kind == ReferenceKind.video
                      ? _videoControls()
                      : _pageControls(reference, fullscreen: true),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return OpcPage(
      title: _title(reference),
      subtitle: reference.fileName,
      bottom: ReferenceDownloadButton(
        app: widget.app,
        taskId: widget.taskId,
        referenceId: _referenceId,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_retryError != null) ...[
            InfoNote(repositoryError(context, _retryError!), warning: true),
            const Gap(12),
          ],
          if (reference.previewState != ReferencePreviewState.ready)
            _previewState(reference)
          else
            switch (reference.kind) {
              ReferenceKind.image => _imageContent(reference),
              ReferenceKind.video => _videoContent(reference),
              ReferenceKind.document ||
              ReferenceKind.pdf => _documentContent(reference),
              ReferenceKind.presentation => _slidesContent(reference),
              ReferenceKind.spreadsheet => _tableContent(reference),
              ReferenceKind.text => _textContent(reference),
              ReferenceKind.other => _unsupported(),
            },
        ],
      ),
    );
  }

  Widget _previewState(TaskReference reference) =>
      switch (reference.previewState) {
        ReferencePreviewState.preparing => _StatePanel(
          icon: Icons.hourglass_top_rounded,
          title: l10n(context).previewPreparing,
          message: l10n(context).previewPreparingHint,
          action: PrimaryButton(
            label: l10n(context).previewCheckPreparation,
            secondary: true,
            onPressed: _retrying || widget.app.busy ? null : _retry,
          ),
        ),
        ReferencePreviewState.failed => _StatePanel(
          icon: Icons.error_outline,
          title: l10n(context).previewFailed,
          message: l10n(context).previewFailedHint,
          action: PrimaryButton(
            label: l10n(context).previewRetry,
            secondary: true,
            onPressed: _retrying || widget.app.busy ? null : _retry,
          ),
        ),
        _ => _unsupported(),
      };

  Widget _unsupported() => _StatePanel(
    icon: Icons.insert_drive_file_outlined,
    title: l10n(context).previewUnsupported,
    message: l10n(context).previewUnsupportedHint,
  );

  Widget _empty() => InfoNote(l10n(context).previewEmpty);

  double _stageHeight({double maximum = 460}) =>
      (MediaQuery.sizeOf(context).height * .48).clamp(220, maximum);

  void _zoom(double delta) {
    final scale = (_transform.value.getMaxScaleOnAxis() + delta).clamp(
      1.0,
      4.0,
    );
    setState(() => _transform.value = Matrix4.diagonal3Values(scale, scale, 1));
  }

  Widget _zoomControls() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: l10n(context).previewZoomOut,
        onPressed: () => _zoom(-.5),
        icon: const Icon(Icons.zoom_out),
      ),
      ValueListenableBuilder<Matrix4>(
        valueListenable: _transform,
        builder: (context, matrix, _) => TextButton(
          onPressed: () => _transform.value = Matrix4.identity(),
          child: Tooltip(
            message: l10n(context).previewResetZoom,
            child: Text('${(matrix.getMaxScaleOnAxis() * 100).round()}%'),
          ),
        ),
      ),
      IconButton(
        tooltip: l10n(context).previewZoomIn,
        onPressed: () => _zoom(.5),
        icon: const Icon(Icons.zoom_in),
      ),
    ],
  );

  void _selectImage(String id) {
    try {
      widget.app.repository.reference(widget.taskId, id);
      setState(() {
        _referenceId = id;
        _resetView();
      });
    } on RepositoryException {
      _appChanged();
    }
  }

  Widget _imageContent(TaskReference reference) {
    final colors = AppColors.of(context);
    final images = widget.app.repository
        .references(widget.taskId)
        .where((entry) => entry.kind == ReferenceKind.image)
        .toList();
    final index = images.indexWhere((image) => image.id == reference.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusPill(
              l10n(context).previewImageCount(index + 1, images.length),
            ),
            _zoomControls(),
          ],
        ),
        const Gap(8),
        Container(
          height: _stageHeight(),
          decoration: BoxDecoration(
            color: colors.raised,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Listener(
            // Observe a one-finger swipe without taking the gesture arena away
            // from InteractiveViewer's two-finger pinch and zoomed panning.
            onPointerDown: (event) {
              _imagePointers++;
              _imageSwipeStart =
                  _imagePointers == 1 &&
                      _transform.value.getMaxScaleOnAxis() <= 1.01
                  ? event.position
                  : null;
            },
            onPointerCancel: (_) {
              _imagePointers = math.max(0, _imagePointers - 1);
              _imageSwipeStart = null;
            },
            onPointerUp: (event) {
              _imagePointers = math.max(0, _imagePointers - 1);
              final start = _imageSwipeStart;
              _imageSwipeStart = null;
              if (start == null ||
                  _imagePointers != 0 ||
                  _transform.value.getMaxScaleOnAxis() > 1.01) {
                return;
              }
              final delta = event.position - start;
              if (delta.dx.abs() < 64 || delta.dy.abs() > delta.dx.abs() * .5) {
                return;
              }
              final next = index + (delta.dx < 0 ? 1 : -1);
              if (next >= 0 && next < images.length) {
                _selectImage(images[next].id);
              }
            },
            child: InteractiveViewer(
              key: const ValueKey('reference-image-viewer'),
              transformationController: _transform,
              maxScale: 4,
              child: Center(child: _assetImage(reference.assetPath)),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              key: const ValueKey('preview-previous-image'),
              tooltip: l10n(context).previewPrevious,
              onPressed: index > 0
                  ? () => _selectImage(images[index - 1].id)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              key: const ValueKey('preview-next-image'),
              tooltip: l10n(context).previewNext,
              onPressed: index >= 0 && index + 1 < images.length
                  ? () => _selectImage(images[index + 1].id)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (reference.description.isNotEmpty)
          Text(
            reference.description,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        const Gap(6),
        Text(
          l10n(context).previewImageHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Gap(12),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, index) => const Gap(10),
            itemBuilder: (context, itemIndex) => Semantics(
              selected: itemIndex == index,
              button: true,
              label: images[itemIndex].fileName,
              child: InkWell(
                key: ValueKey('reference-image-${images[itemIndex].id}'),
                onTap: () => _selectImage(images[itemIndex].id),
                child: Container(
                  width: 104,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: itemIndex == index
                          ? colors.primary
                          : colors.border,
                      width: itemIndex == index ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _assetImage(
                    images[itemIndex].thumbnailAsset ??
                        images[itemIndex].assetPath,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _assetImage(String asset) => Image.asset(
    asset,
    fit: BoxFit.contain,
    errorBuilder: (context, error, stack) => Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(l10n(context).previewImageFailed),
      ),
    ),
  );

  Future<void> _videoAction(
    Future<void> Function(VideoPlayerController) action,
  ) async {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    try {
      _read();
      await action(video);
    } on RepositoryException {
      _appChanged();
    } catch (_) {
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  Widget _videoSurface(TaskReference reference) {
    final video = _video;
    if (_videoFailed || video?.value.hasError == true) {
      return _StatePanel(
        icon: Icons.error_outline,
        title: l10n(context).previewVideoFailed,
        message: l10n(context).previewFailedHint,
        action: TextButton(
          onPressed: _retrying ? null : _retry,
          child: Text(l10n(context).previewRetry),
        ),
      );
    }
    if (video == null || !video.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (reference.thumbnailAsset != null)
              _assetImage(reference.thumbnailAsset!),
            ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Semantics(
                  label: l10n(context).previewVideoLoading,
                  child: const CircularProgressIndicator(),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return AspectRatio(
      aspectRatio: video.value.aspectRatio,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(video),
            if (!video.value.isPlaying)
              IconButton.filled(
                key: const ValueKey('preview-video-overlay-play'),
                tooltip: l10n(context).previewPlay,
                iconSize: 40,
                onPressed: _togglePlay,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePlay() => _videoAction((video) async {
    if (video.value.isPlaying) {
      await video.pause();
    } else {
      if (video.value.position >= video.value.duration) {
        await video.seekTo(Duration.zero);
      }
      _read();
      if (!_foreground || _video != video) return;
      await video.play();
    }
  });

  String _time(Duration value) {
    final seconds = value.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _videoControls() {
    final video = _video;
    final value = video?.value;
    final initialized = value?.isInitialized == true && value?.hasError != true;
    final duration = (value?.duration.inMilliseconds ?? 0).toDouble();
    final position =
        (_seekValue ?? (value?.position.inMilliseconds ?? 0).toDouble()).clamp(
          0.0,
          math.max(1.0, duration),
        );
    return Builder(
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('preview-video-play'),
                tooltip: value?.isPlaying == true
                    ? l10n(context).previewPause
                    : l10n(context).previewPlay,
                onPressed: initialized ? _togglePlay : null,
                icon: Icon(
                  value?.isPlaying == true
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              Text(
                _time(Duration(milliseconds: position.round())),
                style: const TextStyle(fontSize: 11),
              ),
              Expanded(
                child: Semantics(
                  label: l10n(context).previewSeek,
                  child: Slider(
                    key: const ValueKey('preview-video-seek'),
                    value: position.toDouble(),
                    max: math.max(1.0, duration),
                    onChangeStart: initialized
                        ? (_) {
                            _resumeAfterSeek = video!.value.isPlaying;
                            unawaited(video.pause());
                          }
                        : null,
                    onChanged: initialized
                        ? (value) => setState(() => _seekValue = value)
                        : null,
                    onChangeEnd: initialized
                        ? (value) async {
                            final resume = _resumeAfterSeek;
                            await _videoAction((video) async {
                              await video.seekTo(
                                Duration(milliseconds: value.round()),
                              );
                              if (resume && _foreground && _video == video) {
                                _read();
                                await video.play();
                              }
                            });
                            if (mounted) setState(() => _seekValue = null);
                          }
                        : null,
                  ),
                ),
              ),
              Text(
                _time(value?.duration ?? Duration.zero),
                style: const TextStyle(fontSize: 11),
              ),
              IconButton(
                key: const ValueKey('preview-video-mute'),
                tooltip: value?.volume == 0
                    ? l10n(context).previewUnmute
                    : l10n(context).previewMute,
                onPressed: initialized
                    ? () => _videoAction(
                        (video) =>
                            video.setVolume(video.value.volume == 0 ? 1 : 0),
                      )
                    : null,
                icon: Icon(
                  value?.volume == 0
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _videoContent(TaskReference reference) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _videoSurface(reference),
      ),
      _videoControls(),
      const Gap(12),
      if (reference.description.isNotEmpty)
        OpcCard(child: Text(reference.description)),
      const Gap(12),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const ValueKey('preview-fullscreen'),
          onPressed: () => setState(() => _fullscreen = true),
          icon: const Icon(Icons.fullscreen),
          label: Text(l10n(context).previewFullscreen),
        ),
      ),
      InfoNote(l10n(context).previewVideoHint),
    ],
  );

  void _setPage(int page, int total) {
    if (page < 0 || page >= total) return;
    setState(() {
      _page = page;
      _transform.value = Matrix4.identity();
    });
  }

  Future<void> _jumpToPage(int total) async {
    final page = await showDialog<int>(
      context: context,
      builder: (context) => _PageJumpDialog(current: _page + 1, total: total),
    );
    if (mounted && page != null) _setPage(page - 1, total);
  }

  Widget _pageControls(TaskReference reference, {bool fullscreen = false}) {
    final total = reference.pages.length;
    return Builder(
      builder: (context) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('preview-previous-page'),
                tooltip: l10n(context).previewPrevious,
                onPressed: _page > 0 ? () => _setPage(_page - 1, total) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                key: const ValueKey('preview-page-number'),
                onPressed: total > 0 ? () => _jumpToPage(total) : null,
                child: Tooltip(
                  message: l10n(context).previewPages,
                  child: Text(
                    l10n(
                      context,
                    ).previewPageCount(total == 0 ? 0 : _page + 1, total),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('preview-next-page'),
                tooltip: l10n(context).previewNext,
                onPressed: _page + 1 < total
                    ? () => _setPage(_page + 1, total)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (!fullscreen) _zoomControls(),
        ],
      ),
    );
  }

  Widget _formatRow(TaskReference reference, {Widget? action}) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      StatusPill(reference.extension.toUpperCase()),
      Text(
        l10n(context).previewReadOnly,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (action != null) action,
    ],
  );

  Widget _documentContent(TaskReference reference) {
    if (reference.pages.isEmpty) return _empty();
    _page = _page.clamp(0, reference.pages.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _formatRow(reference),
        _pageControls(reference),
        const Gap(6),
        SizedBox(
          height: _stageHeight(maximum: 520),
          child: InteractiveViewer(
            key: const ValueKey('reference-document-viewer'),
            transformationController: _transform,
            maxScale: 4,
            child: SingleChildScrollView(
              child: _ReferencePaper(
                page: reference.pages[_page],
                number: _page + 1,
              ),
            ),
          ),
        ),
        const Gap(10),
        Text(
          l10n(context).previewDocumentHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Gap(10),
        InfoNote(l10n(context).previewFixtureNotice),
      ],
    );
  }

  Widget _slideSurface(TaskReference reference, {bool fullscreen = false}) {
    if (reference.pages.isEmpty) return _empty();
    return InteractiveViewer(
      key: const ValueKey('reference-slide-viewer'),
      transformationController: _transform,
      maxScale: 4,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _ReferenceSlide(page: reference.pages[_page], number: _page + 1),
      ),
    );
  }

  Widget _slidesContent(TaskReference reference) {
    if (reference.pages.isEmpty) return _empty();
    _page = _page.clamp(0, reference.pages.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _formatRow(
          reference,
          action: TextButton.icon(
            key: const ValueKey('preview-fullscreen'),
            onPressed: () => setState(() => _fullscreen = true),
            icon: const Icon(Icons.fullscreen),
            label: Text(l10n(context).previewFullscreen),
          ),
        ),
        _pageControls(reference),
        const Gap(12),
        _slideSurface(reference),
        const Gap(16),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: reference.pages.length,
            separatorBuilder: (_, index) => const Gap(8),
            itemBuilder: (context, index) => Semantics(
              selected: _page == index,
              button: true,
              label: l10n(context).previewThumbnail(index + 1),
              child: InkWell(
                key: ValueKey('preview-slide-thumbnail-$index'),
                onTap: () => _setPage(index, reference.pages.length),
                child: Container(
                  width: 120,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _page == index
                          ? AppColors.of(context).primary
                          : AppColors.of(context).border,
                      width: _page == index ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: _ReferenceSlide(
                          page: reference.pages[index],
                          number: index + 1,
                        ),
                      ),
                      Text(
                        '${index + 1}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const Gap(14),
        if (reference.description.isNotEmpty) Text(reference.description),
        const Gap(10),
        Text(
          l10n(context).previewSlideHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Gap(10),
        InfoNote(l10n(context).previewFixtureNotice),
      ],
    );
  }

  String _columnName(int index) {
    var result = '';
    var number = index + 1;
    while (number > 0) {
      number--;
      result = String.fromCharCode(65 + number % 26) + result;
      number ~/= 26;
    }
    return result;
  }

  Widget _tableContent(TaskReference reference) {
    if (reference.sheets.isEmpty) return _empty();
    _sheet = _sheet.clamp(0, reference.sheets.length - 1);
    final sheet = reference.sheets[_sheet];
    final query = _search.text.trim().toLowerCase();
    final columns = sheet.rows.fold<int>(
      0,
      (count, row) => math.max(count, row.length),
    );
    var matches = 0;
    final rowIndices = <int>[];
    for (var index = 0; index < sheet.rows.length; index++) {
      final count = sheet.rows[index]
          .where(
            (cell) => query.isNotEmpty && cell.toLowerCase().contains(query),
          )
          .length;
      matches += count;
      if (query.isEmpty || index == 0 || count > 0) rowIndices.add(index);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _formatRow(reference),
        const Gap(12),
        TextField(
          key: const ValueKey('preview-table-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: l10n(context).previewSearch,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n(context).previewClearSearch,
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        if (query.isNotEmpty) ...[
          const Gap(8),
          Text(
            matches == 0
                ? l10n(context).previewNoMatches
                : l10n(context).previewSearchMatches(matches),
          ),
        ],
        if (_selectedCell.isNotEmpty) ...[
          const Gap(8),
          Semantics(
            label: l10n(context).previewSelectedCell,
            child: Text('$_selectedCell   $_selectedValue'),
          ),
        ],
        const Gap(12),
        if (columns == 0)
          _empty()
        else
          Scrollbar(
            controller: _tableScroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              key: const ValueKey('preview-table-horizontal'),
              controller: _tableScroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 12),
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(148),
                columnWidths: const {0: FixedColumnWidth(42)},
                border: TableBorder.all(color: const Color(0xFFDDE5E0)),
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFE8F4ED)),
                    children: [
                      _tableCell('', heading: true),
                      for (var column = 0; column < columns; column++)
                        _tableCell(_columnName(column), heading: true),
                    ],
                  ),
                  for (final row in rowIndices)
                    TableRow(
                      decoration: const BoxDecoration(color: Colors.white),
                      children: [
                        _tableCell('${row + 1}', heading: true),
                        for (var column = 0; column < columns; column++)
                          _tableCell(
                            column < sheet.rows[row].length
                                ? sheet.rows[row][column]
                                : '',
                            heading: row == 0,
                            query: query,
                            onTap: () => setState(() {
                              _selectedCell =
                                  '${_columnName(column)}${row + 1}';
                              _selectedValue = column < sheet.rows[row].length
                                  ? sheet.rows[row][column]
                                  : '';
                            }),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        const Gap(10),
        Wrap(
          spacing: 8,
          children: [
            for (var index = 0; index < reference.sheets.length; index++)
              ChoiceChip(
                key: ValueKey('preview-sheet-$index'),
                label: Text(reference.sheets[index].name),
                selected: index == _sheet,
                onSelected: (_) => setState(() {
                  _sheet = index;
                  _selectedCell = '';
                  _selectedValue = '';
                  if (_tableScroll.hasClients) _tableScroll.jumpTo(0);
                }),
              ),
          ],
        ),
        const Gap(10),
        Text(
          l10n(context).previewSheetCount(reference.sheets.length),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          l10n(context).previewTableHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Gap(10),
        InfoNote(l10n(context).previewFixtureNotice),
      ],
    );
  }

  Widget _tableCell(
    String text, {
    bool heading = false,
    String query = '',
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      color: query.isNotEmpty && text.toLowerCase().contains(query)
          ? const Color(0xFFFFE7A8)
          : null,
      child: Text(
        text,
        style: TextStyle(
          color: const Color(0xFF142D36),
          fontSize: 12,
          fontWeight: heading ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    ),
  );

  Widget _textContent(TaskReference reference) {
    final markdown = reference.extension == 'md';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusPill(markdown ? 'Markdown' : 'TXT'),
            if (markdown) ...[
              ChoiceChip(
                key: const ValueKey('preview-text-formatted'),
                label: Text(l10n(context).previewFormatted),
                selected: !_raw,
                onSelected: (_) => setState(() => _raw = false),
              ),
              ChoiceChip(
                key: const ValueKey('preview-text-raw'),
                label: Text(l10n(context).previewOriginal),
                selected: _raw,
                onSelected: (_) => setState(() => _raw = true),
              ),
            ],
          ],
        ),
        Row(
          children: [
            Expanded(child: Text(l10n(context).previewTextSize)),
            IconButton(
              key: const ValueKey('preview-font-smaller'),
              tooltip: l10n(context).previewSmallerText,
              onPressed: _fontSize > 12
                  ? () => setState(() => _fontSize -= 2)
                  : null,
              icon: const Icon(Icons.text_decrease),
            ),
            Text('${_fontSize.round()}'),
            IconButton(
              key: const ValueKey('preview-font-larger'),
              tooltip: l10n(context).previewLargerText,
              onPressed: _fontSize < 24
                  ? () => setState(() => _fontSize += 2)
                  : null,
              icon: const Icon(Icons.text_increase),
            ),
          ],
        ),
        Container(
          key: const ValueKey('preview-text-paper'),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: markdown && !_raw
              ? _MarkdownText(text: reference.text, fontSize: _fontSize)
              : SelectableText(
                  reference.text,
                  style: TextStyle(
                    color: const Color(0xFF142D36),
                    fontSize: _fontSize,
                    height: 1.8,
                    fontFamily: markdown ? 'monospace' : null,
                  ),
                ),
        ),
        const Gap(12),
        Text(
          l10n(context).previewTextHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => OpcCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(icon, size: 38, color: AppColors.of(context).primary),
        const Gap(14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Gap(8),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[const Gap(16), action!],
      ],
    ),
  );
}

class _ReferencePaper extends StatelessWidget {
  const _ReferencePaper({required this.page, required this.number});
  final ReferencePage page;
  final int number;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('reference-document-paper'),
    color: Colors.white,
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    child: DefaultTextStyle(
      style: const TextStyle(
        color: Color(0xFF142D36),
        fontSize: 13,
        height: 1.8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            page.title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          const Gap(16),
          const Divider(color: Color(0xFF086E61), thickness: 2),
          const Gap(12),
          if (page.imageAsset != null)
            Image.asset(page.imageAsset!, fit: BoxFit.contain),
          for (final paragraph in page.paragraphs) ...[
            Text(paragraph),
            const Gap(14),
          ],
          for (final bullet in page.bullets) ...[
            Text('• $bullet'),
            const Gap(8),
          ],
          const Gap(28),
          Text(
            '$number',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFF647572), fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _ReferenceSlide extends StatelessWidget {
  const _ReferenceSlide({required this.page, required this.number});
  final ReferencePage page;
  final int number;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF142D36),
    child: page.imageAsset != null
        ? Image.asset(page.imageAsset!, fit: BoxFit.contain)
        : FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 640,
              height: 360,
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Color(0xFFD9F7DD),
                    fontSize: 18,
                    height: 1.5,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        page.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Gap(20),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final text in page.paragraphs) Text(text),
                              for (final text in page.bullets) Text('• $text'),
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '$number',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
  );
}

class _PageJumpDialog extends StatefulWidget {
  const _PageJumpDialog({required this.current, required this.total});
  final int current;
  final int total;

  @override
  State<_PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<_PageJumpDialog> {
  final _form = GlobalKey<FormState>();
  late final _number = TextEditingController(text: '${widget.current}');

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(l10n(context).previewPages),
    content: LocalizedForm(
      key: _form,
      child: TextFormField(
        key: const ValueKey('preview-page-jump-field'),
        controller: _number,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n(context).previewPageNumber),
        validator: (text) {
          final page = int.tryParse(text ?? '');
          return page == null || page < 1 || page > widget.total
              ? l10n(context).previewPageRange(widget.total)
              : null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(l10n(context).previewCancel),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, int.parse(_number.text));
          }
        },
        child: Text(l10n(context).previewGo),
      ),
    ],
  );
}

/// A safe, basic Markdown reader: headings, lists, quotes, fenced code and
/// inline emphasis. Unknown syntax remains readable; HTML is never executed.
class _MarkdownText extends StatelessWidget {
  const _MarkdownText({required this.text, required this.fontSize});
  final String text;
  final double fontSize;

  List<InlineSpan> _inline(String text) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`)');
    var offset = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      final value = match.group(0)!;
      final bold = value.startsWith('**');
      spans.add(
        TextSpan(
          text: value.substring(bold ? 2 : 1, value.length - (bold ? 2 : 1)),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : null,
            fontFamily: bold ? null : 'monospace',
            backgroundColor: bold ? null : const Color(0xFFE8F4ED),
          ),
        ),
      );
      offset = match.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    var code = false;
    for (final line in text.split('\n')) {
      if (line.trimLeft().startsWith('```')) {
        code = !code;
        continue;
      }
      if (!code && line.trim().isEmpty) {
        // Markdown paragraph breaks are spacing, not selectable empty lines.
        // Rendering an empty SelectableText adds its full strut height as well.
        widgets.add(const Gap(8));
        continue;
      }
      final heading = !code
          ? RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line)
          : null;
      final bullet = !code
          ? RegExp(r'^\s*[-*+]\s+(.+)$').firstMatch(line)
          : null;
      final quote = !code && line.startsWith('> ');
      final value =
          heading?.group(2) ??
          (bullet == null
              ? (quote ? line.substring(2) : line)
              : '• ${bullet.group(1)}');
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: code || quote ? const EdgeInsets.all(8) : EdgeInsets.zero,
            color: code || quote ? const Color(0xFFE8F4ED) : null,
            child: SelectableText.rich(
              TextSpan(
                children: code ? [TextSpan(text: value)] : _inline(value),
              ),
              style: TextStyle(
                color: const Color(0xFF142D36),
                fontSize: heading == null
                    ? fontSize
                    : fontSize + (heading.group(1)!.length == 1 ? 8 : 3),
                fontWeight: heading == null ? FontWeight.w400 : FontWeight.w700,
                fontFamily: code ? 'monospace' : null,
                height: 1.8,
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }
}
