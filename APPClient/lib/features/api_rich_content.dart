import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/widgets.dart';
import '../data/content_file_links.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../l10n/strings.dart';
import 'api_file_page.dart';

/// 原文中的平台图片/媒体/文档与附件使用同一个预览、保存页面。
class ApiRichContent extends StatelessWidget {
  const ApiRichContent({super.key, required this.app, required this.text});
  final AppController app;
  final String text;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final part in contentFileParts(text))
        if (part.fileId == null)
          SelectableText(part.text)
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _InlineFile(app: app, id: part.fileId!, label: part.label),
          ),
    ],
  );
}

class _InlineFile extends StatefulWidget {
  const _InlineFile({required this.app, required this.id, required this.label});
  final AppController app;
  final String id;
  final String label;
  @override
  State<_InlineFile> createState() => _InlineFileState();
}

class _InlineFileState extends State<_InlineFile> with WidgetsBindingObserver {
  RemoteFile? _file;
  RemotePreview? _image;
  bool _failed = false;
  int _generation = 0;
  late final String? _account = widget.app.repository.session?.id;
  RemoteOpcRepository get _repo => widget.app.repository as RemoteOpcRepository;
  @override
  void initState() {
    super.initState();
    widget.app.addListener(_accountChanged);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    ++_generation;
    widget.app.removeListener(_accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _accountChanged() {
    if (_repo.session?.id != _account && mounted) {
      ++_generation;
      setState(() {
        _file = null;
        _image = null;
        _failed = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    } else if (mounted) {
      setState(() => _image = null);
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final file = await _repo.fileMetadata(widget.id);
      RemotePreview? image;
      if (file.isReady && file.mediaType.startsWith('image/')) {
        image = await _repo.previewFile(file.id);
      }
      if (!mounted ||
          generation != _generation ||
          _repo.session?.id != _account) {
        return;
      }
      setState(() {
        _file = file;
        _image = image;
        _failed = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _file = null;
          _image = null;
          _failed = true;
        });
        if (_repo.session == null) widget.app.syncSession();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = l10n(context);
    return OpcCard(
      onTap: _failed
          ? null
          : () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ApiFilePage(app: widget.app, fileId: widget.id),
                ),
              );
              if (mounted) _load();
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_image?.bytes != null) ...[
            Image.memory(
              _image!.bytes!,
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
            ),
            const Gap(8),
          ],
          Row(
            children: [
              const Icon(Icons.attach_file, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _failed
                      ? s.apiFileUnavailable
                      : _file?.name ?? s.fileInlineAttachment,
                ),
              ),
              if (!_failed) const Icon(Icons.chevron_right),
            ],
          ),
          if (!_failed && widget.label.isNotEmpty && _file != null) ...[
            const Gap(4),
            Text(widget.label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
