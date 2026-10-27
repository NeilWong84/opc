import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'app_controller.dart';

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final s = l10n(context);
    return PopupMenuButton<String>(
      key: const Key('language-menu'),
      tooltip: s.coreLanguage,
      initialValue: app.locale.languageCode,
      onSelected: (language) async {
        final saved = await app.setLocale(Locale(language));
        if (!saved && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n(context).coreLanguageSaveFailed)),
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const Key('language-ja'),
          value: 'ja',
          child: Text(l10n(context).coreJapanese),
        ),
        PopupMenuItem(
          key: const Key('language-zh'),
          value: 'zh',
          child: Text(l10n(context).coreChinese),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, size: 16),
            const SizedBox(width: 5),
            Text(
              app.locale.languageCode == 'zh' ? s.coreChinese : s.coreJapanese,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Icon(Icons.expand_more, size: 16),
          ],
        ),
      ),
    );
  }
}
