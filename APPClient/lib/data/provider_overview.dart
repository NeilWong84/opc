import 'models.dart';

enum ProviderProjectFilter { all, communicating, active, delivered }

/// 基于本人有权访问的真实项目及沟通记录；交付数量不等于验收数量。
class ProviderOverview {
  ProviderOverview(
    List<WorkItem> projects,
    List<WorkItem> conversations,
    String userId,
  ) : items = {
        for (final item in conversations)
          if (item.engagementId == null) item.id: item,
        for (final item in projects)
          if (item.providerId == userId && item.engagementId != null)
            item.id: item,
      }.values.toList();

  final List<WorkItem> items;

  static bool matches(WorkItem item, ProviderProjectFilter filter) =>
      switch (filter) {
        ProviderProjectFilter.all => true,
        ProviderProjectFilter.communicating => item.engagementId == null,
        ProviderProjectFilter.active =>
          item.engagementId != null &&
              item.intakeState != 'cancelled' &&
              (item.pendingConfirmation ||
                  [
                    WorkStatus.developing,
                    WorkStatus.revision,
                  ].contains(item.status)),
        ProviderProjectFilter.delivered =>
          item.engagementId != null &&
              item.intakeState != 'cancelled' &&
              [
                WorkStatus.internalReview,
                WorkStatus.awaitingAcceptance,
                WorkStatus.completed,
              ].contains(item.status),
      };

  List<WorkItem> filtered(ProviderProjectFilter filter) =>
      items.where((item) => matches(item, filter)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}
