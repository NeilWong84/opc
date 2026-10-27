import 'package:flutter/material.dart';
import '../data/repository.dart';
import 'preferences.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository, {AppPreferences? preferences})
    : _preferences = preferences ?? MemoryAppPreferences();

  final OpcRepository repository;
  final AppPreferences _preferences;
  Locale _locale = const Locale('ja');
  Future<void> _languageWriteTail = Future<void>.value();
  int _localeRevision = 0;
  bool _disposed = false;

  Locale get locale => _locale;
  ThemeMode themeMode = ThemeMode.system;
  bool busy = false;

  /// File reads run independently from form actions. If their HTTP response
  /// invalidates the session, rebuild the app root without starting an action.
  void syncSession() {
    if (!_disposed) notifyListeners();
  }

  /// Called explicitly before runApp; construction does not call any platform
  /// plugin. A concurrent user choice takes precedence over a delayed read.
  Future<void> restorePreferences() async {
    final revision = _localeRevision;
    String? language;
    try {
      language = await _preferences.readLanguage();
    } catch (_) {
      // Unavailable or malformed storage falls back to the default language.
    }
    if (_disposed || revision != _localeRevision) return;
    final normalized = _supportedLanguage(language) ?? 'ja';
    final restored = Locale(normalized);
    if (_locale == restored) return;
    _locale = restored;
    notifyListeners();
  }

  /// UI updates immediately. Writes run in request order so a slow earlier save
  /// cannot overwrite the most recently selected language.
  Future<bool> setLocale(Locale value) {
    final language = _supportedLanguage(value.languageCode);
    if (_disposed || language == null) return Future<bool>.value(false);
    _localeRevision++;
    final normalized = Locale(language);
    if (_locale != normalized) {
      _locale = normalized;
      notifyListeners();
    }
    final write = _languageWriteTail.then((_) async {
      try {
        return await _preferences.writeLanguage(language);
      } catch (_) {
        return false;
      }
    });
    // A failed save is reported to the caller without blocking later choices.
    _languageWriteTail = write.then<void>((_) {});
    return write;
  }

  static String? _supportedLanguage(String? value) {
    final language = value?.trim().toLowerCase();
    return language == 'ja' || language == 'zh' ? language : null;
  }

  void setTheme(ThemeMode value) {
    themeMode = value;
    notifyListeners();
  }

  Future<T> run<T>(Future<T> Function() action) async {
    if (busy) throw StateError('処理中です。しばらくお待ちください。');
    busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
