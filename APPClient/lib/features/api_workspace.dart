import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/language_picker.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../data/customer_overview.dart';
import '../data/provider_overview.dart';
import '../data/repository.dart';
import '../l10n/strings.dart';
import 'api_forms.dart';
import 'api_work_page.dart';
import 'api_customer_home.dart';
import 'api_classifications.dart';
import 'api_provider_home.dart';

export 'api_forms.dart';
export 'api_work_page.dart';
export 'api_file_page.dart';

RemoteOpcRepository remote(AppController app) =>
    app.repository as RemoteOpcRepository;

String apiError(BuildContext context, Object error) {
  final s = l10n(context);
  if (error is! RepositoryException) return s.apiUnexpected;
  return switch (error.code) {
    'network_unavailable' || 'network_error' || 'timeout' => s.apiNetworkError,
    'version_conflict' || 'state_conflict' || 'conflict' => s.apiConflict,
    'forbidden' ||
    'permission_denied' ||
    'authorization_required' => s.apiForbidden,
    'file_not_ready' || 'scan_pending' => s.apiSafetyNotice,
    'file_not_cleared' || 'file_unavailable' => s.apiFileUnavailable,
    'database_unavailable' ||
    'storage_unavailable' ||
    'request_failed' => s.apiUnexpected,
    'file_too_large' => s.apiFileTooLarge,
    _ => repositoryError(context, error),
  };
}

Future<bool> apiAction(
  BuildContext context,
  AppController app,
  Future<void> Function() action, {
  String? success,
}) async {
  if (app.busy) return false;
  try {
    await app.run(action);
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(apiError(context, error))));
      if (app.repository.session == null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
    return false;
  }
}

String jst(DateTime value) {
  final local = value.toUtc().add(const Duration(hours: 9));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)} JST';
}

class ApiRefreshButton extends StatelessWidget {
  const ApiRefreshButton({
    super.key,
    required this.app,
    required this.onRefresh,
  });
  final AppController app;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('api-refresh'),
    tooltip: l10n(context).apiRefresh,
    onPressed: app.busy ? null : onRefresh,
    icon: const Icon(Icons.refresh),
  );
}

class ApiWorkspace extends StatefulWidget {
  const ApiWorkspace({super.key, required this.app});
  final AppController app;
  @override
  State<ApiWorkspace> createState() => _ApiWorkspaceState();
}

class _ApiWorkspaceState extends State<ApiWorkspace>
    with WidgetsBindingObserver {
  int _tab = 0;
  String _query = '';
  String? _platformCode;
  String? _developmentTypeCode;
  Object? _error;
  bool _loading = false;
  bool _showAllTodos = false;
  CustomerRequestFilter _requestFilter = CustomerRequestFilter.all;
  ProviderProjectFilter _providerFilter = ProviderProjectFilter.all;
  RemoteOpcRepository get _repo => remote(widget.app);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true &&
        !_loading &&
        !widget.app.busy) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_loading || widget.app.busy) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.app.run(_repo.refresh);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted && _repo.session != null) await _refresh();
  }

  void _showRequests(CustomerRequestFilter filter) {
    setState(() {
      _requestFilter = filter;
      _platformCode = null;
      _developmentTypeCode = null;
      _tab = 1;
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final s = l10n(context);
      final session = _repo.session;
      if (session == null) return const SizedBox.shrink();
      final provider = session.role == UserRole.provider;
      final labels = provider
          ? [
              s.customerHome,
              s.providerHall,
              s.customerProjects,
              s.apiMessages,
              s.apiProfile,
            ]
          : [s.customerHome, s.customerRequests, s.apiMessages, s.apiProfile];
      final icons = provider
          ? [
              Icons.home_outlined,
              Icons.search,
              Icons.work_outline,
              Icons.chat_bubble_outline,
              Icons.person_outline,
            ]
          : [
              Icons.home_outlined,
              Icons.work_outline,
              Icons.chat_bubble_outline,
              Icons.person_outline,
            ];
      return OpcPage(
        back: false,
        title: labels[_tab],
        subtitle: _tab == (provider ? 4 : 3)
            ? session.email
            : !provider && _tab == 0
            ? s.homeIntro
            : s.authIntro,
        onRefresh: _refresh,
        actions: [
          ApiRefreshButton(app: widget.app, onRefresh: _refresh),
          IconButton(
            key: const Key('api-notifications'),
            tooltip: s.apiNotifications,
            onPressed: () => _open(ApiNotificationsPage(app: widget.app)),
            icon: const Icon(Icons.notifications_none),
          ),
        ],
        navigation: NavigationBar(
          selectedIndex: !provider && _tab >= 2 ? _tab + 1 : _tab,
          onDestinationSelected: (index) {
            if (!provider && index == 2) {
              _open(ApiRequestPage(app: widget.app));
              return;
            }
            setState(() {
              _tab = !provider && index > 2 ? index - 1 : index;
              _requestFilter = CustomerRequestFilter.all;
              _providerFilter = ProviderProjectFilter.all;
            });
            _refresh();
          },
          destinations: [
            for (var i = 0; i < labels.length; i++) ...[
              if (!provider && i == 2)
                NavigationDestination(
                  key: const Key('api-new-request'),
                  icon: const Icon(Icons.add_circle_outline),
                  label: s.apiNewRequestTab,
                ),
              NavigationDestination(
                key: ValueKey('tab-$i'),
                icon: Icon(icons[i]),
                label: labels[i],
              ),
            ],
          ],
        ),
        child: _error != null
            ? Column(
                children: [
                  InfoNote(apiError(context, _error!), warning: true),
                  const Gap(16),
                  PrimaryButton(label: s.apiRetry, onPressed: _refresh),
                ],
              )
            : _safeContent(context, provider),
      );
    },
  );

  Widget _safeContent(BuildContext context, bool provider) {
    try {
      if (provider && _tab == 0) {
        return ApiProviderHome(
          overview: ProviderOverview(
            _repo.myRequests(),
            _repo.conversationRequests(),
            _repo.session!.id,
          ),
          onHall: () {
            setState(() => _tab = 1);
            _refresh();
          },
          onFilter: (filter) {
            setState(() {
              _providerFilter = filter;
              _tab = filter == ProviderProjectFilter.communicating ? 3 : 2;
            });
            _refresh();
          },
          onOpen: (item) => _open(
            ApiWorkPage(
              app: widget.app,
              id: item.id,
              showMessages: item.engagementId == null,
            ),
          ),
          statusText: (item) => apiStatus(context, item),
        );
      }
      if (!provider && _tab == 0) {
        final session = _repo.session!;
        return ApiCustomerHome(
          overview: CustomerOverview(_repo.myRequests(), session.id),
          name: session.name,
          unreadNotifications: _repo
              .notifications()
              .where((n) => !n.isRead)
              .length,
          hasDraft: _repo.draft != null,
          onNewRequest: () => _open(ApiRequestPage(app: widget.app)),
          onFilter: _showRequests,
          onOpen: (item, messages) => _open(
            ApiWorkPage(app: widget.app, id: item.id, showMessages: messages),
          ),
          onNotifications: () => _open(ApiNotificationsPage(app: widget.app)),
          onMessages: () {
            setState(() => _tab = 2);
            _refresh();
          },
          statusText: (item) => apiStatus(context, item),
          formatTime: jst,
          showAllTodos: _showAllTodos,
          onShowAllTodos: () => setState(() => _showAllTodos = true),
        );
      }
      return _tab == (provider ? 4 : 3)
          ? _profile(context)
          : _list(context, provider);
    } on RepositoryException catch (error) {
      return Column(
        children: [
          InfoNote(apiError(context, error), warning: true),
          const Gap(16),
          PrimaryButton(label: l10n(context).apiRetry, onPressed: _refresh),
        ],
      );
    }
  }

  Widget _profile(BuildContext context) {
    final s = l10n(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OpcCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _repo.session!.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Gap(8),
              Text(_repo.session!.email),
              const Gap(16),
              LanguagePicker(app: widget.app),
              const Gap(16),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto),
                    label: Text(s.customerThemeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_outlined),
                    label: Text(s.customerThemeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_outlined),
                    label: Text(s.customerThemeDark),
                  ),
                ],
                selected: {widget.app.themeMode},
                onSelectionChanged: (values) =>
                    widget.app.setTheme(values.first),
              ),
            ],
          ),
        ),
        const Gap(20),
        InfoNote(s.apiSessionNotice),
        const Gap(24),
        PrimaryButton(
          key: const Key('api-logout'),
          label: s.apiLogout,
          secondary: true,
          onPressed: widget.app.busy
              ? null
              : () => apiAction(context, widget.app, _repo.logout),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, bool provider) {
    final s = l10n(context);
    final hall = provider && _tab == 1;
    final messages = _tab == (provider ? 3 : 2);
    final records = hall
        ? _repo.hall(query: _query)
        : provider && messages
        ? _repo.conversationRequests()
        : _repo.myRequests();
    final items = provider && !hall
        ? records
              .where((item) => ProviderOverview.matches(item, _providerFilter))
              .toList()
        : !provider && _tab == 1
        ? records
              .where(
                (item) =>
                    CustomerOverview.matches(item, _requestFilter) &&
                    (_platformCode == null ||
                        (item.platformCode ?? 'unclassified') ==
                            _platformCode) &&
                    (_developmentTypeCode == null ||
                        (item.developmentTypeCode ?? 'unclassified') ==
                            _developmentTypeCode),
              )
              .toList()
        : records;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!provider && _tab == 1) ...[
          ApiClassificationFields(
            app: widget.app,
            filter: true,
            platformCode: _platformCode,
            developmentTypeCode: _developmentTypeCode,
            onPlatformChanged: (value) => setState(() => _platformCode = value),
            onTypeChanged: (value) =>
                setState(() => _developmentTypeCode = value),
          ),
          if (_platformCode != null || _developmentTypeCode != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('classification-clear'),
                onPressed: () => setState(() {
                  _platformCode = null;
                  _developmentTypeCode = null;
                }),
                child: Text(s.classificationClear),
              ),
            ),
          const Gap(20),
        ],
        if (provider &&
            !hall &&
            _providerFilter != ProviderProjectFilter.all) ...[
          Text(switch (_providerFilter) {
            ProviderProjectFilter.communicating => s.providerCommunicating,
            ProviderProjectFilter.active => s.homeActive,
            ProviderProjectFilter.delivered => s.providerDelivered,
            ProviderProjectFilter.all => s.customerProjects,
          }, style: Theme.of(context).textTheme.titleLarge),
          TextButton(
            key: const Key('provider-clear-filter'),
            onPressed: () =>
                setState(() => _providerFilter = ProviderProjectFilter.all),
            child: Text(s.homeClearFilter),
          ),
        ],
        if (!provider &&
            _tab == 1 &&
            _requestFilter != CustomerRequestFilter.all) ...[
          Text(switch (_requestFilter) {
            CustomerRequestFilter.reviewing => s.homeReviewing,
            CustomerRequestFilter.active => s.homeActive,
            CustomerRequestFilter.acceptance => s.homeAcceptance,
            CustomerRequestFilter.completed => s.homeCompleted,
            CustomerRequestFilter.projects => s.homeProjects,
            CustomerRequestFilter.all => s.customerRequests,
          }, style: Theme.of(context).textTheme.titleLarge),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('home-clear-filter'),
              onPressed: () =>
                  setState(() => _requestFilter = CustomerRequestFilter.all),
              child: Text(s.homeClearFilter),
            ),
          ),
          const Gap(8),
        ],
        if (hall) ...[
          InfoNote(s.providerHallHelp),
          const Gap(12),
          TextField(
            key: const Key('api-hall-search'),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: s.hallSearch,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const Gap(18),
        ],
        if (items.isEmpty) InfoNote(s.apiEmpty),
        for (final item in items) ...[
          OpcCard(
            key: ValueKey('api-item-${item.id}'),
            onTap: () => _open(
              ApiWorkPage(app: widget.app, id: item.id, showMessages: messages),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.publicCode ?? item.id,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    Flexible(
                      child: StatusPill(
                        apiStatus(context, item),
                        warning: item.pendingConfirmation,
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Gap(8),
                Text(
                  messages && item.messages.isNotEmpty
                      ? item.messages.last.text
                      : item.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Gap(12),
                Text(
                  jst(item.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (provider &&
                    !hall &&
                    item.canSubmitDeliveryBy(_repo.session)) ...[
                  const Gap(16),
                  PrimaryButton(
                    key: ValueKey('api-item-delivery-${item.id}'),
                    label: s.apiOpenDelivery,
                    icon: Icons.cloud_upload_outlined,
                    onPressed: widget.app.busy
                        ? null
                        : () => _open(
                            ApiWorkPage(
                              app: widget.app,
                              id: item.id,
                              openDelivery: true,
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(12),
        ],
      ],
    );
  }
}

class ApiNotificationsPage extends StatefulWidget {
  const ApiNotificationsPage({super.key, required this.app});
  final AppController app;
  @override
  State<ApiNotificationsPage> createState() => _ApiNotificationsPageState();
}

class _ApiNotificationsPageState extends State<ApiNotificationsPage> {
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final s = l10n(context);
      final List<AppNotification> notifications;
      try {
        notifications = remote(widget.app).notifications();
      } on RepositoryException catch (error) {
        return OpcPage(
          title: s.apiNotifications,
          actions: [
            ApiRefreshButton(
              app: widget.app,
              onRefresh: () =>
                  apiAction(context, widget.app, remote(widget.app).refresh),
            ),
          ],
          child: InfoNote(apiError(context, error), warning: true),
        );
      }
      return OpcPage(
        title: s.apiNotifications,
        actions: [
          ApiRefreshButton(
            app: widget.app,
            onRefresh: () =>
                apiAction(context, widget.app, remote(widget.app).refresh),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notifications.isEmpty) InfoNote(s.apiNoNotifications),
            for (final n in notifications) ...[
              OpcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      notificationLabel(context, n.templateKey),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Gap(8),
                    Text(jst(n.createdAt)),
                    if (n.parameters['reason'] is String) ...[
                      const Gap(8),
                      Text(n.parameters['reason'] as String),
                    ],
                    if (!n.isRead)
                      TextButton(
                        onPressed: widget.app.busy
                            ? null
                            : () => apiAction(
                                context,
                                widget.app,
                                () => remote(
                                  widget.app,
                                ).markNotificationRead(n.id),
                              ),
                        child: Text(s.apiMarkRead),
                      ),
                  ],
                ),
              ),
              const Gap(12),
            ],
          ],
        ),
      );
    },
  );
}

String notificationLabel(BuildContext context, String key) {
  final s = l10n(context);
  return switch (key) {
    'request.submitted' || 'intake_received' => s.apiSubmitted,
    'request.revised' => s.apiRequestUpdated,
    'request.withdrawn' => s.apiWithdrawn,
    'publication.withdrawn' => s.apiPublicationWithdrawn,
    'clarification.requested' => s.apiReply,
    'agreement.reassigned' || 'agreement.updated' => s.apiTermsUpdated,
    'agreement.confirmed' => s.coreDeveloping,
    'delivery.submitted' => s.apiDeliverySubmitted,
    'delivery.reviewed' => s.apiDeliveryReviewed,
    'delivery.published' => s.coreAwaitingAcceptance,
    'delivery.withdrawn' => s.apiDeliveryWithdrawn,
    'delivery.accepted' => s.coreCompleted,
    'delivery.revision_requested' => s.coreRevision,
    'intake_needs_info' || 'request_needs_info' => s.apiReply,
    'request.published' ||
    'intake_published' ||
    'request_published' => s.corePublished,
    'engagement_confirmation_required' ||
    'agreement_confirmation_required' => s.apiPendingTerms,
    'engagement_confirmed' => s.coreDeveloping,
    'delivery_published' => s.coreAwaitingAcceptance,
    'delivery_accepted' || 'acceptance_recorded' => s.coreCompleted,
    'revision_requested' => s.coreRevision,
    'message_received' || 'new_message' => s.apiMessages,
    _ => s.apiChanged,
  };
}
