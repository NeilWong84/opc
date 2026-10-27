import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/customer_overview.dart';
import '../data/models.dart';
import '../l10n/strings.dart';

/// 客户专属总览；所有操作继续进入原有真实业务页面。
class ApiCustomerHome extends StatelessWidget {
  const ApiCustomerHome({
    super.key,
    required this.overview,
    required this.name,
    required this.unreadNotifications,
    required this.hasDraft,
    required this.onNewRequest,
    required this.onFilter,
    required this.onOpen,
    required this.onNotifications,
    required this.onMessages,
    required this.statusText,
    required this.formatTime,
    this.showAllTodos = false,
    required this.onShowAllTodos,
  });

  final CustomerOverview overview;
  final String name;
  final int unreadNotifications;
  final bool hasDraft;
  final VoidCallback onNewRequest;
  final ValueChanged<CustomerRequestFilter> onFilter;
  final void Function(WorkItem item, bool messages) onOpen;
  final VoidCallback onNotifications;
  final VoidCallback onMessages;
  final String Function(WorkItem) statusText;
  final String Function(DateTime) formatTime;
  final bool showAllTodos;
  final VoidCallback onShowAllTodos;

  @override
  Widget build(BuildContext context) {
    final s = l10n(context);
    final c = AppColors.of(context);
    final todos = overview.todos;
    final projects = overview.projects;
    final reviews = overview.reviews;
    final feedback = overview.feedback;
    final metrics = [
      (
        CustomerRequestFilter.reviewing,
        s.homeReviewing,
        Icons.fact_check_outlined,
      ),
      (CustomerRequestFilter.active, s.homeActive, Icons.work_outline),
      (CustomerRequestFilter.acceptance, s.homeAcceptance, Icons.task_alt),
      (
        CustomerRequestFilter.completed,
        s.homeCompleted,
        Icons.verified_outlined,
      ),
    ];

    return Column(
      key: const Key('customer-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OpcCard(
          color: c.hero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.homeGreeting(name), style: TextStyle(color: c.heroMuted)),
              const Gap(6),
              Text(
                s.homeOverview,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: c.heroText),
              ),
              const Gap(8),
              Text(
                s.homeSummary(
                  overview.items.length,
                  overview.items
                      .where((item) => item.engagementId != null)
                      .length,
                ),
                style: TextStyle(color: c.heroMuted),
              ),
              const Gap(16),
              PrimaryButton(
                key: const Key('home-new-request'),
                label: hasDraft ? s.homeDraft : s.apiNewRequest,
                icon: Icons.add,
                onPressed: onNewRequest,
              ),
            ],
          ),
        ),
        const Gap(16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 600 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (filter, label, icon) in metrics)
                  SizedBox(
                    width: width,
                    child: OpcCard(
                      key: ValueKey('home-stat-${filter.name}'),
                      padding: const EdgeInsets.all(14),
                      onTap: () => onFilter(filter),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: c.primary, size: 21),
                          const Gap(8),
                          Text(
                            '${overview.filtered(filter).length}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            label,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (unreadNotifications > 0) ...[
          const Gap(10),
          TextButton.icon(
            key: const Key('home-unread-notifications'),
            onPressed: onNotifications,
            icon: const Icon(Icons.notifications_active_outlined, size: 19),
            label: Text(s.homeUnread(unreadNotifications)),
          ),
        ],
        if (overview.items.isEmpty) ...[
          const Gap(22),
          _empty(
            context,
            s.homeStart,
            s.homeStartHelp,
            Icons.rocket_launch_outlined,
          ),
        ] else ...[
          _heading(context, s.homeTodos, todos.length),
          if (todos.isEmpty)
            _empty(
              context,
              s.homeNoTodos,
              s.homeNoTodosHelp,
              Icons.check_circle_outline,
            ),
          for (final todo in showAllTodos ? todos : todos.take(3)) ...[
            _todo(context, todo),
            const Gap(10),
          ],
          if (!showAllTodos && todos.length > 3)
            TextButton(
              key: const Key('home-more-todos'),
              onPressed: onShowAllTodos,
              child: Text(s.homeMoreTodos),
            ),
          _heading(
            context,
            s.homeProjects,
            projects.length,
            onAll: () => onFilter(CustomerRequestFilter.projects),
          ),
          if (projects.isEmpty)
            _empty(
              context,
              s.homeNoProjects,
              s.homeNoProjectsHelp,
              Icons.work_outline,
            ),
          for (final item in projects.take(3)) ...[
            _project(context, item),
            const Gap(10),
          ],
          _heading(
            context,
            s.homeReviews,
            reviews.length,
            onAll: () => onFilter(CustomerRequestFilter.all),
          ),
          if (reviews.isEmpty)
            _empty(context, s.homeNoReviews, null, Icons.fact_check_outlined),
          for (final item in reviews.take(2)) ...[
            _review(context, item),
            const Gap(10),
          ],
          _heading(context, s.homeFeedback, feedback.length, onAll: onMessages),
          if (feedback.isEmpty)
            _empty(
              context,
              s.homeNoFeedback,
              s.homeNoFeedbackHelp,
              Icons.chat_bubble_outline,
            ),
          for (final entry in feedback.take(3)) ...[
            _feedback(context, entry),
            const Gap(10),
          ],
        ],
      ],
    );
  }

  Widget _heading(
    BuildContext context,
    String title,
    int count, {
    VoidCallback? onAll,
  }) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '$title · $count',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (onAll != null)
          TextButton(onPressed: onAll, child: Text(l10n(context).homeAll)),
      ],
    ),
  );

  Widget _empty(
    BuildContext context,
    String title,
    String? help,
    IconData icon,
  ) {
    final c = AppColors.of(context);
    return OpcCard(
      color: c.raised,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (help != null) ...[
                  const Gap(5),
                  Text(help, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _todo(BuildContext context, CustomerTodo todo) {
    final s = l10n(context);
    final (label, help, icon) = switch (todo.kind) {
      CustomerTodoKind.clarification => (
        s.apiReply,
        todo.item.question ?? s.homeReplyHelp,
        Icons.edit_note,
      ),
      CustomerTodoKind.agreement => (
        s.apiPendingTerms,
        s.homeAgreementHelp,
        Icons.handshake_outlined,
      ),
      CustomerTodoKind.acceptance => (
        s.homeAcceptance,
        s.homeAcceptanceHelp,
        Icons.task_alt,
      ),
    };
    return OpcCard(
      key: ValueKey('home-todo-${todo.item.id}-${todo.kind.name}'),
      onTap: () =>
          onOpen(todo.item, todo.kind == CustomerTodoKind.clarification),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.of(context).warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          const Gap(8),
          Text(
            todo.item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Gap(6),
          Text(
            help,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context, WorkItem item) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              item.publicCode ?? '',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          Flexible(
            child: StatusPill(
              statusText(item),
              warning: item.pendingConfirmation,
            ),
          ),
        ],
      ),
      const Gap(10),
      Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ],
  );

  Widget _project(BuildContext context, WorkItem item) {
    final s = l10n(context);
    final c = AppColors.of(context);
    final step = item.pendingConfirmation
        ? 1
        : item.status == WorkStatus.awaitingAcceptance
        ? 3
        : 2;
    final stages = [
      s.homeStageReview,
      s.homeStageAgreement,
      s.homeStageDevelopment,
      s.homeStageAcceptance,
    ];
    final help = item.pendingConfirmation
        ? item.confirmedByMe
              ? s.apiTermsConfirmed
              : s.homeAgreementHelp
        : switch (item.status) {
            WorkStatus.awaitingAcceptance => s.homeAcceptanceHelp,
            WorkStatus.internalReview => s.homeInternalHelp,
            WorkStatus.revision => s.homeRevisionHelp,
            _ => s.homeWorkingHelp,
          };
    return OpcCard(
      key: ValueKey('home-project-${item.id}'),
      onTap: () => onOpen(item, false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(context, item),
          const Gap(14),
          Row(
            children: [
              for (var i = 0; i < stages.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= step ? c.primary : c.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const Gap(8),
          Text(
            stages[step],
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: c.primary),
          ),
          const Gap(6),
          Text(help, style: Theme.of(context).textTheme.bodySmall),
          if (item.dueAt != null) ...[
            const Gap(12),
            Text(
              '${s.apiDueAt}: ${formatTime(item.dueAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _review(BuildContext context, WorkItem item) {
    final s = l10n(context);
    return OpcCard(
      key: ValueKey('home-review-${item.id}'),
      onTap: () => onOpen(item, false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(context, item),
          const Gap(8),
          Text(
            item.question ??
                (item.status == WorkStatus.published
                    ? s.homePublishedHelp
                    : s.homeReviewHelp),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _feedback(BuildContext context, ProviderFeedback entry) {
    final s = l10n(context);
    final c = AppColors.of(context);
    return OpcCard(
      key: ValueKey(
        'home-feedback-${entry.item.id}-${entry.message.sentAt.toIso8601String()}',
      ),
      onTap: () => onOpen(entry.item, true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: c.soft,
                child: Icon(Icons.person_outline, color: c.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.homeProvider,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      entry.message.author,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          const Gap(10),
          Text(
            entry.item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Gap(6),
          Text(
            entry.message.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const Gap(10),
          Text(
            formatTime(entry.message.sentAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
