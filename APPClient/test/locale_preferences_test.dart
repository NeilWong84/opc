import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/preferences.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppController _controller({AppPreferences? preferences}) => AppController(
  MockOpcRepository(delay: Duration.zero),
  preferences: preferences,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'default controller has a platform-independent Japanese preference',
    () async {
      final app = _controller();
      addTearDown(app.dispose);
      expect(app.locale, const Locale('ja'));
      await app.restorePreferences();
      expect(app.locale, const Locale('ja'));
      expect(await app.setLocale(const Locale('zh', 'CN')), isTrue);
      expect(app.locale, const Locale('zh'));
    },
  );

  test(
    'memory preferences survive a new controller and normalize locales',
    () async {
      final preferences = MemoryAppPreferences();
      final first = _controller(preferences: preferences);
      expect(
        await first.setLocale(
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: 'CN',
          ),
        ),
        isTrue,
      );
      expect(first.locale, const Locale('zh'));
      first.dispose();

      final restarted = _controller(preferences: preferences);
      addTearDown(restarted.dispose);
      expect(restarted.locale, const Locale('ja'));
      await restarted.restorePreferences();
      expect(restarted.locale, const Locale('zh'));
      expect(await restarted.setLocale(const Locale('ja', 'JP')), isTrue);
      expect(restarted.locale, const Locale('ja'));
      expect(await preferences.readLanguage(), 'ja');
    },
  );

  test(
    'unsupported stored and requested languages use or retain Japanese',
    () async {
      for (final stored in [null, '', 'en', 'zh_CN', 'invalid']) {
        final preferences = MemoryAppPreferences(language: stored);
        final app = _controller(preferences: preferences);
        await app.restorePreferences();
        expect(app.locale, const Locale('ja'));
        expect(await app.setLocale(const Locale('en', 'US')), isFalse);
        expect(app.locale, const Locale('ja'));
        expect(await preferences.readLanguage(), stored);
        app.dispose();
      }
    },
  );

  test(
    'rapid choices update immediately and persist in order despite failure',
    () async {
      final preferences = _ControlledPreferences();
      final app = _controller(preferences: preferences);
      addTearDown(app.dispose);
      final notifications = <String>[];
      app.addListener(() => notifications.add(app.locale.languageCode));

      final first = app.setLocale(const Locale('zh'));
      expect(app.locale, const Locale('zh'));
      final second = app.setLocale(const Locale('ja'));
      expect(app.locale, const Locale('ja'));
      final third = app.setLocale(const Locale('zh', 'TW'));
      expect(app.locale, const Locale('zh'));
      expect(notifications, ['zh', 'ja', 'zh']);

      await Future<void>.delayed(Duration.zero);
      expect(preferences.started, ['zh']);
      preferences.pending.single.complete(true);
      expect(await first, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(preferences.started, ['zh', 'ja']);
      preferences.pending.last.completeError(StateError('Storage unavailable'));
      expect(await second, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(preferences.started, ['zh', 'ja', 'zh']);
      preferences.pending.last.complete(true);
      expect(await third, isTrue);
      expect(preferences.saved, 'zh');

      final restarted = _controller(preferences: preferences);
      addTearDown(restarted.dispose);
      await restarted.restorePreferences();
      expect(restarted.locale, const Locale('zh'));
    },
  );

  test(
    'a false write result is reported without rolling back the UI',
    () async {
      final preferences = _ControlledPreferences();
      final app = _controller(preferences: preferences);
      addTearDown(app.dispose);
      final result = app.setLocale(const Locale('zh'));
      await Future<void>.delayed(Duration.zero);
      preferences.pending.single.complete(false);
      expect(await result, isFalse);
      expect(app.locale, const Locale('zh'));
      expect(preferences.saved, isNull);
    },
  );

  test('a delayed restore cannot replace a newer user selection', () async {
    final preferences = _DelayedReadPreferences();
    final app = _controller(preferences: preferences);
    addTearDown(app.dispose);
    final restore = app.restorePreferences();
    expect(await app.setLocale(const Locale('zh')), isTrue);
    preferences.read.complete('ja');
    await restore;
    expect(app.locale, const Locale('zh'));
  });

  test('a failed preference read preserves the Japanese default', () async {
    final preferences = _DelayedReadPreferences();
    final app = _controller(preferences: preferences);
    addTearDown(app.dispose);
    final restore = app.restorePreferences();
    preferences.read.completeError(StateError('Read failed'));
    await restore;
    expect(app.locale, const Locale('ja'));
  });

  test(
    'logout and scenario reset do not change the language preference',
    () async {
      final preferences = MemoryAppPreferences();
      final app = _controller(preferences: preferences);
      addTearDown(app.dispose);
      await app.repository.login('customer@opc.demo', 'demo1234');
      final before = app.repository.detail('OPC-1017');
      expect(await app.setLocale(const Locale('zh')), isTrue);
      final after = app.repository.detail('OPC-1017');
      expect(after.status, before.status);
      expect(after.version, before.version);
      expect(after.title, before.title);
      expect(after.description, before.description);
      expect(after.deliveries, orderedEquals(before.deliveries));
      expect(app.repository.session?.email, 'customer@opc.demo');
      await app.repository.logout();
      expect(app.locale, const Locale('zh'));
      await app.repository.reset();
      expect(app.locale, const Locale('zh'));
      expect(await preferences.readLanguage(), 'zh');
    },
  );

  test(
    'SharedPreferences adapter restores the language across controllers',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = _controller(preferences: SharedPreferencesAppPreferences());
      await first.restorePreferences();
      expect(first.locale, const Locale('ja'));
      expect(await first.setLocale(const Locale('zh', 'CN')), isTrue);
      first.dispose();

      final restarted = _controller(
        preferences: SharedPreferencesAppPreferences(),
      );
      addTearDown(restarted.dispose);
      await restarted.restorePreferences();
      expect(restarted.locale, const Locale('zh'));
      final storage = await SharedPreferences.getInstance();
      expect(storage.getKeys(), {SharedPreferencesAppPreferences.languageKey});
      expect(
        storage.getString(SharedPreferencesAppPreferences.languageKey),
        'zh',
      );
    },
  );

  test('invalid SharedPreferences values fall back to Japanese', () async {
    for (final value in ['en', '', 42]) {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesAppPreferences.languageKey: value,
      });
      final app = _controller(preferences: SharedPreferencesAppPreferences());
      await app.restorePreferences();
      expect(app.locale, const Locale('ja'));
      app.dispose();
    }
  });
}

class _ControlledPreferences implements AppPreferences {
  final started = <String>[];
  final pending = <Completer<bool>>[];
  String? saved;

  @override
  Future<String?> readLanguage() async => saved;

  @override
  Future<bool> writeLanguage(String languageCode) async {
    started.add(languageCode);
    final completion = Completer<bool>();
    pending.add(completion);
    final success = await completion.future;
    if (success) saved = languageCode;
    return success;
  }
}

class _DelayedReadPreferences implements AppPreferences {
  final read = Completer<String?>();

  @override
  Future<String?> readLanguage() => read.future;

  @override
  Future<bool> writeLanguage(String languageCode) async => true;
}
