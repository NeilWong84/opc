import 'models.dart';

enum CustomerRequestFilter {
  all,
  reviewing,
  active,
  acceptance,
  completed,
  projects,
}

enum CustomerTodoKind { clarification, agreement, acceptance }

class CustomerTodo {
  const CustomerTodo(this.item, this.kind);
  final WorkItem item;
  final CustomerTodoKind kind;
}

class ProviderFeedback {
  const ProviderFeedback(this.item, this.message);
  final WorkItem item;
  final ChatMessage message;
}

/// 仅汇总当前客户有权读取的快照，不产生业务状态、未读消息数或完成百分比。
class CustomerOverview {
  CustomerOverview(Iterable<WorkItem> records, String customerId)
    : items = records.where((item) => item.ownerId == customerId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  final List<WorkItem> items;

  static bool isClosed(WorkItem item) => const {
    'withdrawn',
    'rejected',
    'cancelled',
    'closed',
  }.contains(item.intakeState);

  static bool matches(WorkItem item, CustomerRequestFilter filter) {
    if (filter == CustomerRequestFilter.all) return true;
    if (isClosed(item)) return false;
    return switch (filter) {
      CustomerRequestFilter.all => true,
      CustomerRequestFilter.projects =>
        item.engagementId != null && item.status != WorkStatus.completed,
      CustomerRequestFilter.reviewing =>
        item.engagementId == null &&
            item.intakeState != 'draft' &&
            (item.status == WorkStatus.reviewing ||
                item.status == WorkStatus.needsInfo),
      CustomerRequestFilter.active =>
        item.engagementId != null &&
            (item.pendingConfirmation ||
                const {
                  WorkStatus.developing,
                  WorkStatus.internalReview,
                  WorkStatus.revision,
                }.contains(item.status)),
      CustomerRequestFilter.acceptance =>
        item.engagementId != null &&
            item.status == WorkStatus.awaitingAcceptance,
      CustomerRequestFilter.completed =>
        item.engagementId != null && item.status == WorkStatus.completed,
    };
  }

  List<WorkItem> filtered(CustomerRequestFilter filter) =>
      items.where((item) => matches(item, filter)).toList();

  List<WorkItem> get reviews => items
      .where(
        (item) =>
            item.engagementId == null &&
            !isClosed(item) &&
            item.intakeState != 'draft' &&
            item.status != WorkStatus.completed,
      )
      .toList();

  List<WorkItem> get projects =>
      items
          .where(
            (item) =>
                item.engagementId != null &&
                !isClosed(item) &&
                item.status != WorkStatus.completed,
          )
          .toList()
        ..sort((a, b) {
          final aDue = a.dueAt;
          final bDue = b.dueAt;
          if (aDue == null && bDue == null) {
            return b.createdAt.compareTo(a.createdAt);
          }
          if (aDue == null) return 1;
          if (bDue == null) return -1;
          return aDue.compareTo(bDue);
        });

  List<CustomerTodo> get todos => [
    for (final item in items.where((item) => !isClosed(item))) ...[
      if (item.question?.trim().isNotEmpty == true)
        CustomerTodo(item, CustomerTodoKind.clarification),
      if (item.pendingConfirmation && !item.confirmedByMe)
        CustomerTodo(item, CustomerTodoKind.agreement),
      if (matches(item, CustomerRequestFilter.acceptance) &&
          item.deliveries.any((delivery) => delivery.published))
        CustomerTodo(item, CustomerTodoKind.acceptance),
    ],
  ];

  List<ProviderFeedback> get feedback {
    final result = <ProviderFeedback>[
      for (final item in items)
        if (item.engagementId != null && item.providerId?.isNotEmpty == true)
          for (final message in item.messages)
            if (message.authorId == item.providerId &&
                message.text.trim().isNotEmpty)
              ProviderFeedback(item, message),
    ];
    return result..sort((a, b) => b.message.sentAt.compareTo(a.message.sentAt));
  }
}
