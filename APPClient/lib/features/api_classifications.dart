import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../l10n/strings.dart';
import 'api_workspace.dart';

/// Both filters and intake use the server's bilingual dictionary and stable codes.
class ApiClassificationFields extends StatefulWidget {
  const ApiClassificationFields({
    super.key,
    required this.app,
    this.platformCode,
    this.developmentTypeCode,
    required this.onPlatformChanged,
    required this.onTypeChanged,
    this.filter = false,
  });
  final AppController app;
  final String? platformCode;
  final String? developmentTypeCode;
  final ValueChanged<String?> onPlatformChanged;
  final ValueChanged<String?> onTypeChanged;
  final bool filter;
  @override
  State<ApiClassificationFields> createState() =>
      _ApiClassificationFieldsState();
}

class _ApiClassificationFieldsState extends State<ApiClassificationFields> {
  late Future<RequestClassifications> _catalog = remote(
    widget.app,
  ).requestClassifications();
  @override
  Widget build(BuildContext context) => FutureBuilder<RequestClassifications>(
    future: _catalog,
    builder: (context, snapshot) {
      final s = l10n(context);
      if (snapshot.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoNote(apiError(context, snapshot.error!), warning: true),
            TextButton(
              onPressed: () => setState(
                () => _catalog = remote(widget.app).requestClassifications(),
              ),
              child: Text(s.apiRetry),
            ),
          ],
        );
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final data = snapshot.data!;
      final language = Localizations.localeOf(context).languageCode;
      Widget field(
        String key,
        String label,
        String? value,
        List<RequestClassification> options,
        ValueChanged<String?> changed,
      ) {
        final values = options
            .where((o) => widget.filter || o.enabled || o.code == value)
            .toList();
        return DropdownButtonFormField<String>(
          key: ValueKey('$key-${value ?? "all"}'),
          initialValue: value,
          isExpanded: true,
          hint: Text(
            widget.filter ? s.classificationAll : s.classificationUnclassified,
          ),
          decoration: InputDecoration(labelText: label),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(
                widget.filter
                    ? s.classificationAll
                    : s.classificationUnclassified,
              ),
            ),
            if (widget.filter)
              DropdownMenuItem(
                value: 'unclassified',
                child: Text(s.classificationUnclassified),
              ),
            for (final option in values)
              DropdownMenuItem(
                value: option.code,
                enabled: widget.filter || option.enabled,
                child: Text(
                  option.label(language),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: widget.app.busy ? null : changed,
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field(
            'classification-platform',
            s.classificationPlatform,
            widget.platformCode,
            data.platforms,
            widget.onPlatformChanged,
          ),
          const Gap(12),
          field(
            'classification-type',
            s.classificationType,
            widget.developmentTypeCode,
            data.developmentTypes,
            widget.onTypeChanged,
          ),
          if (!widget.filter) ...[
            const Gap(8),
            Text(
              s.classificationOptional,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      );
    },
  );
}
