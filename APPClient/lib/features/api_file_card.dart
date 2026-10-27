import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 仅从已有文件名／类型绘制封面，不读取文件、不生成远端预览。
enum FileVisualKind {
  word,
  excel,
  slides,
  pdf,
  image,
  video,
  audio,
  text,
  archive,
  other,
}

FileVisualKind fileVisualKind(String name, [String mediaType = '']) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (['doc', 'docx', 'odt', 'rtf'].contains(ext)) return FileVisualKind.word;
  if (['xls', 'xlsx', 'csv', 'ods', 'tsv'].contains(ext)) {
    return FileVisualKind.excel;
  }
  if (['ppt', 'pptx', 'odp'].contains(ext)) return FileVisualKind.slides;
  if (ext == 'pdf' || mediaType == 'application/pdf') return FileVisualKind.pdf;
  if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp'].contains(ext) ||
      mediaType.startsWith('image/')) {
    return FileVisualKind.image;
  }
  if (['mp4', 'mov', 'webm', 'mkv', 'avi', 'm4v'].contains(ext) ||
      mediaType.startsWith('video/')) {
    return FileVisualKind.video;
  }
  if (['mp3', 'wav', 'm4a', 'ogg', 'flac', 'aac'].contains(ext) ||
      mediaType.startsWith('audio/')) {
    return FileVisualKind.audio;
  }
  if (['txt', 'md', 'markdown', 'json', 'xml', 'log'].contains(ext) ||
      mediaType.startsWith('text/')) {
    return FileVisualKind.text;
  }
  if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
    return FileVisualKind.archive;
  }
  return FileVisualKind.other;
}

extension on FileVisualKind {
  Color color(bool dark) => switch (this) {
    FileVisualKind.word => Color(dark ? 0xFF87B8FF : 0xFF245BB5),
    FileVisualKind.excel => Color(dark ? 0xFF75D6A8 : 0xFF237A50),
    FileVisualKind.slides => Color(dark ? 0xFFFFB18A : 0xFFB94F24),
    FileVisualKind.pdf => Color(dark ? 0xFFFF9B9B : 0xFFB73E46),
    FileVisualKind.image => Color(dark ? 0xFFB5ACFF : 0xFF7061BA),
    FileVisualKind.video => Color(dark ? 0xFFA6B9FF : 0xFF4E64B7),
    FileVisualKind.audio => Color(dark ? 0xFFE3A5E4 : 0xFF984C9C),
    FileVisualKind.text => Color(dark ? 0xFF80CDDA : 0xFF2B7180),
    FileVisualKind.archive ||
    FileVisualKind.other => Color(dark ? 0xFFC4BB9E : 0xFF736746),
  };

  IconData get icon => switch (this) {
    FileVisualKind.word => Icons.description_rounded,
    FileVisualKind.excel => Icons.table_chart_rounded,
    FileVisualKind.slides => Icons.slideshow_rounded,
    FileVisualKind.pdf => Icons.picture_as_pdf_rounded,
    FileVisualKind.image => Icons.image_rounded,
    FileVisualKind.video => Icons.play_circle_fill_rounded,
    FileVisualKind.audio => Icons.graphic_eq_rounded,
    FileVisualKind.text => Icons.article_rounded,
    FileVisualKind.archive => Icons.folder_zip_rounded,
    FileVisualKind.other => Icons.insert_drive_file_rounded,
  };

  String? get letter => switch (this) {
    FileVisualKind.word => 'W',
    FileVisualKind.excel => 'X',
    FileVisualKind.slides => 'P',
    _ => null,
  };
}

class FileTypeCover extends StatelessWidget {
  const FileTypeCover({super.key, required this.name, this.mediaType = ''});
  final String name;
  final String mediaType;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final kind = fileVisualKind(name, mediaType);
    final color = kind.color(c.dark);
    final ext = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : 'FILE';
    return ExcludeSemantics(
      child: Container(
        width: 62,
        height: 76,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: c.dark ? .23 : .15),
              color.withValues(alpha: .04),
            ],
          ),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (kind.letter != null)
              Container(
                width: 30,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  kind.letter!,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: c.dark ? c.background : Colors.white,
                  ),
                ),
              )
            else
              Icon(kind.icon, size: 32, color: color),
            const SizedBox(height: 6),
            Text(
              ext.isEmpty || ext.length > 7 ? 'FILE' : ext,
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 9,
                height: 1.2,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 私有附件、已发布参考资料和交付资料共用；权限仍由文件页重新核对。
class ApiFileCard extends StatelessWidget {
  const ApiFileCard({
    super.key,
    required this.name,
    required this.sizeBytes,
    required this.onTap,
    this.mediaType = '',
    this.status,
    this.warning = false,
    this.trailing,
  });
  final String name;
  final int sizeBytes;
  final String mediaType;
  final String? status;
  final bool warning;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = fileVisualKind(name, mediaType).color(c.dark);
    final size = sizeBytes >= 1024 * 1024
        ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: color.withValues(alpha: c.dark ? .24 : .16)),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Color.alphaBlend(
          color.withValues(alpha: c.dark ? .07 : .025),
          c.surface,
        ),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              children: [
                FileTypeCover(name: name, mediaType: mediaType),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: name,
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(size, style: Theme.of(context).textTheme.bodySmall),
                      if (status != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                warning
                                    ? Icons.shield_outlined
                                    : Icons.verified_user_outlined,
                                size: 12,
                                color: warning ? c.warning : c.secondary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                status!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: warning ? c.warning : c.secondary,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                trailing ??
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: c.secondary,
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
