import 'package:flutter/material.dart';
import '../core/app_controller.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../data/mock_repository.dart';
import '../l10n/strings.dart';
import 'reference_widgets.dart';

class ReferenceListPage extends StatelessWidget {
  const ReferenceListPage({super.key, required this.app, required this.taskId});
  final AppController app;
  final String taskId;

  @override
  Widget build(BuildContext context) => RepositoryPageGuard(
    app: app,
    title: l10n(context).refTitle,
    builder: (context) {
      final item = app.repository.detail(taskId);
      final refs = app.repository.references(taskId);
      final images = refs.where((r) => r.kind == ReferenceKind.image).toList();
      final videos = refs.where((r) => r.kind == ReferenceKind.video).toList();
      final files = refs
          .where(
            (r) =>
                r.kind != ReferenceKind.image && r.kind != ReferenceKind.video,
          )
          .toList();
      return OpcPage(
        title: l10n(context).refTitle,
        subtitle: l10n(
          context,
        ).refPublishedVersion(taskId, item.publishedVersion ?? item.version),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoNote(l10n(context).refPublishedNotice),
            const Gap(16),
            if (refs.isEmpty) OpcCard(child: Text(l10n(context).refEmpty)),
            for (var i = 0; i < images.length; i += 2) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ReferenceThumbnail(
                      reference: images[i],
                      label: images[i].fileName,
                      height: 106,
                      onTap: () =>
                          openReference(context, app, taskId, images[i].id),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < images.length
                        ? ReferenceThumbnail(
                            reference: images[i + 1],
                            label: images[i + 1].fileName,
                            height: 106,
                            onTap: () => openReference(
                              context,
                              app,
                              taskId,
                              images[i + 1].id,
                            ),
                          )
                        : const SizedBox(),
                  ),
                ],
              ),
              const Gap(12),
            ],
            for (final video in videos) ...[
              OpcCard(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 106,
                      child: ReferenceThumbnail(
                        reference: video,
                        height: 66,
                        onTap: () =>
                            openReference(context, app, taskId, video.id),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            openReference(context, app, taskId, video.id),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              video.fileName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              '${video.extension.toUpperCase()} · ${referenceDuration(video.durationSeconds)} · ${referenceSize(video.sizeBytes)}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    ReferenceDownloadButton(
                      app: app,
                      taskId: taskId,
                      referenceId: video.id,
                      compact: true,
                    ),
                  ],
                ),
              ),
              const Gap(14),
            ],
            if (files.isNotEmpty) ...[
              SectionLabel(
                l10n(context).refAttachments,
                trailing: l10n(context).refCount(files.length),
              ),
              const Gap(10),
              for (final file in files) ...[
                ReferenceFileRow(app: app, taskId: taskId, reference: file),
                const Gap(8),
              ],
            ],
          ],
        ),
      );
    },
  );
}

/// The long MasterGo state board becomes independent reachable scenarios.
class ReferenceScenariosPage extends StatelessWidget {
  const ReferenceScenariosPage({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) => RepositoryPageGuard(
    app: app,
    title: l10n(context).refScenarios,
    builder: (context) {
      final mock = app.repository as MockOpcRepository;
      final items = mock
          .hall()
          .where((item) => item.references.isNotEmpty)
          .toList();
      return OpcPage(
        title: l10n(context).refScenarios,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoNote(l10n(context).refScenarioHelp),
            const Gap(20),
            for (final item in items) ...[
              Text(item.title, style: Theme.of(context).textTheme.titleMedium),
              const Gap(10),
              for (final state in ReferencePreviewState.values) ...[
                PrimaryButton(
                  secondary: true,
                  label: switch (state) {
                    ReferencePreviewState.ready => l10n(context).refReady,
                    ReferencePreviewState.preparing => l10n(
                      context,
                    ).refPreparing,
                    ReferencePreviewState.failed => l10n(
                      context,
                    ).refPreviewFailed,
                    ReferencePreviewState.unsupported => l10n(
                      context,
                    ).refUnsupported,
                  },
                  onPressed: () async {
                    final file = item.references.firstWhere(
                      (r) =>
                          r.kind != ReferenceKind.image &&
                          r.kind != ReferenceKind.video,
                      orElse: () => item.references.first,
                    );
                    final ok = await performAction(
                      context,
                      app,
                      () =>
                          mock.simulateReferenceState(item.id, file.id, state),
                    );
                    if (ok && context.mounted) {
                      openReference(context, app, item.id, file.id);
                    }
                  },
                ),
                const Gap(8),
              ],
              const Gap(12),
              SectionLabel(l10n(context).refDownloadFailureCase),
              const Gap(8),
              ReferenceDownloadButton(
                app: app,
                taskId: item.id,
                referenceId: item.references.first.id,
                failFirst: true,
              ),
              const Gap(24),
            ],
          ],
        ),
      );
    },
  );
}
