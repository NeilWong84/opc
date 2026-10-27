import 'package:flutter/material.dart';
import '../core/app_controller.dart';
import '../core/language_picker.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/mock_repository.dart';
import '../data/models.dart';
import '../l10n/strings.dart';
import 'customer_pages.dart';
import 'hall_pages.dart';
import 'project_pages.dart';
import 'reference_pages.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.app});
  final AppController app;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool get _provider =>
      widget.app.repository.session?.role == UserRole.provider;

  void _push(Widget Function() page) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (context) => AnimatedBuilder(
        animation: widget.app,
        builder: (context, _) => page(),
      ),
    ),
  );

  void _open(String id) {
    final WorkItem item;
    try {
      item = widget.app.repository.detail(id);
    } on RepositoryException catch (error) {
      _push(
        () => RepositoryUnavailablePage(
          app: widget.app,
          title: l10n(context).customerRequestDetail,
          message: repositoryError(context, error),
        ),
      );
      return;
    }
    if (_provider && item.status == WorkStatus.published) {
      _push(() => TaskDetailPage(app: widget.app, id: id));
    } else if (!_provider &&
        [
          WorkStatus.needsInfo,
          WorkStatus.reviewing,
          WorkStatus.published,
        ].contains(item.status)) {
      _push(() => ReviewPage(app: widget.app, id: id));
    } else if (!_provider &&
        [
          WorkStatus.awaitingAcceptance,
          WorkStatus.completed,
          WorkStatus.revision,
        ].contains(item.status)) {
      _push(() => AcceptancePage(app: widget.app, id: id));
    } else {
      _push(() => ProjectPage(app: widget.app, id: id));
    }
  }

  void _notifications() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => RepositoryPageGuard(
      app: widget.app,
      title: l10n(context).customerNotifications,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(l10n(context).customerNotifications),
              const Gap(16),
              if (widget.app.repository.myRequests().isEmpty)
                InfoNote(l10n(context).customerNoNotifications),
              for (final item in widget.app.repository.myRequests()) ...[
                OpcCard(
                  onTap: () {
                    Navigator.pop(context);
                    _open(item.id);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Gap(4),
                      Text(
                        item.latestNote ?? statusLabel(context, item.status),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Gap(10),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => RepositoryPageGuard(
    app: widget.app,
    title: l10n(context).customerWorkspace,
    builder: _build,
  );

  Widget _build(BuildContext context) {
    // Validate even the profile tab before it dereferences the session.
    final items = widget.app.repository.myRequests();
    final c = AppColors.of(context);
    final labels = [
      _provider ? l10n(context).customerTasks : l10n(context).customerHome,
      _provider
          ? l10n(context).customerProjects
          : l10n(context).customerRequests,
      l10n(context).customerMessages,
      l10n(context).customerProfile,
    ];
    final nav = Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Semantics(
                selected: i == _index,
                button: true,
                child: InkWell(
                  key: ValueKey('tab-$i'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _index = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 9,
                      horizontal: 2,
                    ),
                    decoration: BoxDecoration(
                      color: i == _index ? c.soft : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          [
                            Icons.grid_view_rounded,
                            Icons.folder_open,
                            Icons.chat_bubble_outline,
                            Icons.person_outline,
                          ][i],
                          size: 21,
                          color: i == _index ? c.primary : c.secondary,
                        ),
                        const Gap(4),
                        Text(
                          labels[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: i == _index
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: i == _index ? c.primary : c.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (_index == 0) {
      return _provider
          ? HallPage(
              app: widget.app,
              onOpen: _open,
              onNotifications: _notifications,
              navigation: nav,
            )
          : CustomerHomePage(
              app: widget.app,
              onCreate: () => _push(() => RequestFormPage(app: widget.app)),
              onOpen: _open,
              onNotifications: _notifications,
              navigation: nav,
            );
    }
    if (_index == 3) return _ProfilePage(app: widget.app, navigation: nav);
    return OpcPage(
      title: labels[_index],
      subtitle: _index == 2
          ? l10n(context).customerMessageListSubtitle
          : l10n(context).customerRequestListSubtitle,
      back: false,
      navigation: nav,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty)
            OpcCard(child: InfoNote(l10n(context).customerEmptyWorkspace)),
          for (final item in items) ...[
            OpcCard(
              onTap: () => _index == 2
                  ? _push(() => ConversationPage(app: widget.app, id: item.id))
                  : _open(item.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.id,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      StatusPill(
                        statusLabel(context, item.status),
                        warning: item.status == WorkStatus.needsInfo,
                      ),
                    ],
                  ),
                  const Gap(10),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Gap(6),
                  Text(
                    _index == 2 && item.messages.isNotEmpty
                        ? item.messages.last.text
                        : item.latestNote ?? l10n(context).customerViewDetails,
                    style: Theme.of(context).textTheme.bodySmall,
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

class ConversationPage extends StatefulWidget {
  const ConversationPage({super.key, required this.app, required this.id});
  final AppController app;
  final String id;
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepositoryPageGuard(
    app: widget.app,
    title: l10n(context).customerMessages,
    builder: _build,
  );

  Widget _build(BuildContext context) {
    final item = widget.app.repository.detail(widget.id);
    return OpcPage(
      title: l10n(context).customerMessages,
      subtitle: '${item.id} · ${item.title}',
      bottom: PrimaryButton(
        label: l10n(context).customerSendMessage,
        icon: Icons.send_outlined,
        onPressed: widget.app.busy
            ? null
            : () async {
                final ok = await performAction(
                  context,
                  widget.app,
                  () => widget.app.repository.sendMessage(
                    widget.id,
                    _text.text.trim(),
                  ),
                  success: l10n(context).customerMessageSent,
                );
                if (mounted && ok) _text.clear();
              },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoNote(l10n(context).customerConversationNote),
          const Gap(16),
          if (item.messages.isEmpty)
            OpcCard(child: Text(l10n(context).customerNoMessages)),
          for (final message in item.messages) ...[
            OpcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.author,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Gap(8),
                  Text(message.text),
                  const Gap(6),
                  Text(
                    _jst(message.sentAt),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const Gap(12),
          ],
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: l10n(context).customerMessageHint,
            ),
          ),
        ],
      ),
    );
  }

  String _jst(DateTime time) {
    final jst = time.toUtc().add(const Duration(hours: 9));
    return l10n(context).customerMessageDate(
      jst.month,
      jst.day,
      "${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}",
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.app, required this.navigation});
  final AppController app;
  final Widget navigation;
  @override
  Widget build(BuildContext context) {
    final user = app.repository.session!;
    return OpcPage(
      title: l10n(context).customerProfile,
      subtitle: l10n(context).customerProfileSubtitle,
      back: false,
      navigation: navigation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpcCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: Theme.of(context).textTheme.titleLarge),
                const Gap(4),
                Text(user.email),
                const Gap(12),
                StatusPill(
                  user.role == UserRole.provider
                      ? l10n(context).customerInternalAccount
                      : l10n(context).customerCustomerAccount,
                ),
                if (user.role == UserRole.provider) ...[
                  const Gap(8),
                  InfoNote(l10n(context).customerInternalAuthorization),
                ],
              ],
            ),
          ),
          const Gap(24),
          SectionLabel(l10n(context).customerAppearance),
          const Gap(12),
          Wrap(
            spacing: 8,
            children: [
              for (final theme in [
                (ThemeMode.system, l10n(context).customerThemeSystem),
                (ThemeMode.light, l10n(context).customerThemeLight),
                (ThemeMode.dark, l10n(context).customerThemeDark),
              ])
                ChoiceChip(
                  label: Text(theme.$2),
                  selected: app.themeMode == theme.$1,
                  onSelected: (_) => app.setTheme(theme.$1),
                ),
            ],
          ),
          const Gap(8),
          InfoNote(l10n(context).customerBusinessRegion),
          const Gap(24),
          SectionLabel(l10n(context).customerLanguage),
          const Gap(12),
          LanguagePicker(app: app),
          const Gap(8),
          InfoNote(l10n(context).customerLanguageNote),
          const Gap(24),
          SectionLabel(l10n(context).customerAbout),
          const Gap(12),
          OpcCard(child: InfoNote(l10n(context).customerAboutNote)),
          const Gap(16),
          PrimaryButton(
            label: l10n(context).customerDemoScenarios,
            icon: Icons.science_outlined,
            secondary: true,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => _DemoLab(app: app)),
            ),
          ),
          const Gap(12),
          PrimaryButton(
            label: l10n(context).customerLogout,
            icon: Icons.logout,
            secondary: true,
            onPressed: app.busy
                ? null
                : () => performAction(context, app, app.repository.logout),
          ),
        ],
      ),
    );
  }
}

/// Explicit demo controls: these are not mobile administrator permissions.
class _DemoLab extends StatelessWidget {
  const _DemoLab({required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) => RepositoryPageGuard(
    app: app,
    title: l10n(context).customerDemoScenarios,
    builder: (context) {
      final mock = app.repository as MockOpcRepository;
      final items = mock.session == null ? <WorkItem>[] : mock.myRequests();
      return OpcPage(
        title: l10n(context).customerDemoScenarios,
        subtitle: l10n(context).customerDemoSubtitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoNote(l10n(context).customerDemoNotice, warning: true),
            const Gap(20),
            if (mock.session?.role == UserRole.provider) ...[
              PrimaryButton(
                label: l10n(context).refScenarios,
                icon: Icons.perm_media_outlined,
                secondary: true,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReferenceScenariosPage(app: app),
                  ),
                ),
              ),
              const Gap(20),
            ],
            for (final item in items.where(
              (i) => [
                WorkStatus.needsInfo,
                WorkStatus.reviewing,
                WorkStatus.internalReview,
              ].contains(i.status),
            )) ...[
              OpcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${item.id} · ${item.title}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(12),
                    PrimaryButton(
                      label: item.status == WorkStatus.internalReview
                          ? l10n(context).customerSimulateDelivery
                          : l10n(context).customerSimulatePublication,
                      secondary: true,
                      onPressed: app.busy
                          ? null
                          : () => performAction(
                              context,
                              app,
                              () => item.status == WorkStatus.internalReview
                                  ? mock.simulateDeliveryPublication(item.id)
                                  : mock.simulateReview(item.id),
                              success: l10n(context).customerDemoUpdated,
                            ),
                    ),
                  ],
                ),
              ),
              const Gap(12),
            ],
            PrimaryButton(
              label: l10n(context).customerFailNextAction,
              icon: Icons.wifi_off,
              secondary: true,
              onPressed: () {
                mock.failNext = true;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n(context).customerFailNextNotice)),
                );
              },
            ),
            const Gap(12),
            PrimaryButton(
              label: l10n(context).customerResetDemo,
              icon: Icons.restart_alt,
              secondary: true,
              onPressed: app.busy
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(l10n(context).customerResetDemoTitle),
                          content: Text(l10n(context).customerResetDemoNotice),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(l10n(context).customerBack),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(l10n(context).customerReset),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && context.mounted) {
                        Navigator.pop(context);
                        await performAction(context, app, mock.reset);
                      }
                    },
            ),
          ],
        ),
      );
    },
  );
}
