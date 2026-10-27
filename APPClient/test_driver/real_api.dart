import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      final summary = <String, dynamic>{...?data}..remove('screenshots');
      await writeResponseData(summary);
    },
    onScreenshot: (name, bytes, [args]) async {
      final directory = Directory('test_artifacts/real-api');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
