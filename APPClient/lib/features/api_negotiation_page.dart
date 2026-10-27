import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../l10n/strings.dart';
import 'api_workspace.dart';
import 'api_rich_content.dart';

class ApiNegotiationPage extends StatefulWidget {
  const ApiNegotiationPage({
    super.key,
    required this.app,
    required this.threadId,
  });
  final AppController app;
  final String threadId;
  @override
  State<ApiNegotiationPage> createState() => _ApiNegotiationPageState();
}

class _ApiNegotiationPageState extends State<ApiNegotiationPage>
    with WidgetsBindingObserver {
  Negotiation? _data;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;
  final _message = TextEditingController();
  final _terms = TextEditingController();
  final _amount = TextEditingController();
  DateTime? _dueAt;
  bool _editProposal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _message.dispose();
    _terms.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await remote(widget.app).negotiation(widget.threadId);
      if (mounted) setState(() => _data = data);
    } catch (error) {
      if (mounted) {
        setState(() {
          _data = null;
          _error = error;
        });
      }
      if (mounted && widget.app.repository.session == null) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n(context).apiCancel),
            ),
            FilledButton(
              key: const Key('negotiation-confirm-dialog'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(title),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _propose() async {
    final s = l10n(context);
    final rawAmount = _amount.text.trim();
    final amount = rawAmount.isEmpty ? null : int.tryParse(rawAmount);
    if (_terms.text.trim().isEmpty ||
        (rawAmount.isNotEmpty &&
            (amount == null || amount < 0 || amount > 99999999999999))) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.negotiationFormError)));
      return;
    }
    final ok = await apiAction(
      context,
      widget.app,
      () =>
          remote(widget.app).proposeClaim(_data!, _terms.text, amount, _dueAt),
      success: s.negotiationProposed,
    );
    if (ok && mounted) {
      setState(() => _editProposal = false);
      await _refresh();
    }
  }

  Future<void> _approve() async {
    final s = l10n(context);
    if (!await _confirm(s.negotiationApprove, s.negotiationApproveBody)) return;
    if (!mounted) return;
    if (await apiAction(
      context,
      widget.app,
      () => remote(widget.app).confirmClaim(_data!),
      success: s.apiConfirmed,
    )) {
      await _refresh();
    }
  }

  Future<void> _claim() async {
    final s = l10n(context);
    if (!await _confirm(s.negotiationClaim, s.negotiationClaimBody)) return;
    if (!mounted) return;
    final requestId = _data!.requestId;
    final ok = await apiAction(
      context,
      widget.app,
      () => remote(widget.app).claimProject(_data!),
      success: s.negotiationClaimed,
    );
    if (ok && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ApiWorkPage(app: widget.app, id: requestId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final s = l10n(context);
      final data = _data;
      final session = widget.app.repository.session;
      if (session == null) return const SizedBox.shrink();
      final provider =
          session.role == UserRole.provider && data?.providerId == session.id;
      final proposal = data?.proposal;
      return OpcPage(
        title: s.negotiationTitle,
        onRefresh: _refresh,
        actions: [ApiRefreshButton(app: widget.app, onRefresh: _refresh)],
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Column(
                children: [
                  InfoNote(apiError(context, _error!), warning: true),
                  const Gap(16),
                  PrimaryButton(label: s.apiRetry, onPressed: _refresh),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    data!.scope['title'] as String? ?? '',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Gap(8),
                  Text('${s.negotiationProvider}: ${data.providerName}'),
                  const Gap(16),
                  ApiScopeDetails(app: widget.app, scope: data.scope),
                  const Gap(16),
                  if (!data.available)
                    InfoNote(s.negotiationUnavailable, warning: true),
                  if (proposal != null) ...[
                    OpcCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SectionLabel(s.apiTerms),
                          const Gap(10),
                          ApiRichContent(app: widget.app, text: proposal.terms),
                          if (proposal.amount != null) ...[
                            const Gap(8),
                            Text('${s.apiAmount}: ${proposal.amount}'),
                          ],
                          if (proposal.dueAt != null) ...[
                            const Gap(8),
                            Text('${s.apiDueAt}: ${jst(proposal.dueAt!)}'),
                          ],
                          const Gap(12),
                          InfoNote(
                            proposal.confirmed
                                ? s.negotiationApproved
                                : s.negotiationAwaiting,
                          ),
                          if (data.available && !data.currentProposal) ...[
                            const Gap(12),
                            InfoNote(s.negotiationOutdated, warning: true),
                          ],
                          if (data.currentProposal &&
                              !proposal.confirmed &&
                              session.id == data.customerId) ...[
                            const Gap(16),
                            PrimaryButton(
                              key: const Key('negotiation-approve'),
                              label: s.negotiationApprove,
                              onPressed: widget.app.busy ? null : _approve,
                            ),
                          ],
                          if (data.currentProposal &&
                              proposal.confirmed &&
                              provider) ...[
                            const Gap(16),
                            PrimaryButton(
                              key: const Key('negotiation-claim'),
                              label: s.negotiationClaim,
                              icon: Icons.handshake_outlined,
                              onPressed: widget.app.busy ? null : _claim,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Gap(16),
                  ],
                  if (provider && data.available) ...[
                    if (proposal != null && !_editProposal)
                      TextButton(
                        key: const Key('negotiation-edit-proposal'),
                        onPressed: widget.app.busy
                            ? null
                            : () => setState(() => _editProposal = true),
                        child: Text(s.negotiationEdit),
                      ),
                    if (proposal == null || _editProposal) ...[
                      TextField(
                        key: const Key('negotiation-terms'),
                        controller: _terms,
                        minLines: 3,
                        maxLines: 8,
                        maxLength: 12000,
                        decoration: InputDecoration(labelText: s.apiTerms),
                      ),
                      const Gap(12),
                      TextField(
                        key: const Key('negotiation-amount'),
                        controller: _amount,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: s.negotiationOptionalAmount,
                        ),
                      ),
                      const Gap(12),
                      OutlinedButton(
                        key: const Key('negotiation-due'),
                        onPressed: widget.app.busy
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _dueAt ?? now,
                                  firstDate: now.subtract(
                                    const Duration(days: 1),
                                  ),
                                  lastDate: now.add(const Duration(days: 3650)),
                                );
                                if (date != null && mounted) {
                                  setState(
                                    () => _dueAt = DateTime.utc(
                                      date.year,
                                      date.month,
                                      date.day,
                                      9,
                                    ),
                                  ); // JST 18:00
                                }
                              },
                        child: Text(
                          _dueAt == null
                              ? s.negotiationOptionalDue
                              : jst(_dueAt!),
                        ),
                      ),
                      const Gap(12),
                      PrimaryButton(
                        key: const Key('negotiation-propose'),
                        label: s.negotiationPropose,
                        onPressed: widget.app.busy ? null : _propose,
                      ),
                      const Gap(16),
                    ],
                  ],
                  SectionLabel(s.apiMessages),
                  const Gap(12),
                  for (final message in data.messages) ...[
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
                          Text(jst(message.sentAt)),
                        ],
                      ),
                    ),
                    const Gap(10),
                  ],
                  TextField(
                    key: const Key('negotiation-message'),
                    controller: _message,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 2000,
                    enabled: !widget.app.busy,
                    decoration: InputDecoration(labelText: s.apiMessageInput),
                  ),
                  const Gap(12),
                  PrimaryButton(
                    key: const Key('negotiation-send'),
                    label: s.apiSend,
                    icon: Icons.send_outlined,
                    onPressed: widget.app.busy
                        ? null
                        : () async {
                            if (_message.text.trim().isEmpty) return;
                            final ok = await apiAction(
                              context,
                              widget.app,
                              () => remote(widget.app).sendNegotiationMessage(
                                widget.threadId,
                                _message.text,
                              ),
                            );
                            if (ok && mounted) {
                              _message.clear();
                              await _refresh();
                            }
                          },
                  ),
                ],
              ),
      );
    },
  );
}
