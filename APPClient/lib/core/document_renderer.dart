import 'package:flutter/services.dart';

/// 使用手机系统 PDF 渲染器，逐页读取真实 PDF/Office 转换结果，不执行文档脚本。
class DocumentRenderer {
  DocumentRenderer({
    this.channel = const MethodChannel('opc/document_preview'),
  });
  final MethodChannel channel;
  String? _handle;
  int pages = 0;

  Future<void> open(Uint8List bytes) async {
    await close();
    final value = await channel.invokeMapMethod<String, dynamic>('open', {
      'bytes': bytes,
    });
    _handle = value?['handle'] as String?;
    pages = value?['pages'] as int? ?? 0;
    if (_handle == null || pages < 1) throw StateError('Invalid PDF document');
  }

  Future<Uint8List> render(int page) async {
    if (_handle == null || page < 0 || page >= pages) {
      throw StateError('Invalid PDF page');
    }
    final bytes = await channel.invokeMethod<Uint8List>('page', {
      'handle': _handle,
      'page': page,
      'width': 1600,
    });
    if (bytes == null || bytes.isEmpty) {
      throw StateError('PDF page is unavailable');
    }
    return bytes;
  }

  Future<void> close() async {
    final handle = _handle;
    _handle = null;
    pages = 0;
    if (handle != null) {
      await channel.invokeMethod<void>('close', {'handle': handle});
    }
  }
}
