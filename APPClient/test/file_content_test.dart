import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/document_renderer.dart';
import 'package:opc_app/data/content_file_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = '00000000-0000-4000-8000-000000000001';
  test(
    'body images, audio, video and documents resolve to protected file IDs',
    () {
      final text =
          '原文 ![截图](opc-file:$id)\n'
          '<audio src="/api/v1/mobile/files/$id"></audio>\n'
          '<video src="opc-file:$id"></video>\n'
          '[文档](/api/v1/mobile/files/$id/download)';
      final parts = contentFileParts(text);
      expect(parts.where((p) => p.fileId != null), hasLength(4));
      expect(
        parts.where((p) => p.fileId != null).every((p) => p.fileId == id),
        isTrue,
      );
      expect(parts.first.text, '原文 ');
      expect(parts[1].label, '截图');
    },
  );
  test(
    'third-party URLs, script markup and invalid IDs remain inert source text',
    () {
      final text =
          '![外链](https://example.com/api/v1/mobile/files/$id) '
          '<script>alert(1)</script> opc-file:../../secret';
      expect(contentFileParts(text).where((p) => p.fileId != null), isEmpty);
      expect(contentFileParts(text).single.text, text);
    },
  );
  test(
    'PDF channel tracks actual page count and closes its native handle',
    () async {
      const channel = MethodChannel('test/pdf');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'open' => {'handle': 'document', 'pages': 2},
              'page' => Uint8List.fromList([1, 2, 3]),
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final document = DocumentRenderer(channel: channel);
      await document.open(Uint8List.fromList([37, 80, 68, 70, 45]));
      expect(document.pages, 2);
      expect(await document.render(1), [1, 2, 3]);
      await expectLater(document.render(2), throwsStateError);
      await document.close();
      expect(calls.last.method, 'close');
      expect(document.pages, 0);
    },
  );
}
