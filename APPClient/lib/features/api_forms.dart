import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../l10n/strings.dart';
import 'api_workspace.dart';
import 'api_file_card.dart';
import 'api_classifications.dart';

/// The injectable picker keeps platform file selection separate from upload.
Future<RemoteFile?> pickAndUpload(
  BuildContext context,
  AppController app,
) async {
  RemoteFile? uploaded;
  await apiAction(context, app, () async {
    final choice = await FilePicker.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    if (choice == null || choice.files.isEmpty) return;
    final picked = choice.files.single;
    if (picked.size <= 0 || picked.size > 20 * 1024 * 1024) {
      throw const RepositoryException('file_too_large', 'Invalid file size');
    }
    final bytes =
        picked.bytes ??
        (picked.path == null ? null : await File(picked.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const RepositoryException('file_too_large', 'Invalid file size');
    }
    uploaded = await remote(app).uploadFile(picked.name, bytes);
  });
  return uploaded;
}

class ApiFileList extends StatelessWidget {
  const ApiFileList({
    super.key,
    required this.app,
    required this.files,
    this.onRemove,
  });
  final AppController app;
  final List<RemoteFile> files;
  final ValueChanged<RemoteFile>? onRemove;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final file in files)
        ApiFileCard(
          key: ValueKey('api-file-${file.id}'),
          name: file.name,
          mediaType: file.mediaType,
          sizeBytes: file.sizeBytes,
          warning: !file.isReady,
          status: file.isReady
              ? l10n(context).apiFileReady
              : file.scanStatus == 'pending'
              ? l10n(context).apiFilePending
              : l10n(context).apiFileBlocked,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ApiFilePage(app: app, fileId: file.id),
            ),
          ),
          trailing: onRemove == null
              ? null
              : IconButton(
                  tooltip: l10n(context).apiRemoveFile,
                  onPressed: app.busy ? null : () => onRemove!(file),
                  icon: const Icon(Icons.close),
                ),
        ),
    ],
  );
}

class ApiRequestPage extends StatefulWidget {
  const ApiRequestPage({super.key, required this.app});
  final AppController app;
  @override
  State<ApiRequestPage> createState() => _ApiRequestPageState();
}

class _ApiRequestPageState extends State<ApiRequestPage> {
  final _form = GlobalKey<FormState>();
  late String? _platformCode = widget.app.repository.draft?.platformCode;
  late String? _developmentTypeCode =
      widget.app.repository.draft?.developmentTypeCode;
  late final _description = TextEditingController(
    text: widget.app.repository.draft?.description ?? '',
  );
  late final _timing = TextEditingController(
    text: widget.app.repository.draft?.timing ?? '',
  );
  late final _timingDisplay = TextEditingController(text: _timing.text);
  bool _datePickerOpen = false;
  late final _budget = TextEditingController(
    text: widget.app.repository.draft?.budget ?? '',
  );
  late final List<RemoteFile> _files = [...?widget.app.repository.draft?.files];

  DateTime? get _completionDate {
    final value = _timing.text;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final parsed = DateTime.tryParse(value);
    return parsed != null && _dateValue(parsed) == value ? parsed : null;
  }

  String _dateValue(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  void _syncTimingDisplay() {
    final date = _completionDate;
    final display = date == null
        ? _timing.text
        : MaterialLocalizations.of(context).formatShortDate(date);
    if (_timingDisplay.text != display) _timingDisplay.text = display;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimingDisplay();
  }

  Future<void> _pickCompletionDate() async {
    if (_datePickerOpen || widget.app.busy) return;
    _datePickerOpen = true;
    FocusScope.of(context).unfocus();
    final jstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    final today = DateTime(jstNow.year, jstNow.month, jstNow.day);
    final initial = _completionDate ?? today;
    try {
      final date = await showDatePicker(
        context: context,
        helpText: l10n(context).apiTiming,
        initialDate: initial,
        currentDate: today,
        firstDate: DateTime(
          initial.year < today.year - 100 ? initial.year : today.year - 100,
        ),
        lastDate: DateTime(
          initial.year > today.year + 100 ? initial.year : today.year + 100,
          12,
          31,
        ),
        initialEntryMode: DatePickerEntryMode.calendarOnly,
      );
      if (date != null && mounted) {
        setState(() {
          _timing.text = _dateValue(date);
          _syncTimingDisplay();
        });
      }
    } finally {
      _datePickerOpen = false;
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _timing.dispose();
    _timingDisplay.dispose();
    _budget.dispose();
    super.dispose();
  }

  RequestDraft get _draft => RequestDraft(
    platformCode: _platformCode,
    developmentTypeCode: _developmentTypeCode,
    description: _description.text.trim(),
    timing: _timing.text.trim(),
    budget: _budget.text.trim(),
    files: _files,
    attachmentNames: _files.map((f) => f.name).toList(),
  );

  Future<void> _save(bool submit) async {
    if (submit && !_form.currentState!.validate()) return;
    final s = l10n(context);
    final ok = await apiAction(context, widget.app, () async {
      if (submit) {
        await widget.app.repository.submitRequest(_draft);
      } else {
        await widget.app.repository.saveDraft(_draft);
      }
    }, success: submit ? s.apiSubmitted : s.apiDraftSaved);
    if (ok && mounted && submit) Navigator.pop(context);
  }

  Future<void> _pick() async {
    final result = await pickAndUpload(context, widget.app);
    if (result != null && mounted) setState(() => _files.add(result));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final s = l10n(context);
      return OpcPage(
        title: s.apiRequestTitle,
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(
              key: const Key('api-submit-request'),
              label: s.apiSubmitRequest,
              icon: Icons.send_outlined,
              onPressed: widget.app.busy ? null : () => _save(true),
            ),
            const Gap(8),
            PrimaryButton(
              key: const Key('api-save-draft'),
              label: s.apiSaveDraft,
              secondary: true,
              onPressed: widget.app.busy ? null : () => _save(false),
            ),
          ],
        ),
        child: LocalizedForm(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoNote(s.apiReviewNotice),
              const Gap(20),
              ApiClassificationFields(
                app: widget.app,
                platformCode: _platformCode,
                developmentTypeCode: _developmentTypeCode,
                onPlatformChanged: (value) =>
                    setState(() => _platformCode = value),
                onTypeChanged: (value) =>
                    setState(() => _developmentTypeCode = value),
              ),
              const Gap(20),
              OpcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('api-request-description'),
                      controller: _description,
                      minLines: 6,
                      maxLines: 12,
                      maxLength: 4000,
                      enabled: !widget.app.busy,
                      decoration: InputDecoration(
                        labelText: s.apiDescription,
                        alignLabelWithHint: true,
                      ),
                      validator: (value) => (value ?? '').trim().length < 10
                          ? s.errorDescription
                          : null,
                    ),
                    const Gap(16),
                    TextFormField(
                      key: const Key('api-request-timing'),
                      controller: _timingDisplay,
                      readOnly: true,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      enabled: !widget.app.busy,
                      onTap: _pickCompletionDate,
                      validator: (_) => _completionDate == null
                          ? s.apiPickCompletionDate
                          : null,
                      decoration: InputDecoration(
                        labelText: s.apiTiming,
                        hintText: s.apiPickCompletionDate,
                        suffixIcon: IconButton(
                          key: const Key('api-pick-completion-date'),
                          tooltip: s.apiPickCompletionDate,
                          onPressed: widget.app.busy
                              ? null
                              : _pickCompletionDate,
                          icon: const Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                    ),
                    const Gap(8),
                    TextFormField(
                      key: const Key('api-request-budget'),
                      controller: _budget,
                      maxLength: 500,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? s.apiRequired : null,
                      decoration: InputDecoration(labelText: s.apiBudget),
                    ),
                  ],
                ),
              ),
              const Gap(20),
              SectionLabel(s.apiFiles),
              const Gap(8),
              ApiFileList(
                app: widget.app,
                files: _files,
                onRemove: (file) => setState(() => _files.remove(file)),
              ),
              PrimaryButton(
                key: const Key('api-file-pick'),
                label: s.apiPickFile,
                icon: Icons.attach_file,
                secondary: true,
                onPressed: widget.app.busy ? null : _pick,
              ),
              const Gap(12),
              InfoNote(s.apiUploaded),
            ],
          ),
        ),
      );
    },
  );
}

class ApiDeliveryPage extends StatefulWidget {
  const ApiDeliveryPage({super.key, required this.app, required this.id});
  final AppController app;
  final String id;
  @override
  State<ApiDeliveryPage> createState() => _ApiDeliveryPageState();
}

class _ApiDeliveryPageState extends State<ApiDeliveryPage> {
  final _form = GlobalKey<FormState>();
  final _repoUrl = TextEditingController();
  final _commit = TextEditingController();
  final _archiveRef = TextEditingController();
  final _guide = TextEditingController();
  final _tests = TextEditingController();
  final _note = TextEditingController();
  final List<RemoteFile> _files = [];
  String? _sourceId;
  @override
  void dispose() {
    for (final controller in [
      _repoUrl,
      _commit,
      _archiveRef,
      _guide,
      _tests,
      _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshFiles() async {
    await apiAction(context, widget.app, () async {
      final fresh = await Future.wait(
        _files.map((f) => remote(widget.app).fileMetadata(f.id)),
      );
      if (mounted) {
        setState(() {
          _files.clear();
          _files.addAll(fresh);
        });
      }
    });
  }

  Future<void> _pick() async {
    final result = await pickAndUpload(context, widget.app);
    if (result != null && mounted) setState(() => _files.add(result));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await apiAction(context, widget.app, () async {
      final item = widget.app.repository.detail(widget.id);
      final source = _files.where((f) => f.id == _sourceId).firstOrNull;
      await widget.app.repository.submitDelivery(
        widget.id,
        Delivery(
          version:
              item.deliveries.fold<int>(
                0,
                (n, d) => d.version > n ? d.version : n,
              ) +
              1,
          sourceName: source?.name ?? _repoUrl.text.trim(),
          sourceRef: _sourceId == null ? _commit.text.trim() : '',
          sourceFileId: _sourceId,
          sourceArchiveRef: _sourceId == null ? _archiveRef.text.trim() : null,
          repositoryUrl: _sourceId == null ? _repoUrl.text.trim() : null,
          guideName: _guide.text.trim(),
          testName: _tests.text.trim(),
          note: _note.text.trim(),
          files: _files.where((f) => f.id != _sourceId).toList(),
        ),
      );
    }, success: l10n(context).apiDeliverySubmitted);
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final s = l10n(context);
      String? required(String? value) =>
          (value ?? '').trim().isEmpty ? s.apiRequired : null;
      return OpcPage(
        title: s.apiDelivery,
        actions: [ApiRefreshButton(app: widget.app, onRefresh: _refreshFiles)],
        bottom: PrimaryButton(
          key: const Key('api-submit-delivery'),
          label: s.apiSubmitDelivery,
          icon: Icons.cloud_upload_outlined,
          onPressed: widget.app.busy ? null : _submit,
        ),
        child: LocalizedForm(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoNote(s.apiSourceHelp),
              const Gap(20),
              OpcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('api-source-repository'),
                      controller: _repoUrl,
                      enabled: _sourceId == null,
                      decoration: InputDecoration(labelText: s.apiSourceRepo),
                      validator: (value) {
                        if (_sourceId != null) return null;
                        final uri = Uri.tryParse(value ?? '');
                        return uri != null &&
                                uri.scheme == 'https' &&
                                uri.host.isNotEmpty &&
                                uri.userInfo.isEmpty &&
                                !uri.hasFragment
                            ? null
                            : s.errorSource;
                      },
                    ),
                    const Gap(16),
                    TextFormField(
                      key: const Key('api-source-commit'),
                      controller: _commit,
                      enabled: _sourceId == null,
                      decoration: InputDecoration(labelText: s.apiSourceCommit),
                      validator: (value) =>
                          _sourceId != null ||
                              RegExp(
                                r'^[a-f0-9]{40}([a-f0-9]{24})?$',
                              ).hasMatch(value ?? '')
                          ? null
                          : s.errorSource,
                    ),
                    if (_files.isNotEmpty) ...[
                      const Gap(16),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_sourceId),
                        initialValue: _sourceId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: s.apiSourceFile),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(s.apiSourceRepo),
                          ),
                          for (final f in _files)
                            DropdownMenuItem(
                              value: f.id,
                              child: Text(
                                f.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _sourceId = value),
                      ),
                    ],
                    if (_sourceId == null) ...[
                      const Gap(16),
                      TextFormField(
                        key: const Key('api-source-archive-ref'),
                        controller: _archiveRef,
                        decoration: InputDecoration(
                          labelText: s.apiSourceArchiveRef,
                        ),
                        validator: required,
                      ),
                    ],
                    const Gap(20),
                    TextFormField(
                      key: const Key('api-delivery-guide'),
                      controller: _guide,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 12000,
                      decoration: InputDecoration(
                        labelText: s.apiGuide,
                        alignLabelWithHint: true,
                      ),
                      validator: required,
                    ),
                    const Gap(12),
                    TextFormField(
                      key: const Key('api-delivery-tests'),
                      controller: _tests,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 12000,
                      decoration: InputDecoration(
                        labelText: s.apiTestEvidence,
                        alignLabelWithHint: true,
                      ),
                      validator: required,
                    ),
                    const Gap(12),
                    TextFormField(
                      key: const Key('api-delivery-note'),
                      controller: _note,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 12000,
                      decoration: InputDecoration(
                        labelText: s.apiDeliveryNote,
                        alignLabelWithHint: true,
                      ),
                      validator: required,
                    ),
                  ],
                ),
              ),
              const Gap(20),
              SectionLabel(s.apiFiles),
              ApiFileList(
                app: widget.app,
                files: _files,
                onRemove: (f) => setState(() {
                  _files.remove(f);
                  if (_sourceId == f.id) _sourceId = null;
                }),
              ),
              PrimaryButton(
                key: const Key('api-file-pick'),
                label: s.apiPickFile,
                secondary: true,
                onPressed: widget.app.busy ? null : _pick,
              ),
              const Gap(12),
              InfoNote(s.apiSafetyNotice),
            ],
          ),
        ),
      );
    },
  );
}
