import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'package:flutter/services.dart';
import '../data/models.dart';
import 'app_controller.dart';
import 'theme.dart';

/// Revalidate a submitted form after a language change, retaining all fields.
/// Untouched forms stay untouched; switching language never submits the form.
class LocalizedForm extends Form {
  const LocalizedForm({super.key, required super.child});

  @override
  FormState createState() => _LocalizedFormState();
}

class _LocalizedFormState extends FormState {
  Locale? _locale;
  bool _validated = false;

  @override
  bool validate() {
    _validated = true;
    return super.validate();
  }

  @override
  void reset() {
    _validated = false;
    super.reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Localizations.localeOf(context);
    if (_locale != null && next != _locale && _validated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _validated) validate();
      });
    }
    _locale = next;
  }
}

class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}

class OpcPage extends StatelessWidget {
  const OpcPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.bottom,
    this.navigation,
    this.back = true,
    this.actions,
    this.onRefresh,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? bottom;
  final Widget? navigation;
  final bool back;
  final List<Widget>? actions;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final inlineBottom =
        bottom != null &&
        navigation == null &&
        MediaQuery.viewInsetsOf(context).bottom > 0;
    final scrollView = SingleChildScrollView(
      physics: onRefresh == null ? null : const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: inlineBottom
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [child, const Gap(24), bottom!],
            )
          : child,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(back ? 8 : 20, 10, 12, 18),
                child: Row(
                  children: [
                    if (back)
                      IconButton(
                        tooltip: l10n(context).coreBack,
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => Navigator.maybePop(context),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    ...?actions,
                  ],
                ),
              ),
              Expanded(
                child: onRefresh == null
                    ? scrollView
                    : RefreshIndicator(
                        onRefresh: onRefresh!,
                        child: scrollView,
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar:
            inlineBottom || (bottom == null && navigation == null)
            ? null
            : Container(
                decoration: BoxDecoration(
                  color: c.footer,
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: SafeArea(
                  top: false,
                  child:
                      navigation ??
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                        child: bottom,
                      ),
                ),
              ),
      ),
    );
  }
}

/// Refreshes protected reads and turns expected access failures into a page.
/// Unexpected programming errors are deliberately not swallowed here.
class RepositoryPageGuard extends StatelessWidget {
  const RepositoryPageGuard({
    super.key,
    required this.app,
    required this.title,
    required this.builder,
  });

  final AppController app;
  final String title;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      try {
        return builder(context);
      } on RepositoryException catch (error) {
        return RepositoryUnavailablePage(
          app: app,
          title: title,
          message: repositoryError(context, error),
        );
      }
    },
  );
}

class RepositoryUnavailablePage extends StatelessWidget {
  const RepositoryUnavailablePage({
    super.key,
    required this.app,
    required this.title,
    required this.message,
  });

  final AppController app;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();
    return OpcPage(
      title: title,
      back: canGoBack,
      bottom: canGoBack
          ? null
          : PrimaryButton(
              label: l10n(context).coreBackLogin,
              secondary: true,
              onPressed: app.busy
                  ? null
                  : () => performAction(context, app, app.repository.logout),
            ),
      child: InfoNote(message, warning: true),
    );
  }
}

class OpcCard extends StatelessWidget {
  const OpcCard({
    super.key,
    required this.child,
    this.color,
    this.padding,
    this.onTap,
  });
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: color ?? c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: color == null
              ? c.border.withValues(alpha: .65)
              : Colors.transparent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.warning = false});
  final String text;
  final bool warning;
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: warning ? c.warningSoft : c.soft,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: warning ? c.warning : c.primary,
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary;
  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 7)],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: secondary
          ? OutlinedButton(onPressed: onPressed, child: content)
          : FilledButton(onPressed: onPressed, child: content),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
      if (trailing != null)
        Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class InfoNote extends StatelessWidget {
  const InfoNote(
    this.text, {
    super.key,
    this.icon = Icons.info_outline,
    this.warning = false,
  });
  final String text;
  final IconData icon;
  final bool warning;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Icon(
          icon,
          size: 15,
          color: warning
              ? AppColors.of(context).warning
              : AppColors.of(context).primary,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
    ],
  );
}

Future<bool> performAction(
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
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is RepositoryException
                ? repositoryError(context, e)
                : l10n(context).coreActionFailed,
          ),
        ),
      );
    }
    return false;
  }
}

String statusLabel(BuildContext context, WorkStatus status) => switch (status) {
  WorkStatus.needsInfo => l10n(context).coreNeedsInfo,
  WorkStatus.reviewing => l10n(context).coreReviewing,
  WorkStatus.published => l10n(context).corePublished,
  WorkStatus.developing => l10n(context).coreDeveloping,
  WorkStatus.internalReview => l10n(context).coreInternalReview,
  WorkStatus.awaitingAcceptance => l10n(context).coreAwaitingAcceptance,
  WorkStatus.revision => l10n(context).coreRevision,
  WorkStatus.completed => l10n(context).coreCompleted,
};

Future<void> showDetailSheet(BuildContext context, String title, String body) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const Gap(16),
              Text(body),
              const Gap(24),
              PrimaryButton(
                label: l10n(context).coreClose,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
