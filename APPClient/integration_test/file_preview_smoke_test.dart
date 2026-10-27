// 真实 Android PDF 渲染和系统文件保存验证；不携带业务或管理员凭据。
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/reference_download.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/data/repository.dart';
import 'package:opc_app/features/api_file_page.dart';
import 'package:opc_app/features/api_media_player.dart';

import '../test/api_ui_test.dart' show LiveUiRepository, host, tapKey;

class PdfPhoneRepository extends LiveUiRepository {
  PdfPhoneRepository(this.bytes);
  final Uint8List bytes;
  final fileName =
      'OPC-preview-validation-${DateTime.now().millisecondsSinceEpoch}.pdf';
  @override
  Future<RemoteFile> fileMetadata(String id) async => RemoteFile(
    id: id,
    name: fileName,
    sizeBytes: bytes.length,
    mediaType: 'application/pdf',
    scanStatus: 'clean',
  );
  @override
  Future<RemotePreview> previewFile(String id) async => RemotePreview(
    state: ReferencePreviewState.ready,
    mediaType: 'application/pdf',
    bytes: bytes,
  );
  @override
  Future<Uint8List> downloadFile(String id) async => bytes;
}

class ObservedPhoneStore extends PlatformReferenceFileStore {
  final exported = Completer<bool>();
  @override
  Future<bool> export(String handle, String fileName, String mimeType) async {
    // 验证执行者使用 ADB 操作实际系统文件选择器；不自动选择任意用户目录。
    debugPrint('OPC_NATIVE_SAVE_CHOOSER');
    final success = await super.export(handle, fileName, mimeType);
    exported.complete(success);
    return success;
  }
}

class AudioPhoneRepository extends PdfPhoneRepository {
  AudioPhoneRepository(super.bytes);
  @override
  Future<RemoteFile> fileMetadata(String id) async => RemoteFile(
    id: id,
    name: 'audio-validation.wav',
    sizeBytes: bytes.length,
    mediaType: 'audio/wav',
    scanStatus: 'clean',
  );
  @override
  Future<RemotePreview> previewFile(String id) async => RemotePreview(
    state: ReferencePreviewState.ready,
    mediaType: 'audio/wav',
    bytes: bytes,
  );
}

Uint8List audioFixture() {
  const samples = 24000;
  final data = ByteData(44 + samples * 2);
  void ascii(int start, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(start + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(
      44 + i * 2,
      (math.sin(i * 2 * math.pi * 440 / 8000) * 500).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('actual audio bytes initialize, play and pause on Android', (
    tester,
  ) async {
    final app = AppController(AudioPhoneRepository(audioFixture()));
    addTearDown(app.dispose);
    await tester.pumpWidget(
      host(app, ApiFilePage(app: app, fileId: 'audio-test')),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.audiotrack), findsOneWidget);
    final player = tester
        .widget<ApiMediaPlayer>(find.byType(ApiMediaPlayer))
        .controller;
    expect(player.value.isInitialized, isTrue);
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pump(const Duration(milliseconds: 200));
    expect(player.value.isPlaying, isTrue);
    await tester.tap(find.byIcon(Icons.pause_circle_outline));
    await tester.pumpAndSettle();
    expect(player.value.isPlaying, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('actual PDF pages and original bytes save to Android Files', (
    tester,
  ) async {
    final data = await rootBundle.load('assets/references/workflow.pdf');
    final repo = PdfPhoneRepository(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final app = AppController(repo);
    final store = ObservedPhoneStore();
    addTearDown(app.dispose);
    await app.setLocale(const Locale('zh'));
    await tester.pumpWidget(
      host(app, ApiFilePage(app: app, fileId: 'pdf-test', fileStore: store)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pdf-next')), findsOneWidget);
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('file-preview-pdf-page-1');
    await tapKey(tester, 'pdf-next');
    await binding.takeScreenshot('file-preview-pdf-page-2');
    await tapKey(tester, 'api-file-download');
    final saved = await tester.runAsync(
      () => store.exported.future.timeout(const Duration(seconds: 120)),
    );
    expect(saved, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('文件已导出'), findsOneWidget);
  });
}
