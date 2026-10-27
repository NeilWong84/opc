/// Build configuration is explicit; a missing API never enables sample data.
class AppConfig {
  const AppConfig({
    this.environment = 'api',
    this.baseUrl = '',
    this.explicitDemo = false,
    this.release = false,
  });

  final String environment;
  final String baseUrl;
  final bool explicitDemo;
  final bool release;

  bool get useMock => environment == 'mock' && (!release || explicitDemo);

  bool get isConfigured {
    if (environment == 'mock') return useMock;
    if (environment != 'api') return false;
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    if (uri.scheme == 'https') return true;
    // Device debugging uses adb reverse or the emulator's host loopback.
    return !release &&
        uri.scheme == 'http' &&
        const ['127.0.0.1', 'localhost', '10.0.2.2', '::1'].contains(uri.host);
  }
}
