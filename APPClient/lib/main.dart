import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/app_controller.dart';
import 'core/app_config.dart';
import 'core/language_picker.dart';
import 'core/preferences.dart';
import 'core/theme.dart';
import 'data/mock_repository.dart';
import 'data/api_repository.dart';
import 'data/repository.dart';
import 'features/auth_page.dart';
import 'features/home_shell.dart';
import 'features/api_workspace.dart';
import 'l10n/app_localizations.dart';
import 'l10n/strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const environment = String.fromEnvironment('APP_ENV', defaultValue: 'api');
  const explicitDemo = bool.fromEnvironment('OPC_DEMO');
  const config = AppConfig(
    environment: environment,
    baseUrl: String.fromEnvironment('OPC_API_BASE_URL'),
    explicitDemo: explicitDemo,
    release: kReleaseMode,
  );
  final controller = AppController(
    config.useMock
        ? MockOpcRepository()
        : ApiOpcRepository(
            baseUrl: config.isConfigured
                ? config.baseUrl
                : 'https://unconfigured.invalid',
          ),
    preferences: SharedPreferencesAppPreferences(),
  );
  await controller.restorePreferences();
  runApp(
    OpcApp(controller: controller, configurationRequired: !config.isConfigured),
  );
}

class OpcApp extends StatelessWidget {
  const OpcApp({
    super.key,
    required this.controller,
    this.configurationRequired = false,
  });
  final AppController controller;
  final bool configurationRequired;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MaterialApp(
      title: 'OPC',
      debugShowCheckedModeBanner: false,
      locale: controller.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: opcTheme(Brightness.light),
      darkTheme: opcTheme(Brightness.dark),
      themeMode: controller.themeMode,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            (AppColors.of(context).dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: AppColors.of(context).footer,
                  systemNavigationBarDividerColor: Colors.transparent,
                ),
        child: Stack(
          children: [
            child!,
            if (controller.busy)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(child: LinearProgressIndicator(minHeight: 2)),
              ),
          ],
        ),
      ),
      home: configurationRequired
          ? Builder(
              builder: (context) => Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'OPC',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n(context).apiApiSetup,
                            textAlign: TextAlign.center,
                          ),
                          LanguagePicker(app: controller),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          : controller.repository.session == null
          ? AuthPage(app: controller)
          : controller.repository is RemoteOpcRepository
          ? ApiWorkspace(
              key: ValueKey(controller.repository.session!.id),
              app: controller,
            )
          : HomeShell(
              key: ValueKey(controller.repository.session!.id),
              app: controller,
            ),
    ),
  );
}
