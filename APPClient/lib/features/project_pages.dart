import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../l10n/app_localizations.dart';
import '../l10n/strings.dart';

/// Project, delivery and acceptance screens from the MasterGo mobile designs.
/// All attachment previews below are local examples; no code is executed.
class ProjectPage extends StatefulWidget {
  const ProjectPage({super.key, required this.app, required this.id});

  final AppController app;
  final String id;

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final WorkItem item;
      try {
        item = widget.app.repository.detail(widget.id);
      } on RepositoryException catch (error) {
        return _UnavailablePage(
          title: l10n(context).projectTitle,
          message: repositoryError(context, error),
        );
      }
      final colors = AppColors.of(context);
      final session = widget.app.repository.session;
      final provider = session?.role == UserRole.provider;
      final canDeliver =
          provider &&
          session!.active &&
          session.authorized &&
          item.providerId == session.id &&
          (item.status == WorkStatus.developing ||
              item.status == WorkStatus.revision);
      final deliveries = item.deliveries
          .where((delivery) => provider || delivery.published)
          .toList();
      final published = _latestPublished(item);

      return OpcPage(
        title: l10n(context).projectTitle,
        subtitle: provider
            ? l10n(context).projectProviderSubtitle
            : l10n(context).projectCustomerSubtitle,
        actions: [
          IconButton(
            tooltip: l10n(context).projectInfoTitle,
            onPressed: () => _showProjectInfo(context, item),
            icon: const Icon(Icons.more_horiz),
          ),
        ],
        bottom: provider
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.status == WorkStatus.internalReview) ...[
                    Text(
                      l10n(context).projectInternalReviewPending,
                      style: TextStyle(color: colors.secondary, fontSize: 11),
                    ),
                    const Gap(8),
                  ],
                  PrimaryButton(
                    label: item.status == WorkStatus.internalReview
                        ? l10n(context).projectAwaitingOperations
                        : item.status == WorkStatus.revision
                        ? l10n(context).projectSubmitRevision
                        : l10n(context).projectSubmitDelivery,
                    icon: Icons.cloud_upload_outlined,
                    onPressed: canDeliver && !widget.app.busy
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  DeliveryPage(app: widget.app, id: widget.id),
                            ),
                          )
                        : null,
                  ),
                ],
              )
            : PrimaryButton(
                label: published != null
                    ? l10n(context).projectReviewDelivery
                    : l10n(context).projectSendMessage,
                icon: published != null
                    ? Icons.task_alt
                    : Icons.chat_bubble_outline,
                onPressed: published != null
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              AcceptancePage(app: widget.app, id: widget.id),
                        ),
                      )
                    : () => _showMessages(context, widget.app, widget.id),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OpcCard(
              color: colors.hero,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.id,
                          style: TextStyle(
                            color: colors.heroMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: colors.dark
                              ? const Color(0xFF22584D)
                              : const Color(0xFF2A6155),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          statusLabel(context, item.status),
                          style: TextStyle(
                            color: colors.heroMuted,
                            fontSize: 11,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(14),
                  Text(
                    item.title,
                    style: TextStyle(
                      color: colors.heroText,
                      fontSize: 23,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(13),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        color: colors.heroMuted,
                        size: 17,
                      ),
                      const Gap(8),
                      Expanded(
                        child: Text(
                          _nextStep(context, item),
                          style: TextStyle(
                            color: colors.heroMuted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Gap(8),
            _WorkspaceTabs(
              selected: _tab,
              onSelected: (value) => setState(() => _tab = value),
            ),
            const Gap(14),
            if (_tab == 0) ...[
              _Milestones(item: item),
              const Gap(14),
              if (item.messages.isNotEmpty)
                _MessageCard(
                  message: item.messages.last,
                  onTap: () => _showMessages(context, widget.app, widget.id),
                )
              else
                OpcCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionLabel(l10n(context).projectConsultation),
                      const Gap(8),
                      Text(
                        l10n(context).projectConsultationHint,
                        style: TextStyle(color: colors.secondary, height: 1.6),
                      ),
                      const Gap(10),
                      PrimaryButton(
                        label: l10n(context).projectOpenMessages,
                        secondary: true,
                        onPressed: () =>
                            _showMessages(context, widget.app, widget.id),
                      ),
                    ],
                  ),
                ),
              if (item.status == WorkStatus.revision &&
                  item.latestNote != null) ...[
                const Gap(14),
                InfoNote(item.latestNote!, warning: true),
              ],
            ],
            if (_tab == 1) ...[
              if (item.messages.isEmpty)
                InfoNote(l10n(context).projectNoMessages),
              for (final message in item.messages) ...[
                _MessageCard(message: message),
                const Gap(10),
              ],
              PrimaryButton(
                label: l10n(context).projectSendMessage,
                secondary: true,
                icon: Icons.edit_outlined,
                onPressed: () => _showMessages(context, widget.app, widget.id),
              ),
            ],
            if (_tab == 2) ...[
              if (deliveries.isEmpty)
                InfoNote(
                  provider
                      ? l10n(context).projectNoProviderDeliveries
                      : l10n(context).projectNoCustomerDeliveries,
                  icon: Icons.folder_open_outlined,
                ),
              for (final delivery in deliveries.reversed) ...[
                _DeliveryFilesCard(delivery: delivery),
                const Gap(12),
              ],
            ],
          ],
        ),
      );
    },
  );
}

class DeliveryPage extends StatefulWidget {
  const DeliveryPage({super.key, required this.app, required this.id});

  final AppController app;
  final String id;

  @override
  State<DeliveryPage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<DeliveryPage> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController(
    text: 'FAQ 検索と回答の根拠表示を追加。\n確認用の手順を操作説明書にまとめました。',
  );
  String _source = 'opc-faq-v0.3.0.zip';
  String _sourceRef = 'v0.3.0 · 8f3a2c1';
  String _guide = '操作説明書.pdf';
  String _test = 'テスト結果.xlsx';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _replaceFile(String type) async {
    final current = switch (type) {
      'source' => _source,
      'guide' => _guide,
      _ => _test,
    };
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MockFilePicker(current: current, type: type),
    );
    if (!mounted || selected == null) return;
    setState(() {
      switch (type) {
        case 'source':
          _source = selected;
        case 'guide':
          _guide = selected;
        default:
          _test = selected;
      }
    });
  }

  Future<void> _editVersion() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _TextEditDialog(
        title: l10n(context).projectEditFixedVersion,
        label: l10n(context).projectFixedVersion,
        initial: _sourceRef,
        hint: l10n(context).projectFixedVersionHint,
        help: l10n(context).projectFixedVersionHelp,
        button: l10n(context).projectSave,
      ),
    );
    if (mounted && result != null) setState(() => _sourceRef = result);
  }

  Future<void> _submit(WorkItem item) async {
    if (!_formKey.currentState!.validate()) return;
    final version =
        item.deliveries.fold<int>(
          0,
          (value, delivery) =>
              delivery.version > value ? delivery.version : value,
        ) +
        1;
    final success = await performAction(
      context,
      widget.app,
      () => widget.app.repository.submitDelivery(
        widget.id,
        Delivery(
          version: version,
          sourceName: _source,
          sourceRef: _sourceRef,
          guideName: _guide,
          testName: _test,
          note: _note.text.trim(),
        ),
      ),
      success: l10n(context).projectSubmitted,
    );
    if (success && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final WorkItem item;
      try {
        item = widget.app.repository.detail(widget.id);
      } on RepositoryException catch (error) {
        return _UnavailablePage(
          title: l10n(context).projectDeliveryTitle,
          message: repositoryError(context, error),
        );
      }
      final colors = AppColors.of(context);
      final session = widget.app.repository.session;
      final authorized =
          session?.role == UserRole.provider &&
          session!.active &&
          session.authorized &&
          item.providerId == session.id;
      if (!authorized) {
        return _UnavailablePage(
          title: l10n(context).projectDeliveryTitle,
          message: l10n(context).projectDeliveryUnauthorized,
        );
      }
      final canSubmit =
          item.status == WorkStatus.developing ||
          item.status == WorkStatus.revision;
      return OpcPage(
        title: l10n(context).projectDeliveryTitle,
        subtitle: l10n(context).projectDeliverySubtitle,
        bottom: PrimaryButton(
          label: widget.app.busy
              ? l10n(context).projectSubmitting
              : canSubmit
              ? l10n(context).projectRequestReview
              : l10n(context).projectAwaitingOperations,
          icon: Icons.send_rounded,
          onPressed: canSubmit && !widget.app.busy ? () => _submit(item) : null,
        ),
        child: LocalizedForm(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OpcCard(
                color: colors.soft,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.folder_open_rounded, color: colors.primary),
                    const Gap(11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Gap(4),
                          Text(
                            l10n(context).projectSubmissionDestination(item.id),
                            style: TextStyle(
                              color: colors.secondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(13),
              OpcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SectionLabel(l10n(context).projectSourceCode),
                        ),
                        StatusPill(
                          l10n(context).projectRequired,
                          warning: true,
                        ),
                      ],
                    ),
                    const Gap(9),
                    _FileRow(
                      name: _source,
                      metadata: l10n(context).projectSourceSelected,
                      icon: Icons.code_rounded,
                      onTap: () => _showFilePreview(
                        context,
                        name: _source,
                        type: 'source',
                        version: _sourceRef,
                      ),
                      onReplace: canSubmit && !widget.app.busy
                          ? () => _replaceFile('source')
                          : null,
                    ),
                    const Gap(9),
                    Material(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: canSubmit && !widget.app.busy
                            ? _editVersion
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(11),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n(context).projectFixedVersion,
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    const Gap(4),
                                    Text(
                                      _sourceRef,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.edit_outlined,
                                size: 17,
                                color: colors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(13),
              OpcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionLabel(l10n(context).projectGuideAndTest),
                    const Gap(9),
                    _FileRow(
                      name: _guide,
                      metadata: l10n(context).projectGuideSelected,
                      icon: Icons.description_outlined,
                      onTap: () => _showFilePreview(
                        context,
                        name: _guide,
                        type: 'guide',
                        version: _sourceRef,
                      ),
                      onReplace: canSubmit && !widget.app.busy
                          ? () => _replaceFile('guide')
                          : null,
                    ),
                    Divider(color: colors.border, height: 22),
                    _FileRow(
                      name: _test,
                      metadata: l10n(context).projectTestSelected,
                      icon: Icons.table_chart_outlined,
                      onTap: () => _showFilePreview(
                        context,
                        name: _test,
                        type: 'test',
                        version: _sourceRef,
                      ),
                      onReplace: canSubmit && !widget.app.busy
                          ? () => _replaceFile('test')
                          : null,
                    ),
                  ],
                ),
              ),
              const Gap(14),
              Text(
                l10n(context).projectChanges,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Gap(7),
              TextFormField(
                controller: _note,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                enabled: canSubmit && !widget.app.busy,
                decoration: InputDecoration(
                  hintText: l10n(context).projectChangesHint,
                  counterText: '',
                ),
                style: const TextStyle(fontSize: 12, height: 1.7),
                validator: (value) => value == null || value.trim().isEmpty
                    ? l10n(context).projectChangesRequired
                    : null,
              ),
              const Gap(13),
              InfoNote(
                l10n(context).projectDeliveryReviewNotice,
                icon: Icons.shield_outlined,
              ),
              const Gap(8),
              Text(
                l10n(context).projectAttachmentsNotice,
                style: TextStyle(
                  color: colors.secondary,
                  fontSize: 10,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class AcceptancePage extends StatefulWidget {
  const AcceptancePage({super.key, required this.app, required this.id});

  final AppController app;
  final String id;

  @override
  State<AcceptancePage> createState() => _AcceptancePageState();
}

class _AcceptancePageState extends State<AcceptancePage> {
  final List<bool> _checked = [true, true, false];
  int? _checkedVersion;

  Future<void> _accept(Delivery delivery) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n(context).projectAcceptConfirmTitle),
        content: Text(l10n(context).projectAcceptConfirmBody(delivery.version)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n(context).projectBack),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n(context).projectCompleteAcceptance),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await performAction(
      context,
      widget.app,
      () => widget.app.repository.acceptDelivery(widget.id, delivery.version),
      success: l10n(context).projectAccepted,
    );
  }

  Future<void> _requestRevision(Delivery delivery) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _TextEditDialog(
        title: l10n(context).projectRequestRevision,
        label: l10n(context).projectRevisionContent,
        initial: '',
        hint: l10n(context).projectRevisionHint,
        help: l10n(context).projectRevisionHelp,
        button: l10n(context).projectRequestRevision,
        multiline: true,
      ),
    );
    if (!mounted || text == null) return;
    await performAction(
      context,
      widget.app,
      () => widget.app.repository.requestRevision(
        widget.id,
        delivery.version,
        text,
      ),
      success: l10n(context).projectRevisionRequested,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final WorkItem item;
      try {
        item = widget.app.repository.detail(widget.id);
      } on RepositoryException catch (error) {
        return _UnavailablePage(
          title: l10n(context).projectAcceptanceTitle,
          message: repositoryError(context, error),
        );
      }
      final delivery = _latestPublished(item);
      if (delivery == null) {
        return _UnavailablePage(
          title: l10n(context).projectAcceptanceTitle,
          message: l10n(context).projectNoPublishedDelivery,
        );
      }
      // A check belongs to one delivery version. A refreshed release must not
      // inherit confirmations that were made for an older set of files.
      if (_checkedVersion != delivery.version) {
        if (_checkedVersion != null) _checked.fillRange(0, 3, false);
        _checkedVersion = delivery.version;
      }
      final colors = AppColors.of(context);
      final session = widget.app.repository.session;
      final canReview =
          session?.role == UserRole.customer &&
          session!.id == item.ownerId &&
          item.status == WorkStatus.awaitingAcceptance;
      final count = item.status == WorkStatus.completed
          ? 3
          : _checked.where((checked) => checked).length;
      return OpcPage(
        title: l10n(context).projectAcceptanceTitle,
        subtitle: l10n(context).projectAcceptanceSubtitle,
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.status == WorkStatus.completed
                  ? l10n(context).projectAcceptedNotice
                  : item.status == WorkStatus.revision
                  ? l10n(context).projectRevisionPendingNotice
                  : l10n(context).projectCheckAllHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.secondary,
                fontSize: 10,
                height: 1.6,
              ),
            ),
            const Gap(8),
            PrimaryButton(
              label: item.status == WorkStatus.completed
                  ? l10n(context).projectAcceptanceComplete
                  : l10n(context).projectCompleteAcceptance,
              onPressed: canReview && count == 3 && !widget.app.busy
                  ? () => _accept(delivery)
                  : null,
            ),
            TextButton.icon(
              onPressed: canReview && !widget.app.busy
                  ? () => _requestRevision(delivery)
                  : null,
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: Text(l10n(context).projectRequestRevision),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.id,
                    style: TextStyle(color: colors.secondary, fontSize: 11),
                  ),
                ),
                StatusPill(statusLabel(context, item.status)),
              ],
            ),
            const Gap(10),
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 21,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Gap(10),
            Text(
              l10n(context).projectCustomerVersion(delivery.version),
              style: TextStyle(color: colors.secondary, fontSize: 11),
            ),
            const Gap(18),
            OpcCard(
              padding: const EdgeInsets.all(14),
              onTap: () => _showDemo(context, item, delivery),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 58,
                    decoration: BoxDecoration(
                      color: colors.soft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: colors.primary,
                      size: 32,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n(context).projectWatchDemo,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Gap(5),
                        Text(
                          l10n(context).projectDemoSummary,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.secondary,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(4),
                  Icon(
                    Icons.open_in_new_rounded,
                    color: colors.primary,
                    size: 17,
                  ),
                ],
              ),
            ),
            const Gap(15),
            OpcCard(
              color: colors.soft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () => _showPublishedFiles(context, delivery),
              child: Row(
                children: [
                  Icon(
                    Icons.description_rounded,
                    size: 21,
                    color: colors.primary,
                  ),
                  const Gap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n(context).projectPublishedFiles,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Gap(4),
                        Text(
                          l10n(context).projectPublishedFileCount,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.secondary, size: 20),
                ],
              ),
            ),
            const Gap(15),
            OpcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SectionLabel(
                          l10n(context).projectAcceptanceChecklist,
                        ),
                      ),
                      const Gap(8),
                      Text(
                        '$count / 3',
                        style: TextStyle(
                          color: colors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const Gap(8),
                  for (var index = 0; index < 3; index++)
                    CheckboxListTile(
                      key: ValueKey('acceptance-check-$index'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      visualDensity: VisualDensity.compact,
                      dense: true,
                      value:
                          item.status == WorkStatus.completed ||
                          _checked[index],
                      onChanged: canReview && !widget.app.busy
                          ? (value) =>
                                setState(() => _checked[index] = value ?? false)
                          : null,
                      title: Text(
                        _acceptanceChecks(context, item)[index],
                        style: const TextStyle(fontSize: 12, height: 1.75),
                      ),
                    ),
                ],
              ),
            ),
            const Gap(16),
            if (item.status == WorkStatus.revision)
              InfoNote(
                item.latestNote ?? l10n(context).projectRevisionReviewing,
                icon: Icons.edit_note_rounded,
              )
            else if (item.status == WorkStatus.completed)
              InfoNote(
                l10n(context).projectAcceptedFilesNotice,
                icon: Icons.task_alt,
              )
            else
              InfoNote(
                l10n(context).projectRevisionInvitation,
                icon: Icons.chat_bubble_outline,
              ),
          ],
        ),
      );
    },
  );
}

class _WorkspaceTabs extends StatelessWidget {
  const _WorkspaceTabs({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < 3; index++)
            Expanded(
              child: Semantics(
                selected: selected == index,
                button: true,
                child: InkWell(
                  onTap: () => onSelected(index),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 3,
                          color: selected == index
                              ? colors.primary
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Text(
                      [
                        l10n(context).projectProgressTab,
                        l10n(context).projectMessagesTab,
                        l10n(context).projectFilesTab,
                      ][index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected == index
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected == index
                            ? colors.primary
                            : colors.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Milestones extends StatelessWidget {
  const _Milestones({required this.item});
  final WorkItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final current = switch (item.status) {
      WorkStatus.internalReview => 2,
      WorkStatus.awaitingAcceptance => 3,
      WorkStatus.completed => 4,
      _ => 1,
    };
    return OpcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(l10n(context).projectMilestones),
          const Gap(13),
          for (var index = 0; index < 4; index++) ...[
            if (index > 0) const Gap(16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 29,
                  height: 29,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < current
                        ? colors.primary
                        : index == current
                        ? colors.soft
                        : colors.raised,
                  ),
                  child: Icon(
                    index < current
                        ? Icons.check_rounded
                        : index == current
                        ? index == 1
                              ? Icons.code_rounded
                              : Icons.more_horiz
                        : Icons.circle,
                    size: index > current ? 9 : 17,
                    color: index < current
                        ? colors.onPrimary
                        : index == current
                        ? colors.primary
                        : colors.secondary,
                  ),
                ),
                const Gap(11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          l10n(context).projectRequirementsMilestone,
                          l10n(context).projectDevelopmentMilestone,
                          l10n(context).projectInternalMilestone,
                          l10n(context).projectCustomerMilestone,
                        ][index],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: index > current
                              ? colors.secondary
                              : colors.text,
                        ),
                      ),
                      const Gap(3),
                      Text(
                        index == 1 && item.status == WorkStatus.revision
                            ? l10n(context).projectRevisionMilestoneDescription
                            : [
                                l10n(
                                  context,
                                ).projectRequirementsMilestoneDescription,
                                l10n(
                                  context,
                                ).projectDevelopmentMilestoneDescription,
                                l10n(
                                  context,
                                ).projectInternalMilestoneDescription,
                                l10n(
                                  context,
                                ).projectCustomerMilestoneDescription,
                              ][index],
                        style: TextStyle(
                          color: colors.secondary,
                          fontSize: 10,
                          height: 1.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.onTap});
  final ChatMessage message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final japanTime = message.sentAt.toUtc().add(const Duration(hours: 9));
    final time =
        '${japanTime.hour.toString().padLeft(2, '0')}:${japanTime.minute.toString().padLeft(2, '0')}';
    return OpcCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: colors.soft,
                foregroundColor: colors.primary,
                child: Text(
                  message.author.startsWith('OPC')
                      ? 'O'
                      : l10n(context).projectMessageAvatar,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  message.author,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Gap(8),
              Text(
                time,
                style: TextStyle(color: colors.secondary, fontSize: 10),
              ),
            ],
          ),
          const Gap(10),
          Text(
            message.text,
            style: TextStyle(
              color: colors.secondary,
              fontSize: 12,
              height: 1.85,
            ),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.metadata,
    required this.icon,
    required this.onTap,
    this.onReplace,
  });
  final String name;
  final String metadata;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.soft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 21, color: colors.primary),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.6,
                          ),
                        ),
                        const Gap(3),
                        Text(
                          metadata,
                          style: TextStyle(
                            color: colors.secondary,
                            fontSize: 10,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onReplace != null)
          IconButton(
            tooltip: l10n(context).projectReplaceFile,
            onPressed: onReplace,
            icon: Icon(Icons.swap_horiz, color: colors.primary, size: 21),
          )
        else ...[
          const Gap(8),
          Icon(Icons.chevron_right, color: colors.primary, size: 19),
        ],
      ],
    );
  }
}

class _DeliveryFilesCard extends StatelessWidget {
  const _DeliveryFilesCard({required this.delivery});
  final Delivery delivery;

  @override
  Widget build(BuildContext context) => OpcCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SectionLabel(
                l10n(context).projectSubmittedVersion(delivery.version),
              ),
            ),
            const Gap(8),
            StatusPill(
              delivery.published
                  ? l10n(context).projectDeliveryPublished
                  : l10n(context).projectDeliveryInternal,
            ),
          ],
        ),
        const Gap(12),
        _FileRow(
          name: delivery.sourceName,
          metadata: delivery.sourceRef,
          icon: Icons.code_rounded,
          onTap: () => _showFilePreview(
            context,
            name: delivery.sourceName,
            type: 'source',
            version: delivery.sourceRef,
          ),
        ),
        const Gap(10),
        _FileRow(
          name: delivery.guideName,
          metadata: l10n(context).projectGuideMetadata,
          icon: Icons.description_outlined,
          onTap: () => _showFilePreview(
            context,
            name: delivery.guideName,
            type: 'guide',
            version: delivery.sourceRef,
          ),
        ),
        const Gap(10),
        _FileRow(
          name: delivery.testName,
          metadata: l10n(context).projectTestMetadata,
          icon: Icons.table_chart_outlined,
          onTap: () => _showFilePreview(
            context,
            name: delivery.testName,
            type: 'test',
            version: delivery.sourceRef,
          ),
        ),
        const Gap(12),
        Text(delivery.note, style: const TextStyle(fontSize: 12, height: 1.8)),
      ],
    ),
  );
}

Future<void> _showMessages(
  BuildContext context,
  AppController app,
  String id,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _MessagesSheet(app: app, id: id),
);

class _MessagesSheet extends StatefulWidget {
  const _MessagesSheet({required this.app, required this.id});
  final AppController app;
  final String id;

  @override
  State<_MessagesSheet> createState() => _MessagesSheetState();
}

class _MessagesSheetState extends State<_MessagesSheet> {
  final _text = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final success = await performAction(
      context,
      widget.app,
      () => widget.app.repository.sendMessage(widget.id, _text.text.trim()),
      success: l10n(context).projectMessageSent,
    );
    if (!mounted || !success) return;
    _text.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final colors = AppColors.of(context);
      final WorkItem item;
      try {
        item = widget.app.repository.detail(widget.id);
      } on RepositoryException catch (error) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: InfoNote(repositoryError(context, error), warning: true),
        );
      }
      return _SheetBody(
        title: l10n(context).projectMessagesTab,
        scrollController: _scroll,
        children: [
          Text(
            '${item.id} · ${item.title}',
            style: TextStyle(color: colors.secondary, fontSize: 11),
          ),
          const Gap(14),
          if (item.messages.isEmpty) InfoNote(l10n(context).projectNoMessages),
          for (final message in item.messages) ...[
            _MessageCard(message: message),
            const Gap(10),
          ],
          const Gap(6),
          LocalizedForm(
            key: _form,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 2000,
                    enabled: !widget.app.busy,
                    decoration: InputDecoration(
                      hintText: l10n(context).projectMessageHint,
                      counterText: '',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? l10n(context).projectMessageRequired
                        : null,
                  ),
                ),
                const Gap(8),
                IconButton.filled(
                  tooltip: l10n(context).projectMessageSendTooltip,
                  onPressed: widget.app.busy ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _MockFilePicker extends StatefulWidget {
  const _MockFilePicker({required this.current, required this.type});
  final String current;
  final String type;

  @override
  State<_MockFilePicker> createState() => _MockFilePickerState();
}

class _MockFilePickerState extends State<_MockFilePicker> {
  late final _name = TextEditingController(text: widget.current);
  final _key = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final samples = switch (widget.type) {
      'source' => ['opc-faq-v0.3.0.zip', 'opc-faq-v0.3.1.zip'],
      'guide' => ['操作説明書.pdf', '操作説明書_改訂版.pdf'],
      _ => ['テスト結果.xlsx', 'テスト結果_修正版.xlsx'],
    };
    return _SheetBody(
      title: l10n(context).projectSelectFile,
      children: [
        InfoNote(l10n(context).projectFilePickerNotice),
        const Gap(12),
        for (final sample in samples)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(sample, style: const TextStyle(fontSize: 13)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _name.text = sample),
          ),
        const Gap(10),
        LocalizedForm(
          key: _key,
          child: TextFormField(
            controller: _name,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: l10n(context).projectSampleFilename,
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? l10n(context).projectFilenameRequired
                : null,
          ),
        ),
        const Gap(12),
        PrimaryButton(
          label: l10n(context).projectUseSample,
          onPressed: () {
            if (_key.currentState!.validate()) {
              Navigator.of(context).pop(_name.text.trim());
            }
          },
        ),
      ],
    );
  }
}

class _TextEditDialog extends StatefulWidget {
  const _TextEditDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.hint,
    required this.help,
    required this.button,
    this.multiline = false,
  });
  final String title;
  final String label;
  final String initial;
  final String hint;
  final String help;
  final String button;
  final bool multiline;

  @override
  State<_TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<_TextEditDialog> {
  final _form = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: LocalizedForm(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.help, style: const TextStyle(fontSize: 12, height: 1.7)),
          const Gap(16),
          TextFormField(
            controller: _text,
            autofocus: true,
            minLines: widget.multiline ? 3 : 1,
            maxLines: widget.multiline ? 6 : 2,
            maxLength: widget.multiline ? 2000 : 160,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              alignLabelWithHint: true,
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? l10n(context).projectFieldRequired(widget.label)
                : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n(context).projectCancel),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.of(context).pop(_text.text.trim());
          }
        },
        child: Text(widget.button),
      ),
    ],
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.children,
    this.scrollController,
  });
  final String title;
  final List<Widget> children;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n(context).projectClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Gap(14),
            ...children,
          ],
        ),
      ),
    ),
  );
}

void _showFilePreview(
  BuildContext context, {
  required String name,
  required String type,
  required String version,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SheetBody(
      title: name,
      children: [
        Text(
          l10n(context).projectTargetVersion(version),
          style: const TextStyle(fontSize: 12),
        ),
        const Gap(16),
        OpcCard(
          child: Text(switch (type) {
            'source' => l10n(context).projectSourcePreview,
            'guide' => l10n(context).projectGuidePreview,
            _ => l10n(context).projectTestPreview,
          }, style: const TextStyle(fontSize: 13, height: 1.85)),
        ),
        const Gap(14),
        InfoNote(l10n(context).projectFileAccessNotice),
      ],
    ),
  );
}

void _showPublishedFiles(BuildContext context, Delivery delivery) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SheetBody(
      title: l10n(context).projectPublishedFiles,
      children: [_DeliveryFilesCard(delivery: delivery)],
    ),
  );
}

void _showDemo(BuildContext context, WorkItem item, Delivery delivery) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DemoSheet(item: item, delivery: delivery),
  );
}

class _DemoSheet extends StatefulWidget {
  const _DemoSheet({required this.item, required this.delivery});
  final WorkItem item;
  final Delivery delivery;

  @override
  State<_DemoSheet> createState() => _DemoSheetState();
}

class _DemoSheetState extends State<_DemoSheet> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return _SheetBody(
      title: l10n(context).projectDemoTitle,
      children: [
        Text(widget.item.title, style: const TextStyle(fontSize: 14)),
        const Gap(8),
        Text(
          l10n(context).projectDemoVersion(widget.delivery.sourceRef),
          style: TextStyle(fontSize: 11, color: colors.secondary),
        ),
        const Gap(16),
        OpcCard(
          color: colors.soft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                const [
                  Icons.add_circle_outline,
                  Icons.search_rounded,
                  Icons.task_alt,
                ][_step],
                size: 44,
                color: colors.primary,
              ),
              const Gap(16),
              Text(
                [
                  l10n(context).projectDemoRegister,
                  l10n(context).projectDemoSearch,
                  l10n(context).projectDemoUpdate,
                ][_step],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(10),
              Text(
                [
                  l10n(context).projectDemoRegisterDescription,
                  l10n(context).projectDemoSearchDescription,
                  l10n(context).projectDemoUpdateDescription,
                ][_step],
                style: const TextStyle(fontSize: 13, height: 1.9),
              ),
            ],
          ),
        ),
        const Gap(15),
        Text(
          '${_step + 1} / 3',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.primary),
        ),
        const Gap(10),
        PrimaryButton(
          label: _step == 2
              ? l10n(context).projectDemoRestart
              : l10n(context).projectDemoNext,
          onPressed: () => setState(() => _step = (_step + 1) % 3),
        ),
        const Gap(15),
        InfoNote(l10n(context).projectDemoNotice),
      ],
    );
  }
}

void _showProjectInfo(BuildContext context, WorkItem item) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SheetBody(
      title: l10n(context).projectInfoTitle,
      children: [
        Text(
          '${item.id} · ${item.title}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const Gap(12),
        Text(
          item.description,
          style: const TextStyle(fontSize: 13, height: 1.8),
        ),
        const Gap(16),
        InfoNote(l10n(context).projectConfirmedScope(item.version)),
        const Gap(10),
        InfoNote(
          l10n(context).projectInfoMessageNotice,
          icon: Icons.chat_bubble_outline,
        ),
      ],
    ),
  );
}

class _UnavailablePage extends StatelessWidget {
  const _UnavailablePage({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => OpcPage(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [InfoNote(message, warning: true)],
    ),
  );
}

Delivery? _latestPublished(WorkItem item) {
  Delivery? latest;
  for (final delivery in item.deliveries) {
    if (delivery.published &&
        (latest == null || delivery.version > latest.version)) {
      latest = delivery;
    }
  }
  return latest;
}

String _nextStep(BuildContext context, WorkItem item) => switch (item.status) {
  WorkStatus.developing => l10n(context).projectNextDeveloping,
  WorkStatus.internalReview => l10n(context).projectNextInternalReview,
  WorkStatus.awaitingAcceptance => l10n(context).projectNextAcceptance,
  WorkStatus.revision => l10n(context).projectNextRevision,
  WorkStatus.completed => l10n(context).projectNextCompleted,
  _ => l10n(context).projectNextDefault,
};

List<String> _acceptanceChecks(BuildContext context, WorkItem item) {
  final AppLocalizations strings = l10n(context);
  return item.title.contains('FAQ')
      ? [
          strings.projectCheckFaqSearch,
          strings.projectCheckFaqSources,
          strings.projectCheckGuide,
        ]
      : [
          strings.projectCheckSearch,
          strings.projectCheckUpdate,
          strings.projectCheckGuide,
        ];
}
