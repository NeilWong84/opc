import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../l10n/strings.dart';
import 'api_workspace.dart';
import 'api_rich_content.dart';
import 'api_file_card.dart';
import 'api_negotiation_page.dart';

class ApiWorkPage extends StatefulWidget {
  const ApiWorkPage({
    super.key,
    required this.app,
    required this.id,
    this.showMessages = false,
    this.openDelivery = false,
  });
  final AppController app;
  final String id;
  final bool showMessages;
  final bool openDelivery;
  @override
  State<ApiWorkPage> createState() => _ApiWorkPageState();
}

class _ApiWorkPageState extends State<ApiWorkPage> with WidgetsBindingObserver {
  final _message = TextEditingController();
  bool _loading = true;
  bool _refreshing = false;
  bool _waitingForIdle = false;
  Object? _error;
  bool _deliveryOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(_onAppChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.removeListener(_onAppChanged);
    _message.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      _refresh();
    }
  }

  void _onAppChanged() {
    if (_waitingForIdle && !widget.app.busy) {
      _waitingForIdle = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _refreshing) return;
    if (widget.app.busy) {
      // 首页刷新尚未结束时排队，不能直接退出并留下永远不结束的加载状态。
      _waitingForIdle = true;
      return;
    }
    _waitingForIdle = false;
    _refreshing = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.app.run(() => remote(widget.app).refreshItem(widget.id));
    } catch (error) {
      if (mounted) setState(() => _error = error);
      if (mounted && widget.app.repository.session == null) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
    if (mounted && _error == null && widget.openDelivery && !_deliveryOpened) {
      _deliveryOpened = true;
      if (widget.app.repository
          .detail(widget.id)
          .canSubmitDeliveryBy(widget.app.repository.session)) {
        await _openDelivery();
      }
    }
  }

  Future<void> _openDelivery() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ApiDeliveryPage(app: widget.app, id: widget.id),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _openNegotiation([String? threadId]) async {
    var id = threadId;
    if (id == null) {
      final ok = await apiAction(context, widget.app, () async {
        id = await remote(widget.app).startNegotiation(widget.id);
      });
      if (!ok) return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ApiNegotiationPage(app: widget.app, threadId: id!),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n(context).apiCancel),
            ),
            FilledButton(
              key: const Key('api-confirm-dialog'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(title),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _confirmAgreement(WorkItem item) async {
    final s = l10n(context);
    if (!await _confirm(
      s.apiConfirmTerms,
      '${s.apiConfirmTermsBody}\n\nv${item.agreementVersion}\n${item.agreementTerms}',
    )) {
      return;
    }
    if (!mounted) return;
    await apiAction(
      context,
      widget.app,
      () => remote(widget.app).confirmAgreement(widget.id),
      success: s.apiConfirmed,
    );
  }

  Future<void> _send(WorkItem item) async {
    if (_message.text.trim().isEmpty) return;
    final repo = widget.app.repository;
    final provider = repo.session?.role == UserRole.provider;
    final text = _message.text.trim();
    final ok = await apiAction(context, widget.app, () async {
      if (item.engagementId == null && provider) {
        await repo.consult(widget.id, text);
      } else if (item.question != null && !provider) {
        await repo.answerQuestion(widget.id, text);
      } else {
        await repo.sendMessage(widget.id, text);
      }
    }, success: l10n(context).apiMessageSent);
    if (ok) _message.clear();
  }

  Future<void> _accept(Delivery delivery) async {
    final s = l10n(context);
    if (!await _confirm(
      s.apiAccept,
      '${s.apiAcceptBody}\n\nv${delivery.version}',
    )) {
      return;
    }
    if (!mounted) return;
    await apiAction(
      context,
      widget.app,
      () => widget.app.repository.acceptDelivery(widget.id, delivery.version),
      success: s.apiChanged,
    );
  }

  Future<void> _revision(Delivery delivery) async {
    final s = l10n(context);
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.apiRevision),
        scrollable: true,
        content: LocalizedForm(
          key: form,
          child: TextFormField(
            key: const Key('api-revision-reason'),
            controller: reason,
            minLines: 4,
            maxLines: 8,
            maxLength: 4000,
            decoration: InputDecoration(labelText: s.apiRevisionReason),
            validator: (text) =>
                (text ?? '').trim().isEmpty ? s.apiRequired : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.apiCancel),
          ),
          FilledButton(
            key: const Key('api-revision-confirm'),
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, reason.text.trim());
              }
            },
            child: Text(s.apiRevision),
          ),
        ],
      ),
    );
    // A dialog may finish its closing animation after its Future resolves.
    Future<void>.delayed(const Duration(seconds: 1), reason.dispose);
    if (value == null || !mounted) return;
    await apiAction(
      context,
      widget.app,
      () => widget.app.repository.requestRevision(
        widget.id,
        delivery.version,
        value,
      ),
      success: s.apiChanged,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final s = l10n(context);
      if (_loading) {
        return OpcPage(
          title: s.apiDetails,
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      if (_error != null) {
        return OpcPage(
          title: s.apiDetails,
          child: Column(
            children: [
              InfoNote(apiError(context, _error!), warning: true),
              const Gap(20),
              PrimaryButton(label: s.apiRetry, onPressed: _refresh),
            ],
          ),
        );
      }
      final WorkItem item;
      try {
        item = widget.app.repository.detail(widget.id);
      } on RepositoryException catch (error) {
        return OpcPage(
          title: s.apiDetails,
          actions: [ApiRefreshButton(app: widget.app, onRefresh: _refresh)],
          child: InfoNote(apiError(context, error), warning: true),
        );
      }
      final provider = widget.app.repository.session?.role == UserRole.provider;
      final canDeliver = item.canSubmitDeliveryBy(
        widget.app.repository.session,
      );
      final published = item.deliveries.where((d) => d.published).toList()
        ..sort((a, b) => b.version.compareTo(a.version));
      final latest = published.firstOrNull;
      final c = AppColors.of(context);
      return OpcPage(
        title: widget.showMessages ? s.apiMessages : s.apiDetails,
        actions: [ApiRefreshButton(app: widget.app, onRefresh: _refresh)],
        bottom: item.pendingConfirmation
            ? item.confirmedByMe
                  ? InfoNote(s.apiTermsConfirmed)
                  : PrimaryButton(
                      key: const Key('api-confirm-agreement'),
                      label: s.apiConfirmTerms,
                      onPressed: widget.app.busy
                          ? null
                          : () => _confirmAgreement(item),
                    )
            : canDeliver
            ? PrimaryButton(
                key: const Key('api-open-delivery'),
                label: s.apiOpenDelivery,
                icon: Icons.cloud_upload_outlined,
                onPressed: widget.app.busy ? null : _openDelivery,
              )
            : !provider &&
                  item.status == WorkStatus.awaitingAcceptance &&
                  latest != null
            ? Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      key: const Key('api-revision'),
                      label: s.apiRevision,
                      secondary: true,
                      onPressed: widget.app.busy
                          ? null
                          : () => _revision(latest),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryButton(
                      key: const Key('api-accept-delivery'),
                      label: s.apiAccept,
                      onPressed: widget.app.busy ? null : () => _accept(latest),
                    ),
                  ),
                ],
              )
            : provider && item.engagementId == null && item.isPublished
            ? PrimaryButton(
                key: const Key('api-start-negotiation'),
                label: s.negotiationStart,
                icon: Icons.chat_bubble_outline,
                onPressed: widget.app.busy ? null : () => _openNegotiation(),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OpcCard(
              color: c.hero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    item.publicCode ?? item.id,
                    style: TextStyle(color: c.heroMuted),
                  ),
                  const Gap(12),
                  Text(
                    item.title,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(color: c.heroText),
                  ),
                  const Gap(16),
                  Text(
                    '${apiStatus(context, item)} · ${s.apiVersion} ${item.version}',
                    style: TextStyle(color: c.heroMuted),
                  ),
                ],
              ),
            ),
            const Gap(20),
            if (!widget.showMessages) ...[
              ApiRichContent(app: widget.app, text: item.description),
              const Gap(16),
              if (item.duration.isNotEmpty)
                Text('${s.apiTiming}: ${item.duration}'),
              if (item.budget.isNotEmpty)
                Text('${s.apiBudget}: ${item.budget}'),
              if (item.latestNote?.isNotEmpty ?? false) ...[
                const Gap(12),
                InfoNote(item.latestNote!),
              ],
              const Gap(20),
              if (item.engagementId != null) ...[
                OpcCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionLabel('${s.apiTerms} · v${item.agreementVersion}'),
                      const Gap(12),
                      ApiRichContent(
                        app: widget.app,
                        text: item.agreementTerms,
                      ),
                      if (item.quotedAmount != null) ...[
                        const Gap(12),
                        Text('${s.apiAmount}: ${item.quotedAmount}'),
                      ],
                      if (item.dueAt != null) ...[
                        const Gap(8),
                        Text('${s.apiDueAt}: ${jst(item.dueAt!)}'),
                      ],
                      const Gap(16),
                      ApiScopeDetails(scope: item.scope, app: widget.app),
                    ],
                  ),
                ),
                const Gap(20),
              ] else if (item.scope.isNotEmpty) ...[
                ApiScopeDetails(scope: item.scope, app: widget.app),
                const Gap(20),
              ],
              if (item.files.isNotEmpty) ...[
                SectionLabel(s.apiFiles),
                ApiFileList(app: widget.app, files: item.files),
                const Gap(16),
              ],
              if (item.references.isNotEmpty) ...[
                SectionLabel(s.refTitle),
                const Gap(8),
                for (final reference in item.references)
                  ApiFileCard(
                    key: ValueKey('api-reference-${reference.id}'),
                    name: reference.fileName,
                    sizeBytes: reference.sizeBytes,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ApiFilePage(app: widget.app, fileId: reference.id),
                      ),
                    ),
                  ),
                const Gap(16),
              ],
              for (final delivery in item.deliveries.reversed) ...[
                ApiDeliveryCard(app: widget.app, delivery: delivery),
                const Gap(16),
              ],
            ],
            for (final thread in remote(
              widget.app,
            ).negotiations(widget.id)) ...[
              PrimaryButton(
                key: ValueKey('api-negotiation-${thread.id}'),
                label: '${s.negotiationTitle} · ${thread.name}',
                secondary: true,
                icon: Icons.handshake_outlined,
                onPressed: widget.app.busy
                    ? null
                    : () => _openNegotiation(thread.id),
              ),
              const Gap(12),
            ],
            SectionLabel(s.apiMessages),
            const Gap(12),
            if (item.question != null) ...[
              InfoNote(item.question!, warning: true),
              const Gap(16),
            ],
            if (provider && item.engagementId == null) ...[
              InfoNote(s.apiConsultNotice),
              const Gap(12),
            ],
            for (final message in item.messages) ...[
              OpcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      message.author,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(8),
                    ApiRichContent(app: widget.app, text: message.text),
                    const Gap(8),
                    Text(
                      jst(message.sentAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Gap(10),
            ],
            TextField(
              key: const Key('api-message-input'),
              controller: _message,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              enabled: !widget.app.busy,
              decoration: InputDecoration(labelText: s.apiMessageInput),
            ),
            const Gap(12),
            PrimaryButton(
              key: const Key('api-message-send'),
              label: item.question != null && !provider
                  ? s.apiReply
                  : s.apiSend,
              onPressed: widget.app.busy ? null : () => _send(item),
              icon: Icons.send_outlined,
            ),
          ],
        ),
      );
    },
  );
}

class ApiDeliveryCard extends StatelessWidget {
  const ApiDeliveryCard({super.key, required this.app, required this.delivery});
  final AppController app;
  final Delivery delivery;
  @override
  Widget build(BuildContext context) {
    final s = l10n(context);
    return OpcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel('${s.apiDelivery} · v${delivery.version}'),
          const Gap(10),
          StatusPill(
            delivery.published
                ? s.apiPublishedDelivery
                : s.apiUnpublishedDelivery,
          ),
          const Gap(14),
          ApiRichContent(app: app, text: delivery.note),
          const Gap(16),
          if (delivery.repositoryUrl != null) ...[
            Text(
              s.apiSourceRepo,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Gap(6),
            SelectableText(delivery.repositoryUrl!),
            const Gap(8),
            SelectableText(delivery.sourceRef),
            if (delivery.sourceArchiveRef != null) ...[
              const Gap(8),
              SelectableText(delivery.sourceArchiveRef!),
            ],
            const Gap(16),
          ],
          Text(s.apiGuide, style: Theme.of(context).textTheme.titleSmall),
          const Gap(6),
          ApiRichContent(app: app, text: delivery.guideName),
          const Gap(16),
          Text(
            s.apiTestEvidence,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Gap(6),
          ApiRichContent(app: app, text: delivery.testName),
          const Gap(12),
          ApiFileList(app: app, files: delivery.files),
        ],
      ),
    );
  }
}

class ApiScopeDetails extends StatelessWidget {
  const ApiScopeDetails({super.key, required this.scope, this.app});
  final Map<String, dynamic> scope;
  final AppController? app;
  @override
  Widget build(BuildContext context) {
    final s = l10n(context);
    final labels = {
      'included_scope': s.apiScopeIncluded,
      'excluded_scope': s.apiScopeExcluded,
      'deliverables': s.apiScopeDeliverables,
      'acceptance_criteria': s.apiScopeAcceptance,
      'revision_terms': s.apiScopeRevision,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in labels.entries)
          if (scope[entry.key] != null) ...[
            Text(entry.value, style: Theme.of(context).textTheme.titleSmall),
            const Gap(6),
            if (app == null)
              SelectableText(
                scope[entry.key] is List
                    ? (scope[entry.key] as List).join('\n')
                    : scope[entry.key].toString(),
              )
            else
              ApiRichContent(
                app: app!,
                text: scope[entry.key] is List
                    ? (scope[entry.key] as List).join('\n')
                    : scope[entry.key].toString(),
              ),
            const Gap(14),
          ],
      ],
    );
  }
}

String apiStatus(BuildContext context, WorkItem item) {
  final s = l10n(context);
  return switch (item.intakeState) {
    'draft' => s.apiDraft,
    'pending_confirmation' => s.apiPendingTerms,
    'withdrawn' => s.apiWithdrawn,
    'rejected' => s.apiRejected,
    'cancelled' => s.apiCancelled,
    _ => statusLabel(context, item.status),
  };
}
