import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../l10n/strings.dart';

class CustomerHomePage extends StatelessWidget {
  const CustomerHomePage({
    super.key,
    required this.app,
    required this.onCreate,
    required this.onOpen,
    required this.onNotifications,
    this.navigation,
  });

  final AppController app;
  final VoidCallback onCreate;
  final ValueChanged<String> onOpen;
  final VoidCallback onNotifications;
  final Widget? navigation;

  @override
  Widget build(BuildContext context) => RepositoryPageGuard(
    app: app,
    title: l10n(context).customerRequestsTitle,
    builder: (context) {
      final colors = AppColors.of(context);
      final requests = app.repository.myRequests();
      return OpcPage(
        title: l10n(context).customerRequestsTitle,
        subtitle: l10n(context).customerWorkspaceSubtitle,
        back: false,
        navigation: navigation,
        actions: [
          IconButton(
            tooltip: l10n(context).customerNotifications,
            onPressed: onNotifications,
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
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
                          l10n(context).customerHeroTitle,
                          style: TextStyle(
                            color: colors.heroText,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: colors.heroText.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.code,
                          color: colors.heroText,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                  const Gap(8),
                  Text(
                    l10n(context).customerHeroSubtitle,
                    style: TextStyle(
                      color: colors.heroMuted,
                      fontSize: 11,
                      height: 1.65,
                    ),
                  ),
                  const Gap(16),
                  FilledButton(
                    onPressed: onCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.mint,
                      foregroundColor: colors.dark
                          ? colors.onPrimary
                          : colors.text,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.center,
                      children: [
                        Text(
                          l10n(context).customerCreateRequest,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (app.repository.draft != null) ...[
              const Gap(12),
              OpcCard(
                onTap: onCreate,
                child: Row(
                  children: [
                    Icon(Icons.edit_note, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n(context).customerContinueDraft,
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colors.primary),
                  ],
                ),
              ),
            ],
            const Gap(16),
            SectionLabel(
              l10n(context).customerActiveRequests,
              trailing: l10n(context).customerRequestCount(requests.length),
            ),
            const Gap(12),
            if (requests.isEmpty)
              OpcCard(
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 32),
                    Gap(10),
                    Text(l10n(context).customerNoRequests),
                    Gap(6),
                    Text(
                      l10n(context).customerNoRequestsHint,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            for (final request in requests) ...[
              _RequestCard(item: request, onTap: () => onOpen(request.id)),
              const Gap(12),
            ],
          ],
        ),
      );
    },
  );
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.item, required this.onTap});
  final WorkItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (item.status == WorkStatus.awaitingAcceptance) {
      return OpcCard(
        onTap: onTap,
        child: Row(
          children: [
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
                  const Gap(6),
                  Text(
                    l10n(context).customerDeliveryPrompt(item.id),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.7,
                      color: colors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.primary),
          ],
        ),
      );
    }
    return OpcCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.id,
                  style: TextStyle(fontSize: 10, color: colors.secondary),
                ),
              ),
              Flexible(
                child: StatusPill(
                  statusLabel(context, item.status),
                  warning:
                      item.status == WorkStatus.needsInfo ||
                      item.status == WorkStatus.reviewing,
                ),
              ),
            ],
          ),
          const Gap(10),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          const Gap(10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                item.status == WorkStatus.needsInfo
                    ? Icons.chat_bubble_outline
                    : Icons.code,
                size: 15,
                color: item.status == WorkStatus.needsInfo
                    ? colors.warning
                    : colors.primary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  item.latestNote ?? l10n(context).customerProgressHint,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.secondary,
                    height: 1.65,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RequestFormPage extends StatefulWidget {
  const RequestFormPage({super.key, required this.app});
  final AppController app;

  @override
  State<RequestFormPage> createState() => _RequestFormPageState();
}

class _RequestFormPageState extends State<RequestFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late String _timing;
  late String _budget;
  late List<String> _attachments;
  bool _confirming = false;

  static const _timings = ['1か月以内を希望', '2〜3か月以内を希望', '時期は相談したい'];
  static const _budgets = [
    '相談して決めたい',
    '10万円未満',
    '10万〜30万円',
    '30万〜50万円',
    '50万円以上',
  ];

  @override
  void initState() {
    super.initState();
    final draft = widget.app.repository.draft;
    _description = TextEditingController(
      text:
          draft?.description ??
          '社内の資料を検索できる AI FAQ をつくりたいです。社員が質問すると、手順書をもとに回答する仕組みを考えています。',
    );
    _timing = draft?.timing ?? _timings.first;
    _budget = draft?.budget ?? _budgets.first;
    _attachments = List.of(draft?.attachmentNames ?? []);
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  RequestDraft get _draft => RequestDraft(
    description: _description.text.trim(),
    timing: _timing,
    budget: _budget,
    attachmentNames: _attachments,
  );

  Future<void> _save() async {
    await performAction(
      context,
      widget.app,
      () => widget.app.repository.saveDraft(_draft),
      success: l10n(context).customerDraftSaved,
    );
  }

  Future<void> _submit() async {
    WorkItem? submitted;
    final succeeded = await performAction(context, widget.app, () async {
      submitted = await widget.app.repository.submitRequest(_draft);
    });
    if (!mounted || !succeeded || submitted == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ReviewPage(app: widget.app, id: submitted!.id),
      ),
    );
  }

  Future<void> _chooseAttachment() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(l10n(context).customerAddReference),
              const Gap(8),
              InfoNote(l10n(context).customerAttachmentNote),
              const Gap(12),
              for (final name in ['会議メモ.pdf', '仕様メモ.png'])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    name.endsWith('pdf')
                        ? Icons.description_outlined
                        : Icons.image_outlined,
                  ),
                  title: Text(name),
                  trailing: _attachments.contains(name)
                      ? const Icon(Icons.check)
                      : const Icon(Icons.add),
                  enabled: !_attachments.contains(name),
                  onTap: () => Navigator.pop(context, name),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && name != null) setState(() => _attachments.add(name));
  }

  Future<void> _assist() async {
    final original = _description.text.trim();
    final suggestion = l10n(context).customerAssistedDescription(original);
    final adopted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n(context).customerAssistTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoNote(l10n(context).customerAssistNote),
              const Gap(16),
              Text(suggestion, style: const TextStyle(height: 1.7)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n(context).customerKeepOriginal),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n(context).customerAdoptSuggestion),
          ),
        ],
      ),
    );
    if (adopted == true && mounted) {
      setState(() => _description.text = suggestion);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final colors = AppColors.of(context);
      return PopScope(
        canPop: !_confirming,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _confirming && !widget.app.busy) {
            setState(() => _confirming = false);
          }
        },
        child: OpcPage(
          title: _confirming
              ? l10n(context).customerConfirmTitle
              : l10n(context).customerFormTitle,
          subtitle: _confirming
              ? l10n(context).customerConfirmSubtitle
              : l10n(context).customerFormSubtitle,
          bottom: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryButton(
                label: widget.app.busy
                    ? l10n(context).customerProcessing
                    : (_confirming
                          ? l10n(context).customerSubmitRequest
                          : l10n(context).customerProceedConfirmation),
                icon: _confirming ? Icons.send_outlined : Icons.arrow_forward,
                onPressed: widget.app.busy
                    ? null
                    : () {
                        if (_confirming) {
                          _submit();
                        } else if (_formKey.currentState!.validate()) {
                          FocusScope.of(context).unfocus();
                          setState(() => _confirming = true);
                        }
                      },
              ),
              TextButton(
                onPressed: widget.app.busy
                    ? null
                    : () {
                        if (_confirming) {
                          setState(() => _confirming = false);
                        } else {
                          _save();
                        }
                      },
                child: Text(
                  _confirming
                      ? l10n(context).customerEditRequest
                      : l10n(context).customerSaveDraft,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!_confirming)
                    StatusPill(l10n(context).customerFormStep)
                  else
                    Text(
                      l10n(context).customerFormStep,
                      style: TextStyle(fontSize: 11, color: colors.secondary),
                    ),
                  Icon(Icons.chevron_right, size: 16, color: colors.secondary),
                  if (_confirming)
                    StatusPill(l10n(context).customerConfirmStep)
                  else
                    Text(
                      l10n(context).customerConfirmStep,
                      style: TextStyle(fontSize: 11, color: colors.secondary),
                    ),
                ],
              ),
              const Gap(18),
              if (_confirming) ...[
                OpcCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StatusPill(l10n(context).customerServiceCategory),
                      const Gap(16),
                      SectionLabel(l10n(context).customerGoalLabel),
                      const Gap(8),
                      Text(
                        _description.text.trim(),
                        style: const TextStyle(fontSize: 14, height: 1.75),
                      ),
                      const Gap(20),
                      _SummaryField(
                        label: l10n(context).customerTimingLabel,
                        value: _timingLabel(context, _timing),
                      ),
                      const Gap(16),
                      _SummaryField(
                        label: l10n(context).customerBudgetLabel,
                        value: _budgetLabel(context, _budget),
                      ),
                      const Gap(16),
                      _SummaryField(
                        label: l10n(context).customerReferenceLabel,
                        value: _attachments.isEmpty
                            ? l10n(context).customerNoAttachments
                            : _attachments.join('\n'),
                      ),
                    ],
                  ),
                ),
                const Gap(18),
                InfoNote(l10n(context).customerConfirmNotice),
              ] else ...[
                Text(
                  l10n(context).customerFormIntro,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.secondary,
                    height: 1.8,
                  ),
                ),
                const Gap(18),
                LocalizedForm(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n(context).customerGoalQuestion,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          StatusPill(
                            l10n(context).customerRequired,
                            warning: true,
                          ),
                        ],
                      ),
                      const Gap(9),
                      TextFormField(
                        controller: _description,
                        enabled: !widget.app.busy,
                        minLines: 3,
                        maxLines: 9,
                        maxLength: 4000,
                        style: const TextStyle(fontSize: 14, height: 1.7),
                        decoration: InputDecoration(
                          hintText: l10n(context).customerGoalHint,
                          counterText: '',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 10
                            ? l10n(context).customerGoalValidation
                            : null,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: widget.app.busy ? null : _assist,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                          ),
                          icon: const Icon(Icons.auto_fix_high, size: 17),
                          label: Text(
                            l10n(context).customerAssistAction,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const Gap(4),
                      _ChoiceField(
                        label: l10n(context).customerTimingLabel,
                        value: _timing,
                        options: _timings,
                        displayLabel: (value) => _timingLabel(context, value),
                        icon: Icons.calendar_month_outlined,
                        onChanged: widget.app.busy
                            ? null
                            : (value) => setState(() => _timing = value),
                      ),
                      const Gap(16),
                      _ChoiceField(
                        label: l10n(context).customerBudgetLabel,
                        value: _budget,
                        options: _budgets,
                        displayLabel: (value) => _budgetLabel(context, value),
                        onChanged: widget.app.busy
                            ? null
                            : (value) => setState(() => _budget = value),
                      ),
                      const Gap(16),
                      Text(
                        l10n(context).customerOptionalReference,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Gap(8),
                      PrimaryButton(
                        label: l10n(context).customerAddFiles,
                        icon: Icons.attach_file,
                        secondary: true,
                        onPressed: widget.app.busy ? null : _chooseAttachment,
                      ),
                      for (final name in _attachments)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.insert_drive_file_outlined,
                            color: colors.primary,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            l10n(context).customerSampleReference,
                            style: TextStyle(fontSize: 10),
                          ),
                          trailing: IconButton(
                            tooltip: l10n(
                              context,
                            ).customerRemoveAttachment(name),
                            onPressed: widget.app.busy
                                ? null
                                : () =>
                                      setState(() => _attachments.remove(name)),
                            icon: const Icon(Icons.close, size: 20),
                          ),
                        ),
                      const Gap(16),
                      InfoNote(l10n(context).customerSubmitNotice),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _ChoiceField extends StatelessWidget {
  const _ChoiceField({
    required this.label,
    required this.value,
    required this.options,
    required this.displayLabel,
    required this.onChanged,
    this.icon = Icons.keyboard_arrow_down,
  });
  final String label;
  final String value;
  final List<String> options;
  final String Function(String value) displayLabel;
  final ValueChanged<String>? onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const Gap(8),
      DropdownButtonFormField<String>(
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        icon: Icon(icon, size: 20),
        style: TextStyle(fontSize: 14, color: AppColors.of(context).text),
        items: {...options, value}
            .map(
              (option) => DropdownMenuItem(
                value: option,
                child: Text(displayLabel(option)),
              ),
            )
            .toList(),
        onChanged: onChanged == null
            ? null
            : (value) {
                if (value != null) onChanged!(value);
              },
      ),
    ],
  );
}

class _SummaryField extends StatelessWidget {
  const _SummaryField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(color: AppColors.of(context).secondary, fontSize: 11),
      ),
      const Gap(6),
      Text(value, style: const TextStyle(fontSize: 14, height: 1.7)),
    ],
  );
}

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key, required this.app, required this.id});
  final AppController app;
  final String id;

  Future<void> _reply(BuildContext context, WorkItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReplySheet(app: app, item: item),
    );
  }

  @override
  Widget build(BuildContext context) => RepositoryPageGuard(
    app: app,
    title: l10n(context).customerReviewTitle,
    builder: (context) {
      final item = app.repository.detail(id);
      final colors = AppColors.of(context);
      final received = item.createdAt.toUtc().add(const Duration(hours: 9));
      final receivedLabel = l10n(context).customerReceivedDate(
        received.year,
        received.month,
        received.day,
        "${received.hour.toString().padLeft(2, '0')}:${received.minute.toString().padLeft(2, '0')}",
      );
      final needsInfo = item.status == WorkStatus.needsInfo;
      return OpcPage(
        title: l10n(context).customerReviewTitle,
        subtitle: l10n(context).customerReviewSubtitle,
        bottom: needsInfo
            ? PrimaryButton(
                label: l10n(context).customerReplyAction,
                icon: Icons.reply,
                onPressed: app.busy ? null : () => _reply(context, item),
              )
            : PrimaryButton(
                label: l10n(context).customerBackToRequests,
                icon: Icons.arrow_back,
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OpcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.id,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.secondary,
                          ),
                        ),
                      ),
                      Flexible(
                        child: StatusPill(
                          item.isPublished
                              ? l10n(context).customerPublished
                              : l10n(context).customerUnderReview,
                          warning: !item.isPublished,
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                  const Gap(9),
                  Text(
                    l10n(context).customerReceivedAt(receivedLabel),
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.secondary,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(14),
            OpcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n(context).customerReviewSteps,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const Gap(16),
                  _ReviewStep(
                    number: 1,
                    title: l10n(context).customerReceivedStep,
                    description: l10n(context).customerReceivedStepDetail,
                    complete: true,
                  ),
                  const Gap(14),
                  _ReviewStep(
                    number: 2,
                    title: l10n(context).customerComplianceStep,
                    description: item.complianceApproved
                        ? l10n(context).customerComplianceComplete
                        : l10n(context).customerCompliancePending,
                    complete: item.complianceApproved,
                    active: !item.complianceApproved,
                  ),
                  const Gap(14),
                  _ReviewStep(
                    number: 3,
                    title: l10n(context).customerRequirementsStep,
                    description: item.technicalApproved
                        ? l10n(context).customerRequirementsComplete
                        : needsInfo
                        ? l10n(context).customerRequirementsNeedsInfo
                        : l10n(context).customerRequirementsPending,
                    complete: item.technicalApproved,
                    active: item.complianceApproved && !item.technicalApproved,
                  ),
                  const Gap(14),
                  _ReviewStep(
                    number: 4,
                    title: l10n(context).customerPublicationStep,
                    description: item.isPublished
                        ? l10n(context).customerPublicationComplete
                        : l10n(context).customerPublicationPending,
                    complete: item.isPublished,
                  ),
                ],
              ),
            ),
            if (item.question != null) ...[
              const Gap(14),
              OpcCard(
                color: colors.warningSoft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          color: colors.warning,
                          size: 18,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            l10n(context).customerOperatorQuestion,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    Text(
                      item.question!,
                      style: const TextStyle(fontSize: 13, height: 1.75),
                    ),
                    const Gap(10),
                    Text(
                      needsInfo
                          ? l10n(context).customerOperatorAwaitingReply
                          : l10n(context).customerOperatorReplyReceived,
                      style: TextStyle(fontSize: 10, color: colors.secondary),
                    ),
                  ],
                ),
              ),
            ],
            if (item.messages.isNotEmpty) ...[
              const Gap(14),
              SectionLabel(l10n(context).customerSupplementConversation),
              const Gap(10),
              for (final message in item.messages) ...[
                OpcCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        message.author,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                      const Gap(7),
                      Text(
                        message.text,
                        style: const TextStyle(fontSize: 13, height: 1.7),
                      ),
                    ],
                  ),
                ),
                const Gap(10),
              ],
            ],
            const Gap(16),
            InfoNote(
              item.isPublished
                  ? l10n(context).customerPublicationNotice
                  : l10n(context).customerUnpublishedNotice,
              icon: Icons.lock_outline,
            ),
          ],
        ),
      );
    },
  );
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.number,
    required this.title,
    required this.description,
    this.complete = false,
    this.active = false,
  });
  final int number;
  final String title;
  final String description;
  final bool complete;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: complete
                ? colors.primary
                : active
                ? colors.soft
                : colors.raised,
          ),
          alignment: Alignment.center,
          child: complete
              ? Icon(Icons.check, size: 18, color: colors.onPrimary)
              : Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? colors.primary : colors.secondary,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: complete || active ? colors.text : colors.secondary,
                ),
              ),
              const Gap(3),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: colors.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReplySheet extends StatefulWidget {
  const _ReplySheet({required this.app, required this.item});
  final AppController app;
  final WorkItem item;

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final success = await performAction(
      context,
      widget.app,
      () => widget.app.repository.answerQuestion(
        widget.item.id,
        _controller.text.trim(),
      ),
      success: l10n(context).customerReplySuccess,
    );
    if (mounted && success) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: LocalizedForm(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SectionLabel(l10n(context).customerReplyAction),
              const Gap(12),
              Text(
                widget.item.question ?? '',
                style: const TextStyle(fontSize: 13, height: 1.7),
              ),
              const Gap(16),
              TextFormField(
                controller: _controller,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                autofocus: true,
                enabled: !widget.app.busy,
                decoration: InputDecoration(
                  labelText: l10n(context).customerReplyLabel,
                  hintText: l10n(context).customerReplyHint,
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? l10n(context).customerReplyValidation
                    : null,
              ),
              const Gap(12),
              InfoNote(l10n(context).customerReplyNotice),
              const Gap(20),
              PrimaryButton(
                label: widget.app.busy
                    ? l10n(context).customerSending
                    : l10n(context).customerSendReply,
                icon: Icons.send_outlined,
                onPressed: widget.app.busy ? null : _send,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// Stable stored values remain unchanged when the interface language changes.
String _timingLabel(BuildContext context, String value) => switch (value) {
  '1か月以内を希望' => l10n(context).customerTimingMonth,
  '2〜3か月以内を希望' => l10n(context).customerTimingQuarter,
  '時期は相談したい' => l10n(context).customerTimingDiscuss,
  _ => value,
};

String _budgetLabel(BuildContext context, String value) => switch (value) {
  '相談して決めたい' => l10n(context).customerBudgetDiscuss,
  '10万円未満' => l10n(context).customerBudgetUnder100k,
  '10万〜30万円' => l10n(context).customerBudget100to300k,
  '30万〜50万円' => l10n(context).customerBudget300to500k,
  '50万円以上' => l10n(context).customerBudgetOver500k,
  _ => value,
};
