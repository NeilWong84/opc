import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/data/models.dart';

import 'api_repository_test.dart' show Server, engagementRow;

void main() {
  test('API dictionary, classified draft, request and engagement preserve stable codes', () async {
    final server = Server()..engagement = engagementRow();
    server.row['original'] = {...server.row['original'] as Map<String, dynamic>, 'platform_code': 'web', 'development_type_code': 'crm'};
    final repo = server.repo();
    addTearDown(repo.close);
    await repo.login('customer@example.jp', 'private-password');
    server.override = (request) {
      if (request.url.path.endsWith('/mobile/request-classifications')) {
        return server.json({
          'platforms': [{'code': 'web', 'name_zh': 'Web开发', 'name_ja': 'Webアプリ開発', 'enabled': true}],
          'development_types': [{'code': 'crm', 'name_zh': 'CRM', 'name_ja': '顧客管理（CRM）', 'enabled': true}],
        });
      }
      return null;
    };
    final catalog = await repo.requestClassifications();
    expect(catalog.platforms.single.label('zh'), 'Web开发');
    expect(catalog.platforms.single.label('ja'), 'Webアプリ開発');
    expect(repo.myRequests().single.platformCode, 'web');
    expect(repo.myRequests().single.developmentTypeCode, 'crm');
    final draft = RequestDraft(description: '保留客户原文的开发需求，不由分类代码翻译正文。', platformCode: 'web', developmentTypeCode: 'crm');
    await repo.saveDraft(draft);
    expect(repo.draft!.platformCode, 'web');
    expect(repo.draft!.developmentTypeCode, 'crm');
    await repo.refresh();
    expect(repo.draft!.platformCode, 'web');
    Map<String, dynamic>? submitted;
    server.override = (request) {
      if (request.method == 'POST' && request.url.path.endsWith('/mobile/requests')) {
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return server.json(server.row, 201);
      }
      return null;
    };
    await repo.submitRequest(draft);
    expect(submitted!['platform_code'], 'web');
    expect(submitted!['development_type_code'], 'crm');
    expect(repo.detail('request-1').platformCode, 'web');
    expect(repo.detail('request-1').copyWith(messages: []).developmentTypeCode, 'crm');
  });
}
