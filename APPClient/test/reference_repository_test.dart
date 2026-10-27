import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/data/models.dart';

Matcher _throwsCode(String code) => throwsA(
  isA<RepositoryException>().having((error) => error.code, 'code', code),
);

TaskReference _reference({
  String id = 'visible',
  int version = 2,
  ReferencePreviewState state = ReferencePreviewState.ready,
}) => TaskReference(
  id: id,
  fileName: '$id.MD',
  kind: ReferenceKind.text,
  sizeBytes: 16,
  assetPath: 'assets/references/notes.md',
  publishedVersion: version,
  previewState: state,
  text: '原文は言語設定で変更しません。',
);

WorkItem _task({
  String id = 'TEST-REF',
  String? providerId,
  int version = 2,
  int? publishedVersion = 2,
  bool approved = true,
  WorkStatus status = WorkStatus.published,
  List<TaskReference> references = const [],
  List<String> attachments = const [],
}) => WorkItem(
  id: id,
  title: '参考資料の権限検証',
  description: 'これはアクセス権限を検証するための合成データです。',
  category: 'Web アプリ',
  duration: '相談して決めたい',
  status: status,
  ownerId: 'customer-1',
  providerId: providerId,
  version: version,
  publishedVersion: publishedVersion,
  complianceApproved: approved,
  technicalApproved: approved,
  createdAt: DateTime.utc(2026, 10, 13),
  references: references,
  attachmentNames: attachments,
);

Future<MockOpcRepository> _provider({
  List<WorkItem> fixtures = const [],
  Duration delay = Duration.zero,
}) async {
  final repository = MockOpcRepository(delay: delay, taskFixtures: fixtures);
  await repository.login('member@opc.demo', 'demo1234');
  return repository;
}

void main() {
  test('reference preview lists are deeply immutable snapshots', () {
    final paragraphs = ['原文'];
    final bullets = ['項目'];
    final rows = [
      ['列', '値'],
    ];
    final page = ReferencePage(
      title: '概要',
      paragraphs: paragraphs,
      bullets: bullets,
    );
    final sheet = ReferenceSheet(name: '表', rows: rows);
    final pages = [page];
    final sheets = [sheet];
    final reference = TaskReference(
      id: 'immutable',
      fileName: '原文.XLSX',
      kind: ReferenceKind.spreadsheet,
      sizeBytes: 123,
      assetPath: 'assets/references/fields.xlsx',
      publishedVersion: 2,
      pages: pages,
      sheets: sheets,
    );
    paragraphs.add('外部変更');
    bullets.clear();
    rows.first[0] = '外部変更';
    rows.add(['追加']);
    pages.clear();
    sheets.clear();

    expect(reference.pages.single.paragraphs, ['原文']);
    expect(reference.pages.single.bullets, ['項目']);
    expect(reference.sheets.single.rows, [
      ['列', '値'],
    ]);
    expect(reference.extension, 'xlsx');
    expect(() => reference.pages.clear(), throwsUnsupportedError);
    expect(() => reference.sheets.clear(), throwsUnsupportedError);
    expect(() => page.paragraphs.add('変更'), throwsUnsupportedError);
    expect(() => page.bullets.clear(), throwsUnsupportedError);
    expect(() => sheet.rows.clear(), throwsUnsupportedError);
    expect(() => sheet.rows.first[0] = '変更', throwsUnsupportedError);
  });

  test('task reference copies preserve immutable original snapshots', () {
    final reference = _reference(state: ReferencePreviewState.failed);
    final source = [reference];
    final task = _task(references: source);
    source.clear();
    expect(task.references, [reference]);
    expect(() => task.references.clear(), throwsUnsupportedError);
    final ready = reference.copyWith(previewState: ReferencePreviewState.ready);
    final copy = task.copyWith(references: [ready]);
    expect(copy.references.single.previewState, ReferencePreviewState.ready);
    expect(task.references.single.previewState, ReferencePreviewState.failed);
    expect(ready.publishedVersion, reference.publishedVersion);
    expect(ready.assetPath, reference.assetPath);
    expect(ready.text, reference.text);
    expect(_task().references, isEmpty);
  });

  test(
    'published hall metadata contains exactly nine authorized references',
    () async {
      final repository = await _provider();
      final hall = repository.hall();
      expect(hall, hasLength(2));
      final item = hall.firstWhere((item) => item.id == 'DEV-1036');
      expect(item.references, hasLength(9));
      expect(item.references.map((reference) => reference.fileName), [
        '画面イメージ_01.png',
        '画面イメージ_02.png',
        '操作フロー.mp4',
        '要件整理_v1.docx',
        '項目定義.xlsx',
        'サンプルデータ.csv',
        '画面構成.pptx',
        '業務フロー.pdf',
        '補足事項.md',
      ]);
      expect(
        item.references.every((reference) => reference.publishedVersion == 3),
        isTrue,
      );
      expect(repository.references(item.id), hasLength(9));
      expect(repository.detail(item.id).references, hasLength(9));
      expect(item.attachmentNames, isEmpty);
      expect(
        repository.references('DEV-1039').single.fileName,
        '見積テンプレート.xlsx',
      );
      expect(repository.references('DEV-1039').single.thumbnailAsset, isNull);
    },
  );

  for (final hidden in ['private-client-memo', 'old-screen', 'missing']) {
    test(
      '$hidden is inaccessible by direct reference ID and preview retry',
      () async {
        final repository = await _provider();
        expect(
          () => repository.reference('DEV-1036', hidden),
          _throwsCode('not_found'),
        );
        await expectLater(
          repository.prepareReference('DEV-1036', hidden),
          _throwsCode('not_found'),
        );
        await expectLater(
          repository.simulateReferenceState(
            'DEV-1036',
            hidden,
            ReferencePreviewState.ready,
          ),
          _throwsCode('not_found'),
        );
        expect(repository.references('DEV-1036'), hasLength(9));
      },
    );
  }

  test(
    'unauthenticated and unrelated customers cannot obtain reference metadata',
    () async {
      final repository = MockOpcRepository(delay: Duration.zero);
      expect(
        () => repository.references('DEV-1036'),
        _throwsCode('unauthenticated'),
      );
      await expectLater(
        repository.prepareReference('DEV-1036', 'notes'),
        _throwsCode('unauthenticated'),
      );
      await repository.login('customer@opc.demo', 'demo1234');
      expect(() => repository.references('DEV-1036'), _throwsCode('not_found'));
      expect(
        () => repository.reference('DEV-1036', 'notes'),
        _throwsCode('not_found'),
      );
    },
  );

  test(
    'private original attachment names never become published references',
    () async {
      final repository = MockOpcRepository(delay: Duration.zero);
      await repository.login('customer@opc.demo', 'demo1234');
      final task = await repository.submitRequest(
        RequestDraft(
          description: '顧客の非公開原本を添付した開発相談です。',
          attachmentNames: ['顧客の秘密資料.pdf'],
        ),
      );
      expect(repository.detail(task.id).attachmentNames, ['顧客の秘密資料.pdf']);
      expect(repository.references(task.id), isEmpty);
      await repository.simulateReview(task.id);
      await repository.login('member@opc.demo', 'demo1234');
      expect(repository.detail(task.id).attachmentNames, isEmpty);
      expect(repository.detail(task.id).references, isEmpty);
      expect(repository.references(task.id), isEmpty);
    },
  );

  test(
    'unpublished requests do not reveal reference previews even to their owner',
    () async {
      final task = _task(
        publishedVersion: null,
        approved: false,
        status: WorkStatus.reviewing,
        references: [_reference()],
        attachments: ['本人の添付名.pdf'],
      );
      final repository = MockOpcRepository(
        delay: Duration.zero,
        taskFixtures: [task],
      );
      await repository.login('customer@opc.demo', 'demo1234');
      expect(repository.detail(task.id).references, isEmpty);
      expect(repository.references(task.id), isEmpty);
      expect(repository.detail(task.id).attachmentNames, ['本人の添付名.pdf']);
      expect(
        () => repository.reference(task.id, 'visible'),
        _throwsCode('not_found'),
      );
    },
  );

  test(
    'owner and assigned provider views also filter private and stale references',
    () async {
      final task = _task(
        providerId: 'provider-1',
        status: WorkStatus.developing,
        references: [
          _reference(),
          _reference(id: 'private', version: 0),
          _reference(id: 'old', version: 1),
        ],
      );
      final repository = await _provider(fixtures: [task]);
      for (final email in ['member@opc.demo', 'customer@opc.demo']) {
        await repository.login(email, 'demo1234');
        expect(repository.detail(task.id).references.single.id, 'visible');
        expect(repository.references(task.id).single.id, 'visible');
        expect(
          repository
              .myRequests()
              .firstWhere((item) => item.id == task.id)
              .references
              .single
              .id,
          'visible',
        );
        expect(
          () => repository.reference(task.id, 'old'),
          _throwsCode('not_found'),
        );
      }
    },
  );

  test(
    'old task publication and other provider assignments do not grant access',
    () async {
      final stale = _task(
        version: 3,
        publishedVersion: 2,
        providerId: 'provider-1',
        references: [_reference()],
      );
      final other = _task(
        id: 'OTHER-PROVIDER',
        providerId: 'provider-2',
        status: WorkStatus.developing,
        references: [_reference()],
      );
      final repository = await _provider(fixtures: [stale, other]);
      expect(() => repository.references(stale.id), _throwsCode('not_found'));
      expect(() => repository.references(other.id), _throwsCode('not_found'));
      expect(repository.hall(), hasLength(2));
      await repository.login('customer@opc.demo', 'demo1234');
      expect(repository.references(stale.id), isEmpty);
    },
  );

  for (final state in [
    ReferencePreviewState.preparing,
    ReferencePreviewState.failed,
  ]) {
    test('$state retries only the preview and preserves publication', () async {
      final repository = await _provider();
      await repository.simulateReferenceState(
        'DEV-1036',
        'requirements',
        state,
      );
      final before = repository.detail('DEV-1036');
      final oldReference = repository.reference('DEV-1036', 'requirements');
      final prepared = await repository.prepareReference(
        'DEV-1036',
        'requirements',
      );
      final after = repository.detail('DEV-1036');
      expect(prepared.previewState, ReferencePreviewState.ready);
      expect(oldReference.previewState, state);
      expect(prepared.publishedVersion, oldReference.publishedVersion);
      expect(prepared.assetPath, oldReference.assetPath);
      expect(prepared.fileName, oldReference.fileName);
      expect(after.version, before.version);
      expect(after.publishedVersion, before.publishedVersion);
      expect(after.complianceApproved, before.complianceApproved);
      expect(after.technicalApproved, before.technicalApproved);
      expect(after.status, before.status);
      expect(after.providerId, isNull);
      expect(after.references, hasLength(9));
    });
  }

  test(
    'failed preparation can retry without discarding original metadata',
    () async {
      final repository = await _provider();
      await repository.simulateReferenceState(
        'DEV-1036',
        'notes',
        ReferencePreviewState.failed,
      );
      repository.failNext = true;
      await expectLater(
        repository.prepareReference('DEV-1036', 'notes'),
        _throwsCode('network_unavailable'),
      );
      expect(
        repository.reference('DEV-1036', 'notes').previewState,
        ReferencePreviewState.failed,
      );
      final result = await repository.prepareReference('DEV-1036', 'notes');
      expect(result.previewState, ReferencePreviewState.ready);
      expect(result.fileName, '補足事項.md');
      expect(result.text, contains('開発にあたっての補足'));
    },
  );

  test(
    'unsupported previews remain unsupported while original metadata is readable',
    () async {
      final repository = await _provider();
      await repository.simulateReferenceState(
        'DEV-1036',
        'notes',
        ReferencePreviewState.unsupported,
      );
      final reference = await repository.prepareReference('DEV-1036', 'notes');
      expect(reference.previewState, ReferencePreviewState.unsupported);
      expect(reference.assetPath, 'assets/references/notes.md');
      expect(repository.reference('DEV-1036', 'notes').publishedVersion, 3);
    },
  );

  test(
    'withdrawal removes names and direct access, and cannot republish a reference',
    () async {
      final repository = await _provider();
      await repository.simulateReferenceWithdrawal(
        'DEV-1036',
        'inquiry-overview',
      );
      expect(repository.references('DEV-1036'), hasLength(8));
      expect(
        repository
            .hall()
            .firstWhere((item) => item.id == 'DEV-1036')
            .references
            .any((reference) => reference.id == 'inquiry-overview'),
        isFalse,
      );
      await expectLater(
        repository.prepareReference('DEV-1036', 'inquiry-overview'),
        _throwsCode('not_found'),
      );
      expect(repository.detail('DEV-1036').publishedVersion, 3);
    },
  );

  test('preparation rechecks a reference withdrawn while waiting', () async {
    final repository = await _provider(delay: const Duration(milliseconds: 10));
    final withdrawal = repository.simulateReferenceWithdrawal(
      'DEV-1036',
      'notes',
    );
    final assertion = expectLater(
      repository.prepareReference('DEV-1036', 'notes'),
      _throwsCode('not_found'),
    );
    await withdrawal;
    await assertion;
    expect(repository.references('DEV-1036'), hasLength(8));
  });

  test('preparation rejects a changed session while waiting', () async {
    final repository = await _provider(delay: const Duration(milliseconds: 10));
    final logout = repository.logout();
    final assertion = expectLater(
      repository.prepareReference('DEV-1036', 'notes'),
      _throwsCode('session_changed'),
    );
    await logout;
    await assertion;
    expect(
      () => repository.references('DEV-1036'),
      _throwsCode('unauthenticated'),
    );
  });

  for (final access in ['suspended', 'revoked']) {
    test('$access account loses list, preview and scenario access', () async {
      final repository = await _provider();
      await repository.simulateAccountAccess(
        active: access == 'suspended' ? false : null,
        authorized: access == 'revoked' ? false : null,
      );
      final code = access == 'suspended'
          ? 'account_inactive'
          : 'provider_required';
      expect(() => repository.references('DEV-1036'), _throwsCode(code));
      expect(
        () => repository.reference('DEV-1036', 'notes'),
        _throwsCode(code),
      );
      await expectLater(
        repository.prepareReference('DEV-1036', 'notes'),
        _throwsCode(code),
      );
      await expectLater(
        repository.simulateReferenceState(
          'DEV-1036',
          'notes',
          ReferencePreviewState.ready,
        ),
        _throwsCode(code),
      );
    });
  }

  test('an authorized task without references stays empty', () async {
    final task = _task();
    final repository = await _provider(fixtures: [task]);
    expect(repository.detail(task.id).references, isEmpty);
    expect(repository.references(task.id), isEmpty);
    expect(
      () => repository.reference(task.id, 'notes'),
      _throwsCode('not_found'),
    );
  });
}
