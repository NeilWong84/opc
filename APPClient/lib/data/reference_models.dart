/// Formats of an explicitly published task reference, separate from deliveries.
enum ReferenceKind {
  image,
  video,
  document,
  spreadsheet,
  presentation,
  pdf,
  text,
  other,
}

enum ReferencePreviewState { ready, preparing, failed, unsupported }

/// Bundled, read-only preview content. This is not a document conversion API.
class ReferencePage {
  ReferencePage({
    required this.title,
    List<String> paragraphs = const [],
    List<String> bullets = const [],
    this.imageAsset,
  }) : paragraphs = List.unmodifiable(paragraphs),
       bullets = List.unmodifiable(bullets);

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
  final String? imageAsset;
}

class ReferenceSheet {
  ReferenceSheet({required this.name, List<List<String>> rows = const []})
    : rows = List.unmodifiable(
        rows.map((row) => List<String>.unmodifiable(row)),
      );

  final String name;
  final List<List<String>> rows;
}

class TaskReference {
  TaskReference({
    required this.id,
    required this.fileName,
    required this.kind,
    required this.sizeBytes,
    required this.assetPath,
    this.thumbnailAsset,
    required this.publishedVersion,
    this.previewState = ReferencePreviewState.ready,
    this.durationSeconds = 0,
    List<ReferencePage> pages = const [],
    List<ReferenceSheet> sheets = const [],
    this.text = '',
    this.description = '',
    this.remote = false,
  }) : pages = List.unmodifiable(pages),
       sheets = List.unmodifiable(sheets);

  final String id;
  final String fileName;
  final ReferenceKind kind;
  final int sizeBytes;
  final String assetPath;
  final String? thumbnailAsset;

  /// Must match the task's reviewed and published version; 0 is private.
  final int publishedVersion;
  final ReferencePreviewState previewState;
  final int durationSeconds;
  final List<ReferencePage> pages;
  final List<ReferenceSheet> sheets;
  final String text;
  final String description;

  /// Live metadata uses an authenticated file endpoint; assetPath is empty.
  final bool remote;

  String get extension {
    final dot = fileName.lastIndexOf('.');
    return dot <= 0 || dot == fileName.length - 1
        ? ''
        : fileName.substring(dot + 1).toLowerCase();
  }

  TaskReference copyWith({
    ReferencePreviewState? previewState,
    int? publishedVersion,
  }) => TaskReference(
    id: id,
    fileName: fileName,
    kind: kind,
    sizeBytes: sizeBytes,
    assetPath: assetPath,
    thumbnailAsset: thumbnailAsset,
    publishedVersion: publishedVersion ?? this.publishedVersion,
    previewState: previewState ?? this.previewState,
    durationSeconds: durationSeconds,
    pages: pages,
    sheets: sheets,
    text: text,
    description: description,
    remote: remote,
  );
}
