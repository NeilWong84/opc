import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/data/models.dart';

Matcher errorCode(String code) => isA<RepositoryException>().having(
  (exception) => exception.code,
  'code',
  code,
);

Delivery delivery(
  int version, {
  bool published = false,
  String ref = '8f3a2c1',
}) => Delivery(
  version: version,
  sourceName: 'source-v$version.zip',
  sourceRef: ref,
  guideName: 'guide-v$version.pdf',
  testName: 'tests-v$version.pdf',
  note: '合意した範囲の成果物を提出します。',
  published: published,
);

void main() {
  late MockOpcRepository repository;

  Future<void> customer() async {
    await repository.login('customer@opc.demo', 'demo1234');
  }

  Future<void> provider() async {
    await repository.login('member@opc.demo', 'demo1234');
  }

  setUp(() => repository = MockOpcRepository(delay: Duration.zero));

  test('anonymous users cannot inspect requests, hall or details', () {
    expect(repository.session, isNull);
    expect(repository.myRequests, throwsA(errorCode('unauthenticated')));
    expect(repository.hall, throwsA(errorCode('unauthenticated')));
    expect(
      () => repository.detail('REQ-1042'),
      throwsA(errorCode('unauthenticated')),
    );
  });

  test(
    'self registration always creates a customer without internal access',
    () async {
      final user = await repository.register(
        '新しいお客様',
        ' New@example.jp ',
        'password123',
      );
      expect(user.email, 'new@example.jp');
      expect(user.role, UserRole.customer);
      expect(user.authorized, isFalse);
      expect(repository.myRequests(), isEmpty);
      expect(repository.hall, throwsA(errorCode('provider_required')));
      expect(
        () => repository.detail('OPC-1017'),
        throwsA(errorCode('not_found')),
      );
      await expectLater(
        repository.acceptDelivery('OPC-1017', 1),
        throwsA(errorCode('not_found')),
      );
    },
  );

  test(
    'registration validates fields and prevents duplicate normalized emails',
    () async {
      await expectLater(
        repository.register('', 'new@example.jp', 'password123'),
        throwsA(errorCode('invalid_name')),
      );
      await expectLater(
        repository.register('田中', 'not-an-email', 'password123'),
        throwsA(errorCode('invalid_email')),
      );
      await expectLater(
        repository.register('田中', 'new@example.jp', 'short'),
        throwsA(errorCode('invalid_password')),
      );
      await expectLater(
        repository.register('田中', 'CUSTOMER@OPC.DEMO', 'password123'),
        throwsA(errorCode('email_exists')),
      );
      expect(repository.session, isNull);
    },
  );

  test(
    'customer reads own review state but cannot enter the provider hall',
    () async {
      await customer();
      expect(repository.myRequests().map((item) => item.id), [
        'REQ-1042',
        'OPC-1028',
        'OPC-1017',
      ]);
      expect(repository.detail('REQ-1042').status, WorkStatus.needsInfo);
      expect(repository.hall, throwsA(errorCode('provider_required')));
      expect(
        () => repository.detail('DEV-1036'),
        throwsA(errorCode('not_found')),
      );
      await expectLater(
        repository.submitDelivery('OPC-1028', delivery(1)),
        throwsA(errorCode('provider_required')),
      );
    },
  );

  test(
    'hall search, category, counts and detail cannot reveal unreviewed requests',
    () async {
      await provider();
      expect(repository.hall().map((item) => item.id), [
        'DEV-1036',
        'DEV-1039',
      ]);
      expect(repository.hall(query: 'REQ-1042'), isEmpty);
      expect(repository.hall(query: '社内資料'), isEmpty);
      expect(repository.hall(category: 'Web アプリ').single.id, 'DEV-1036');
      expect(repository.hall(query: '見積').single.id, 'DEV-1039');
      expect(
        () => repository.detail('REQ-1042'),
        throwsA(errorCode('not_found')),
      );
      expect(repository.myRequests().map((item) => item.id), [
        'OPC-1028',
        'OPC-1017',
      ]);
    },
  );

  test('publication requires both review results and the current version', () {
    final item = WorkItem(
      id: 'TEST-1',
      title: 'テスト',
      description: 'テスト用の説明です。',
      category: 'Web アプリ',
      duration: '3週間',
      status: WorkStatus.published,
      ownerId: 'customer-1',
      version: 2,
      publishedVersion: 2,
      complianceApproved: true,
      createdAt: DateTime.utc(2026, 10, 12),
    );
    expect(item.isPublished, isFalse);
    expect(item.copyWith(technicalApproved: true).isPublished, isTrue);
    expect(
      item.copyWith(technicalApproved: true, publishedVersion: 1).isPublished,
      isFalse,
    );
  });

  test(
    'submitted requests stay private until explicit mock dual review',
    () async {
      await customer();
      final item = await repository.submitRequest(
        RequestDraft(
          description: '予約の管理を簡単にしたいです。毎日の受付を一か所にまとめたいです。',
          attachmentNames: ['業務メモ.pdf'],
        ),
      );
      expect(item.title, '予約の管理を簡単にしたいです');
      expect(item.status, WorkStatus.reviewing);
      expect(item.isPublished, isFalse);
      expect(item.attachmentNames, ['業務メモ.pdf']);
      await provider();
      expect(repository.hall(query: item.id), isEmpty);
      expect(() => repository.detail(item.id), throwsA(errorCode('not_found')));
      await repository.simulateReview(item.id);
      final published = repository.hall(query: item.id).single;
      expect(published.isPublished, isTrue);
      expect(published.messages, isEmpty);
      expect(published.attachmentNames, isEmpty);
      expect(repository.detail(item.id).attachmentNames, isEmpty);
      await customer();
      expect(repository.detail(item.id).attachmentNames, ['業務メモ.pdf']);
    },
  );

  test('drafts survive logout but are isolated by customer account', () async {
    await customer();
    await repository.saveDraft(RequestDraft(description: '作業中の内容'));
    await repository.logout();
    expect(repository.draft, isNull);
    await repository.register('別の人', 'other@example.jp', 'password123');
    expect(repository.draft, isNull);
    await customer();
    expect(repository.draft!.description, '作業中の内容');
    await repository.submitRequest(
      RequestDraft(description: '業務の受付を自動化するシステムを作りたいです。'),
    );
    expect(repository.draft, isNull);
  });

  test(
    'clarification increments scope version and returns to private review',
    () async {
      await customer();
      final before = repository.detail('REQ-1042');
      await repository.answerQuestion('REQ-1042', '規程集を使用します。個人情報は含みません。');
      final after = repository.detail('REQ-1042');
      expect(after.version, before.version + 1);
      expect(after.status, WorkStatus.reviewing);
      expect(after.question, isNull);
      expect(after.isPublished, isFalse);
      expect(after.complianceApproved, isFalse);
      expect(after.technicalApproved, isFalse);
      expect(after.messages.last.text, contains('個人情報は含みません'));
      await expectLater(
        repository.answerQuestion('REQ-1042', 'もう一度回答'),
        throwsA(errorCode('state_conflict')),
      );
      await provider();
      expect(repository.hall(query: 'REQ-1042'), isEmpty);
    },
  );

  test(
    'consultation stores a message without claiming or assigning the work',
    () async {
      await provider();
      await repository.consult('DEV-1036', '対応状況の項目について確認したいです。');
      final item = repository.detail('DEV-1036');
      expect(item.status, WorkStatus.published);
      expect(item.providerId, isNull);
      expect(item.messages.single.text, contains('確認したい'));
      expect(repository.hall(query: 'DEV-1036').single.messages, isEmpty);
      expect(
        repository.myRequests().any((item) => item.id == 'DEV-1036'),
        isFalse,
      );
      await expectLater(
        repository.submitDelivery('DEV-1036', delivery(1)),
        throwsA(errorCode('not_found')),
      );
      await expectLater(
        repository.sendMessage('DEV-1036', '未担当案件への共通メッセージ'),
        throwsA(errorCode('not_found')),
      );
    },
  );

  test(
    'unpublished deliveries remain internal even if client sets published=true',
    () async {
      await provider();
      await repository.submitDelivery('OPC-1028', delivery(1, published: true));
      expect(repository.detail('OPC-1028').status, WorkStatus.internalReview);
      expect(
        repository.detail('OPC-1028').deliveries.single.published,
        isFalse,
      );
      await customer();
      expect(repository.detail('OPC-1028').deliveries, isEmpty);
      expect(
        repository
            .myRequests()
            .firstWhere((item) => item.id == 'OPC-1028')
            .deliveries,
        isEmpty,
      );
      await expectLater(
        repository.acceptDelivery('OPC-1028', 1),
        throwsA(errorCode('state_conflict')),
      );
      await repository.simulateDeliveryPublication('OPC-1028');
      expect(repository.detail('OPC-1028').deliveries.single.published, isTrue);
      await repository.acceptDelivery('OPC-1028', 1);
      expect(repository.detail('OPC-1028').status, WorkStatus.completed);
      expect(
        repository.detail('OPC-1028').latestNote,
        contains('お支払いの処理は行われません'),
      );
    },
  );

  test(
    'revision needs a new delivery and rejects stale or unpublished versions',
    () async {
      await customer();
      await expectLater(
        repository.requestRevision('OPC-1017', 99, '検索を修正してください。'),
        throwsA(errorCode('version_conflict')),
      );
      await repository.requestRevision('OPC-1017', 1, '検索を修正してください。');
      expect(repository.detail('OPC-1017').status, WorkStatus.revision);
      await expectLater(
        repository.acceptDelivery('OPC-1017', 1),
        throwsA(errorCode('state_conflict')),
      );
      await provider();
      await expectLater(
        repository.submitDelivery('OPC-1017', delivery(1)),
        throwsA(errorCode('version_conflict')),
      );
      await repository.submitDelivery('OPC-1017', delivery(2));
      await customer();
      expect(
        repository.detail('OPC-1017').deliveries.map((item) => item.version),
        [1],
      );
      await repository.simulateDeliveryPublication('OPC-1017');
      await expectLater(
        repository.acceptDelivery('OPC-1017', 1),
        throwsA(errorCode('version_conflict')),
      );
      await repository.acceptDelivery('OPC-1017', 2);
      expect(repository.detail('OPC-1017').status, WorkStatus.completed);
      await expectLater(
        repository.acceptDelivery('OPC-1017', 2),
        throwsA(errorCode('state_conflict')),
      );
    },
  );

  test(
    'a duplicate concurrent delivery cannot create two committed versions',
    () async {
      await provider();
      final outcomes = await Future.wait([
        repository
            .submitDelivery('OPC-1028', delivery(1))
            .then<Object>((_) => true)
            .catchError((Object error) => error),
        repository
            .submitDelivery('OPC-1028', delivery(1))
            .then<Object>((_) => true)
            .catchError((Object error) => error),
      ]);
      expect(outcomes.where((outcome) => outcome == true).length, 1);
      expect(
        outcomes.whereType<RepositoryException>().single.code,
        'state_conflict',
      );
      expect(repository.detail('OPC-1028').deliveries.length, 1);
    },
  );

  test(
    'revoked internal access blocks hall, assigned data and new deliveries',
    () async {
      await provider();
      await repository.simulateAccountAccess(authorized: false);
      expect(repository.hall, throwsA(errorCode('provider_required')));
      expect(repository.myRequests, throwsA(errorCode('provider_required')));
      expect(
        () => repository.detail('OPC-1028'),
        throwsA(errorCode('provider_required')),
      );
      await expectLater(
        repository.submitDelivery('OPC-1028', delivery(1)),
        throwsA(errorCode('provider_required')),
      );
    },
  );

  test('suspended account loses access and cannot log in again', () async {
    await provider();
    await repository.simulateAccountAccess(active: false);
    expect(repository.hall, throwsA(errorCode('account_inactive')));
    await expectLater(
      repository.sendMessage('OPC-1028', 'メッセージ'),
      throwsA(errorCode('account_inactive')),
    );
    await repository.logout();
    await expectLater(
      repository.login('member@opc.demo', 'demo1234'),
      throwsA(errorCode('account_inactive')),
    );
  });

  test(
    'revoked provider cannot infer existence from detail error codes',
    () async {
      await provider();
      await repository.simulateAccountAccess(authorized: false);
      for (final id in ['REQ-1042', 'DEV-1036', 'OPC-1028', 'NONEXISTENT']) {
        expect(
          () => repository.detail(id),
          throwsA(errorCode('provider_required')),
        );
      }
    },
  );

  test(
    'an account switch invalidates a pending request from the old session',
    () async {
      await customer();
      final switchAccount = repository.register(
        '別のお客様',
        'another@example.jp',
        'password123',
      );
      final staleRequest = repository.submitRequest(
        RequestDraft(description: '元のアカウントで作成した業務システムのご相談です。'),
      );
      final rejected = expectLater(
        staleRequest,
        throwsA(errorCode('session_changed')),
      );
      await switchAccount;
      await rejected;
      expect(repository.myRequests(), isEmpty);
      await customer();
      expect(repository.myRequests().length, 3);
    },
  );

  test(
    'injected failure does not write and retry commits exactly once',
    () async {
      await customer();
      final count = repository.myRequests().length;
      repository.failNext = true;
      final draft = RequestDraft(description: 'お問い合わせを管理する仕組みを開発したいです。');
      await expectLater(
        repository.submitRequest(draft),
        throwsA(errorCode('network_unavailable')),
      );
      expect(repository.myRequests().length, count);
      expect(repository.failNext, isFalse);
      final item = await repository.submitRequest(draft);
      expect(item.id, 'REQ-1043');
      expect(repository.myRequests().length, count + 1);
    },
  );

  test(
    'invalid forms and mutable source markers fail before creating a delivery',
    () async {
      await customer();
      await expectLater(
        repository.submitRequest(RequestDraft(description: '短い')),
        throwsA(errorCode('invalid_description')),
      );
      await expectLater(
        repository.answerQuestion('REQ-1042', '  '),
        throwsA(errorCode('invalid_message')),
      );
      await provider();
      await expectLater(
        repository.submitDelivery('OPC-1028', delivery(1, ref: 'main')),
        throwsA(errorCode('source_not_fixed')),
      );
      expect(repository.detail('OPC-1028').deliveries, isEmpty);
    },
  );

  test(
    'returned collections cannot be mutated to bypass repository writes',
    () async {
      await customer();
      final item = repository.detail('REQ-1042');
      expect(() => item.messages.clear(), throwsUnsupportedError);
      expect(() => repository.myRequests().clear(), throwsUnsupportedError);
      final forged = item.copyWith(
        complianceApproved: true,
        technicalApproved: true,
        publishedVersion: 1,
      );
      expect(forged.isPublished, isTrue);
      expect(repository.detail('REQ-1042').isPublished, isFalse);
    },
  );

  test(
    'reset restores fixtures and removes registered accounts and drafts',
    () async {
      await repository.register('新規', 'new@example.jp', 'password123');
      await repository.saveDraft(RequestDraft(description: '保存中の内容'));
      await repository.reset();
      expect(repository.session, isNull);
      expect(repository.draft, isNull);
      await expectLater(
        repository.login('new@example.jp', 'password123'),
        throwsA(errorCode('invalid_credentials')),
      );
      await customer();
      expect(repository.myRequests().length, 3);
      expect(repository.detail('REQ-1042').status, WorkStatus.needsInfo);
    },
  );
}
