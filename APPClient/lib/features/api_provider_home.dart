import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../data/provider_overview.dart';
import '../l10n/strings.dart';

class ApiProviderHome extends StatelessWidget {
  const ApiProviderHome({
    super.key,
    required this.overview,
    required this.onHall,
    required this.onFilter,
    required this.onOpen,
    required this.statusText,
  });
  final ProviderOverview overview;
  final VoidCallback onHall;
  final ValueChanged<ProviderProjectFilter> onFilter;
  final ValueChanged<WorkItem> onOpen;
  final String Function(WorkItem) statusText;

  @override
  Widget build(BuildContext context) {
    final s = l10n(context);
    final c = AppColors.of(context);
    final groups = [
      (
        ProviderProjectFilter.communicating,
        s.providerCommunicating,
        Icons.chat_bubble_outline,
      ),
      (ProviderProjectFilter.active, s.homeActive, Icons.work_outline),
      (
        ProviderProjectFilter.delivered,
        s.providerDelivered,
        Icons.inventory_2_outlined,
      ),
    ];
    return Column(
      key: const Key('provider-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OpcCard(
          color: c.hero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.providerOverview,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: c.heroText),
              ),
              const Gap(10),
              Text(s.providerIntro, style: TextStyle(color: c.heroMuted)),
              const Gap(18),
              PrimaryButton(
                key: const Key('provider-open-hall'),
                label: s.providerHall,
                icon: Icons.search,
                onPressed: onHall,
              ),
            ],
          ),
        ),
        const Gap(16),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (filter, label, icon) in groups)
                SizedBox(
                  width: constraints.maxWidth >= 600
                      ? (constraints.maxWidth - 20) / 3
                      : (constraints.maxWidth - 10) / 2,
                  child: OpcCard(
                    key: ValueKey('provider-stat-${filter.name}'),
                    onTap: () => onFilter(filter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: c.primary),
                        const Gap(8),
                        Text(
                          '${overview.filtered(filter).length}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(label),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Gap(12),
        InfoNote(s.providerDeliveredHelp),
        for (final (filter, label, _) in groups) ...[
          const Gap(24),
          SectionLabel(label),
          const Gap(12),
          if (overview.filtered(filter).isEmpty) InfoNote(s.apiEmpty),
          for (final item in overview.filtered(filter).take(3)) ...[
            OpcCard(
              key: ValueKey('provider-recent-${item.id}'),
              onTap: () => onOpen(item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Gap(8),
                  Text(statusText(item)),
                  if (item.messages.isNotEmpty) ...[
                    const Gap(8),
                    Text(
                      item.messages.last.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Gap(10),
          ],
          TextButton(
            key: ValueKey('provider-all-${filter.name}'),
            onPressed: () => onFilter(filter),
            child: Text(s.providerViewAll),
          ),
        ],
      ],
    );
  }
}
