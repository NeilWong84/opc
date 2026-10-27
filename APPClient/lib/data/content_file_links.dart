/// 正文使用平台文件引用，预览和下载始终经过同一鉴权文件接口。
class ContentFilePart {
  const ContentFilePart(this.text, {this.fileId, this.label = ''});
  final String text;
  final String? fileId;
  final String label;
}

List<ContentFilePart> contentFileParts(String text) {
  const uuid =
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
  final link =
      '(?:opc-file:$uuid|/api/v1/mobile/files/$uuid(?:/download|/preview)?)';
  // 仅处理平台文件 URI；任意 HTML、脚本及第三方 URL 保持原文，不直接执行或请求。
  final expression = RegExp(
    '!?\\[([^\\]]*)\\]\\(($link)\\)|'
    '<(?:img|audio|video|a)\\b[^>]*?(?:src|href)=["\x27]($link)["\x27][^>]*>(?:</(?:audio|video|a)>)?|(?<![A-Za-z0-9/:])($link)',
    caseSensitive: false,
  );
  final result = <ContentFilePart>[];
  var offset = 0;
  for (final match in expression.allMatches(text)) {
    if (match.start > offset) {
      result.add(ContentFilePart(text.substring(offset, match.start)));
    }
    final target = match.group(2) ?? match.group(3) ?? match.group(4)!;
    final id = RegExp(uuid).firstMatch(target)!.group(0)!.toLowerCase();
    result.add(
      ContentFilePart(match.group(0)!, fileId: id, label: match.group(1) ?? ''),
    );
    offset = match.end;
  }
  if (offset < text.length) result.add(ContentFilePart(text.substring(offset)));
  return result;
}
