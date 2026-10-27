import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_controller.dart';
import '../core/reference_download.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../l10n/strings.dart';
import 'reference_pages.dart';
import 'reference_preview_page.dart';

String referenceSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String referenceDuration(int seconds) =>
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

String referenceMime(TaskReference file) => switch (file.extension) {
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'mp4' => 'video/mp4',
  'pdf' => 'application/pdf',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'doc' => 'application/msword',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'xls' => 'application/vnd.ms-excel',
  'pptx' =>
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'ppt' => 'application/vnd.ms-powerpoint',
  'csv' => 'text/csv',
  'md' => 'text/markdown',
  'txt' => 'text/plain',
  _ => 'application/octet-stream',
};

IconData referenceIcon(ReferenceKind kind) => switch (kind) {
  ReferenceKind.image => Icons.image_outlined,
  ReferenceKind.video => Icons.play_circle_outline,
  ReferenceKind.document => Icons.description_outlined,
  ReferenceKind.spreadsheet => Icons.table_chart_outlined,
  ReferenceKind.presentation => Icons.slideshow_outlined,
  ReferenceKind.pdf => Icons.picture_as_pdf_outlined,
  ReferenceKind.text => Icons.notes_outlined,
  ReferenceKind.other => Icons.insert_drive_file_outlined,
};

void openReference(
  BuildContext context,
  AppController app,
  String taskId,
  String referenceId,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReferencePreviewPage(
        app: app,
        taskId: taskId,
        referenceId: referenceId,
      ),
    ),
  );
}

void openReferenceList(BuildContext context, AppController app, String taskId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReferenceListPage(app: app, taskId: taskId),
    ),
  );
}

/// Only accepts references already filtered by the repository's published view.
class ReferenceThumbnail extends StatelessWidget {
  const ReferenceThumbnail({
    super.key,
    required this.reference,
    required this.onTap,
    this.height = 84,
    this.label,
  });
  final TaskReference reference;
  final VoidCallback onTap;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.raised,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('reference-thumb-${reference.id}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (reference.thumbnailAsset != null)
                    Image.asset(
                      reference.thumbnailAsset!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        referenceIcon(reference.kind),
                        color: c.secondary,
                      ),
                    ),
                  if (reference.kind == ReferenceKind.video) ...[
                    const ColoredBox(color: Color(0x22000000)),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xB3000000),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          referenceDuration(reference.durationSeconds),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (label != null)
              Padding(
                padding: const EdgeInsets.all(7),
                child: Text(
                  label!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReferenceFileRow extends StatelessWidget {
  const ReferenceFileRow({
    super.key,
    required this.app,
    required this.taskId,
    required this.reference,
    this.download = true,
  });
  final AppController app;
  final String taskId;
  final TaskReference reference;
  final bool download;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return OpcCard(
      padding: const EdgeInsets.fromLTRB(10, 8, 3, 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 40,
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              referenceIcon(reference.kind),
              color: c.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: InkWell(
              onTap: () => openReference(context, app, taskId, reference.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reference.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(fontSize: 12),
                  ),
                  Text(
                    '${reference.extension.toUpperCase()} · ${referenceSize(reference.sizeBytes)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            key: ValueKey('reference-open-${reference.id}'),
            tooltip: l10n(context).refPreview,
            onPressed: () => openReference(context, app, taskId, reference.id),
            icon: Icon(Icons.visibility_outlined, size: 19, color: c.primary),
          ),
          if (download)
            ReferenceDownloadButton(
              app: app,
              taskId: taskId,
              referenceId: reference.id,
              compact: true,
            ),
        ],
      ),
    );
  }
}

class HallReferenceSummary extends StatelessWidget {
  const HallReferenceSummary({
    super.key,
    required this.app,
    required this.item,
  });
  final AppController app;
  final WorkItem item;

  @override
  Widget build(BuildContext context) {
    final refs = item.references;
    if (refs.isEmpty) return const SizedBox.shrink();
    final media = refs
        .where(
          (r) => r.kind == ReferenceKind.image || r.kind == ReferenceKind.video,
        )
        .toList();
    final images = refs.where((r) => r.kind == ReferenceKind.image).length;
    final videos = refs.where((r) => r.kind == ReferenceKind.video).length;
    final files = refs.length - images - videos;
    return Padding(
      key: ValueKey('hall-references-${item.id}'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (media.isNotEmpty)
            Row(
              children: [
                for (var i = 0; i < media.take(3).length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: ReferenceThumbnail(
                      reference: media[i],
                      height: 62,
                      onTap: () =>
                          openReference(context, app, item.id, media[i].id),
                    ),
                  ),
                ],
              ],
            )
          else
            ReferenceFileRow(
              app: app,
              taskId: item.id,
              reference: refs.first,
              download: false,
            ),
          const Gap(6),
          InkWell(
            onTap: () => openReferenceList(context, app, item.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                [
                  if (images > 0) l10n(context).refImages(images),
                  if (videos > 0) l10n(context).refVideos(videos),
                  if (files > 0) l10n(context).refFiles(files),
                ].join(' · '),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TaskReferenceSection extends StatelessWidget {
  const TaskReferenceSection({
    super.key,
    required this.app,
    required this.item,
  });
  final AppController app;
  final WorkItem item;

  @override
  Widget build(BuildContext context) {
    if (item.references.isEmpty) return const SizedBox.shrink();
    final images = item.references
        .where((r) => r.kind == ReferenceKind.image)
        .toList();
    final videos = item.references
        .where((r) => r.kind == ReferenceKind.video)
        .toList();
    final files = item.references
        .where(
          (r) => r.kind != ReferenceKind.image && r.kind != ReferenceKind.video,
        )
        .toList();
    return Padding(
      key: const Key('task-reference-section'),
      padding: const EdgeInsets.only(top: 16),
      child: OpcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n(context).refTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  key: const Key('reference-view-all'),
                  onPressed: () => openReferenceList(context, app, item.id),
                  child: Text(l10n(context).refViewAll(item.references.length)),
                ),
              ],
            ),
            if (images.isNotEmpty || videos.isNotEmpty) ...[
              const Gap(6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (images.isNotEmpty)
                    Expanded(
                      child: ReferenceThumbnail(
                        reference: images.first,
                        height: 80,
                        label:
                            '${l10n(context).refImageHint} · ${l10n(context).refImages(images.length)}',
                        onTap: () => openReference(
                          context,
                          app,
                          item.id,
                          images.first.id,
                        ),
                      ),
                    ),
                  if (images.isNotEmpty && videos.isNotEmpty)
                    const SizedBox(width: 10),
                  if (videos.isNotEmpty)
                    Expanded(
                      child: ReferenceThumbnail(
                        reference: videos.first,
                        height: 80,
                        label: l10n(context).refVideoHint,
                        onTap: () => openReference(
                          context,
                          app,
                          item.id,
                          videos.first.id,
                        ),
                      ),
                    ),
                ],
              ),
              const Gap(10),
            ],
            if (files.isNotEmpty)
              ReferenceFileRow(
                app: app,
                taskId: item.id,
                reference: files.first,
              ),
            const Gap(10),
            Text(
              l10n(context).refOpenHint,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// A local original-file transfer with real progress, cancellation and export.
class ReferenceDownloadButton extends StatefulWidget {
  const ReferenceDownloadButton({
    super.key,
    required this.app,
    required this.taskId,
    required this.referenceId,
    this.compact = false,
    this.autoStart = false,
    this.failFirst = false,
    this.store,
  });
  final AppController app;
  final String taskId;
  final String referenceId;
  final bool compact;
  final bool autoStart;
  final bool failFirst;
  final ReferenceFileStore? store;

  @override
  State<ReferenceDownloadButton> createState() =>
      _ReferenceDownloadButtonState();
}

class _ReferenceDownloadButtonState extends State<ReferenceDownloadButton> {
  ReferenceDownloadController? _download;
  Object? _accessError;
  bool _failedOnce = false;
  bool _opening = false;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_checkAccess);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ReferenceDownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app ||
        oldWidget.taskId != widget.taskId ||
        oldWidget.referenceId != widget.referenceId) {
      oldWidget.app.removeListener(_checkAccess);
      _download?.removeListener(_changed);
      _download?.dispose();
      _download = null;
      _accessError = null;
      _sessionId = null;
      _failedOnce = false;
      widget.app.addListener(_checkAccess);
    }
  }

  void _checkAccess() {
    try {
      widget.app.repository.reference(widget.taskId, widget.referenceId);
      if (_sessionId != null &&
          widget.app.repository.session?.id != _sessionId) {
        throw const RepositoryException('session_changed', '');
      }
      if (_accessError != null && mounted) setState(() => _accessError = null);
    } on RepositoryException catch (e) {
      _download?.cancel();
      if (mounted) setState(() => _accessError = e);
    }
  }

  Future<void> _start() async {
    try {
      final file = widget.app.repository.reference(
        widget.taskId,
        widget.referenceId,
      );
      _sessionId = widget.app.repository.session!.id;
      _download ??= ReferenceDownloadController(
        fileName: file.fileName,
        mimeType: referenceMime(file),
        store: widget.store,
        authorize: () {
          if (widget.app.repository.session?.id != _sessionId) {
            throw const RepositoryException('session_changed', '');
          }
          final current = widget.app.repository.reference(
            widget.taskId,
            widget.referenceId,
          );
          if (current.publishedVersion != file.publishedVersion ||
              current.assetPath != file.assetPath) {
            throw const RepositoryException('not_found', '');
          }
        },
        load: () async {
          if (widget.failFirst && !_failedOnce) {
            _failedOnce = true;
            throw StateError('simulated_file_read_failure');
          }
          return rootBundle.load(file.assetPath);
        },
      )..addListener(_changed);
      await _download!.start();
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _accessError = e);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _open({bool export = false}) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final ok = export ? await _download!.export() : await _download!.open();
      if (!ok && mounted) {
        _checkAccess();
        if (_accessError == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n(context).refActionFailed)),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_checkAccess);
    _download?.removeListener(_changed);
    _download?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = l10n(context);
    TaskReference file;
    try {
      file = widget.app.repository.reference(widget.taskId, widget.referenceId);
    } on RepositoryException {
      return InfoNote(s.refAccessDenied, warning: true);
    }
    if (_accessError != null) return InfoNote(s.refAccessDenied, warning: true);
    if (widget.compact) {
      return IconButton(
        key: ValueKey('reference-download-${widget.referenceId}'),
        tooltip: s.refDownload,
        onPressed: () {
          // Rows can be reused when a file disappears. The open sheet must
          // keep the identity and account from the original tap.
          final app = widget.app;
          final taskId = widget.taskId;
          final referenceId = widget.referenceId;
          final store = widget.store;
          final sessionId = app.repository.session?.id;
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: ListenableBuilder(
                  listenable: app,
                  builder: (context, _) {
                    // A bottom sheet outlives the row that opened it. Revalidate
                    // its filename as well as the transfer controls on changes.
                    try {
                      if (app.repository.session?.id != sessionId) {
                        throw const RepositoryException('session_changed', '');
                      }
                      final current = app.repository.reference(
                        taskId,
                        referenceId,
                      );
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            current.fileName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Gap(16),
                          ReferenceDownloadButton(
                            app: app,
                            taskId: taskId,
                            referenceId: referenceId,
                            autoStart: true,
                            store: store,
                          ),
                        ],
                      );
                    } on RepositoryException {
                      return InfoNote(
                        l10n(context).refAccessDenied,
                        warning: true,
                      );
                    }
                  },
                ),
              ),
            ),
          );
        },
        icon: Icon(
          Icons.download_outlined,
          size: 20,
          color: AppColors.of(context).primary,
        ),
      );
    }
    final download = _download;
    final state = download?.state ?? ReferenceDownloadState.idle;
    if (download?.error is RepositoryException) {
      return InfoNote(s.refAccessDenied, warning: true);
    }
    return Column(
      key: ValueKey('reference-download-panel-${widget.referenceId}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state == ReferenceDownloadState.loading) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  s.refDownloading((download!.progress * 100).round()),
                ),
              ),
              TextButton(
                key: const Key('download-cancel'),
                onPressed: download.cancel,
                child: Text(s.refCancel),
              ),
            ],
          ),
          LinearProgressIndicator(value: download.progress),
        ] else if (state == ReferenceDownloadState.completed) ...[
          Text(s.refDownloaded, style: Theme.of(context).textTheme.titleSmall),
          const Gap(6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('download-open'),
                  onPressed: _opening ? null : () => _open(),
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: Text(s.refOpen),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('download-export'),
                  onPressed: _opening ? null : () => _open(export: true),
                  icon: const Icon(Icons.ios_share, size: 17),
                  label: Text(s.refExport),
                ),
              ),
            ],
          ),
          Text(s.refSavedInApp, style: Theme.of(context).textTheme.labelSmall),
        ] else ...[
          if (state == ReferenceDownloadState.failed ||
              state == ReferenceDownloadState.cancelled) ...[
            InfoNote(
              state == ReferenceDownloadState.failed
                  ? s.refDownloadFailed
                  : s.refCancelled,
              warning: state == ReferenceDownloadState.failed,
            ),
            const Gap(8),
          ],
          PrimaryButton(
            key: ValueKey('download-start-${widget.referenceId}'),
            label: state == ReferenceDownloadState.failed
                ? s.refRetry
                : switch (file.kind) {
                    ReferenceKind.image => s.refImageDownload,
                    ReferenceKind.video => s.refVideoDownload,
                    _ => s.refDownload,
                  },
            icon: Icons.download_outlined,
            onPressed: _start,
          ),
          const Gap(6),
          Text(
            s.refLocalSample,
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
