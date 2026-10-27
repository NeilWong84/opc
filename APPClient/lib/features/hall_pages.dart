import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../core/app_controller.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'reference_widgets.dart';

class HallPage extends StatefulWidget {
  const HallPage({
    super.key,
    required this.app,
    required this.onOpen,
    required this.onNotifications,
    this.navigation,
  });
  final AppController app;
  final ValueChanged<String> onOpen;
  final VoidCallback onNotifications;
  final Widget? navigation;
  @override
  State<HallPage> createState() => _HallPageState();
}

class _HallPageState extends State<HallPage> {
  String _query = '';
  String _category = 'すべて';
  @override
  Widget build(BuildContext context) => RepositoryPageGuard(
    app: widget.app,
    title: l10n(context).hallTitle,
    builder: _build,
  );

  Widget _build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final items = widget.app.repository.hall(
      query: _query,
      category: _category,
    );
    return OpcPage(
      title: l10n(context).hallTitle,
      subtitle: l10n(context).hallSubtitle,
      back: false,
      navigation: widget.navigation,
      actions: [
        IconButton(
          tooltip: l10n(context).hallNotifications,
          onPressed: widget.onNotifications,
          icon: const Icon(Icons.notifications_none, size: 22),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpcCard(
            color: c.soft,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.badge_outlined, size: 17, color: c.primary),
                const SizedBox(width: 8),
                Text(
                  l10n(context).hallInternal,
                  style: t.bodySmall?.copyWith(
                    color: c.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n(context).hallPublishedWork,
                    style: t.labelSmall,
                  ),
                ),
              ],
            ),
          ),
          const Gap(12),
          TextField(
            key: const Key('hall-search'),
            decoration: InputDecoration(
              hintText: l10n(context).hallSearch,
              prefixIcon: const Icon(Icons.search, size: 21),
              suffixIcon: Icon(Icons.tune, size: 20, color: c.primary),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const Gap(8),
          Wrap(
            spacing: 6,
            children: [
              for (final category in ['すべて', 'Web アプリ', '業務自動化'])
                ChoiceChip(
                  label: Text(
                    categoryLabel(context, category),
                    style: TextStyle(
                      fontSize: 11,
                      color: category == _category ? c.primary : c.secondary,
                    ),
                  ),
                  selected: category == _category,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
          const Gap(10),
          SectionLabel(
            l10n(context).hallCount(items.length),
            trailing: l10n(context).hallSort,
          ),
          const Gap(12),
          if (items.isEmpty)
            OpcCard(
              child: Column(
                children: [
                  Icon(Icons.search_off, size: 32, color: c.secondary),
                  const Gap(12),
                  Text(l10n(context).hallEmpty),
                  const Gap(4),
                  Text(l10n(context).hallEmptyHelp, style: t.bodySmall),
                ],
              ),
            ),
          for (final item in items) ...[
            OpcCard(
              onTap: () => widget.onOpen(item.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(item.id, style: t.labelSmall)),
                      StatusPill(l10n(context).hallPublished),
                    ],
                  ),
                  const Gap(10),
                  Text(item.title, style: t.titleMedium),
                  const Gap(8),
                  Text(item.description, style: t.bodySmall),
                  HallReferenceSummary(app: widget.app, item: item),
                  const Gap(10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusPill(categoryLabel(context, item.category)),
                      StatusPill(l10n(context).hallStructured),
                    ],
                  ),
                  const Gap(10),
                  Divider(color: c.border, height: 1),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n(context).hallEstimate(item.duration),
                          style: t.bodySmall,
                        ),
                      ),
                      Text(
                        l10n(context).hallView,
                        style: t.bodySmall?.copyWith(
                          color: c.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 16, color: c.primary),
                    ],
                  ),
                ],
              ),
            ),
            const Gap(12),
          ],
        ],
      ),
    );
  }
}

class TaskDetailPage extends StatelessWidget {
  const TaskDetailPage({super.key, required this.app, required this.id});
  final AppController app;
  final String id;

  void _consult(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ConsultSheet(app: app, id: id),
  );

  @override
  Widget build(BuildContext context) => RepositoryPageGuard(
    app: app,
    title: l10n(context).hallDetail,
    builder: _build,
  );

  Widget _build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final item = app.repository.detail(id);
    // Only the two design fixtures have these already-written scope examples.
    // A newly submitted request must not inherit another project's promises.
    final inquiryFixture = item.id == 'DEV-1036';
    final quoteFixture = item.id == 'DEV-1039';
    final scopeItems = inquiryFixture
        ? const ['問い合わせの登録・一覧・検索', '担当者と対応状況の更新', 'チーム用ログインと閲覧権限']
        : quoteFixture
        ? const ['入力フォームと見積計算', 'PDF の生成・出力', '過去の見積もりの検索']
        : const <String>[];
    return OpcPage(
      title: l10n(context).hallDetail,
      subtitle: l10n(context).hallDevelopment,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: l10n(context).hallConsult,
            icon: Icons.chat_bubble_outline,
            onPressed: app.busy ? null : () => _consult(context),
          ),
          const Gap(8),
          Text(
            l10n(context).hallNotAssigned,
            style: t.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.id, style: t.labelSmall)),
              StatusPill(l10n(context).hallPublished),
            ],
          ),
          const Gap(12),
          Text(
            inquiryFixture ? 'お問い合わせ\n管理ツールの開発' : item.title,
            style: t.headlineSmall,
          ),
          const Gap(10),
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(categoryLabel(context, item.category)),
              Text(l10n(context).hallVersion(item.version), style: t.bodySmall),
            ],
          ),
          TaskReferenceSection(app: app, item: item),
          const Gap(16),
          OpcCard(
            color: c.soft,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n(context).hallDuration, style: t.bodySmall),
                      const Gap(4),
                      Text(item.duration, style: t.titleMedium),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n(context).hallMethod, style: t.bodySmall),
                      const Gap(4),
                      Text(l10n(context).hallOnline, style: t.titleMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Gap(16),
          OpcCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n(context).hallScope, style: t.titleMedium),
                const Gap(10),
                Text(item.description, style: t.bodySmall),
                const Gap(12),
                if (scopeItems.isEmpty) InfoNote(l10n(context).hallScopeHelp),
                for (final label in scopeItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check, color: c.primary, size: 17),
                        const SizedBox(width: 8),
                        Expanded(child: Text(label)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Gap(16),
          OpcCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: c.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n(context).hallDeliverables,
                        style: t.titleMedium,
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                Text(l10n(context).hallFiles, style: t.titleSmall),
                const Gap(10),
                Text(
                  inquiryFixture
                      ? '登録・検索・状態更新ができることを確認。\n対象外：外部 CRM 連携、既存データの移行。'
                      : quoteFixture
                      ? '見積計算と PDF 出力ができることを確認。\n対象外：外部会計サービスへの連携。'
                      : l10n(context).hallIndividualScope,
                  style: t.bodySmall,
                ),
              ],
            ),
          ),
          const Gap(16),
          InfoNote(l10n(context).hallPrivateHelp),
        ],
      ),
    );
  }
}

class _ConsultSheet extends StatefulWidget {
  const _ConsultSheet({required this.app, required this.id});
  final AppController app;
  final String id;
  @override
  State<_ConsultSheet> createState() => _ConsultSheetState();
}

class _ConsultSheetState extends State<_ConsultSheet> {
  final _text = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
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
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: LocalizedForm(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(l10n(context).hallConsult),
              const Gap(12),
              InfoNote(l10n(context).hallConsultHelp),
              const Gap(16),
              TextFormField(
                controller: _text,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: l10n(context).hallConsultHint,
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? l10n(context).hallConsultRequired
                    : null,
              ),
              const Gap(16),
              PrimaryButton(
                label: widget.app.busy
                    ? l10n(context).hallSending
                    : l10n(context).hallSend,
                icon: Icons.send_outlined,
                onPressed: widget.app.busy
                    ? null
                    : () async {
                        if (!_form.currentState!.validate()) return;
                        final ok = await performAction(
                          context,
                          widget.app,
                          () => widget.app.repository.consult(
                            widget.id,
                            _text.text.trim(),
                          ),
                          success: l10n(context).hallSent,
                        );
                        if (ok && context.mounted) Navigator.pop(context);
                      },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
