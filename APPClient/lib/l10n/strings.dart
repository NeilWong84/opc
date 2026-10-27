import 'package:flutter/material.dart';
import '../data/models.dart';
import 'app_localizations.dart';

// The app supplies its persisted locale. Standalone component hosts use Japanese.
AppLocalizations l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? lookupAppLocalizations(const Locale('ja'));

String categoryLabel(BuildContext context, String value) => switch (value) {
  'すべて' => l10n(context).coreAll,
  'Web アプリ' => l10n(context).coreWeb,
  '業務自動化' => l10n(context).coreAutomation,
  'AI 開発' => l10n(context).coreAi,
  _ => value,
};

/// Error codes are language independent; never translate customer content.
String repositoryError(BuildContext context, RepositoryException error) {
  final s = l10n(context);
  return switch (error.code) {
    'session_changed' => s.errorSessionChanged,
    'network_unavailable' => s.errorNetwork,
    'unauthenticated' => s.errorUnauthenticated,
    'account_inactive' => s.errorInactive,
    'customer_required' => s.errorCustomer,
    'provider_required' => s.errorProvider,
    'not_found' => s.errorNotFound,
    'invalid_credentials' => s.errorCredentials,
    'invalid_name' => s.errorName,
    'invalid_email' => s.errorEmail,
    'invalid_password' => s.errorPassword,
    'email_exists' => s.errorEmailExists,
    'invalid_description' => s.errorDescription,
    'invalid_request' => s.errorRequest,
    'invalid_attachments' => s.errorAttachments,
    'invalid_message' => s.errorMessage,
    'state_conflict' => s.errorState,
    'version_conflict' => s.errorVersion,
    'invalid_delivery' => s.errorDelivery,
    'source_not_fixed' => s.errorSource,
    _ => s.coreActionFailed,
  };
}
