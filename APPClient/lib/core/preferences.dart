import 'package:shared_preferences/shared_preferences.dart';

/// Stores interface preferences only. Credentials and business data never enter
/// this boundary.
abstract class AppPreferences {
  Future<String?> readLanguage();
  Future<bool> writeLanguage(String languageCode);
}

/// The default controller adapter keeps unit/widget tests independent of device
/// plugins. Reuse an instance to model a restart against the same storage.
class MemoryAppPreferences implements AppPreferences {
  MemoryAppPreferences({String? language}) : _language = language;

  String? _language;

  @override
  Future<String?> readLanguage() async => _language;

  @override
  Future<bool> writeLanguage(String languageCode) async {
    _language = languageCode;
    return true;
  }
}

/// Production adapter for the one persisted setting: the selected UI language.
class SharedPreferencesAppPreferences implements AppPreferences {
  static const languageKey = 'opc.language';

  @override
  Future<String?> readLanguage() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(languageKey);
  }

  @override
  Future<bool> writeLanguage(String languageCode) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.setString(languageKey, languageCode);
  }
}
