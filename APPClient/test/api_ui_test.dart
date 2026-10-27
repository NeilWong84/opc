import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_config.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/core/theme.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/data/repository.dart';
import 'package:opc_app/features/api_workspace.dart';
import 'package:opc_app/features/auth_page.dart';
import 'package:opc_app/l10n/app_localizations.dart';
import 'package:opc_app/main.dart';

WorkItem record({
  bool pending = false,
  String state = 'executing',
  List<Delivery> deliveries = const [],
}) => WorkItem(
  id: 'request-1',
  title: '顧客原文の予約システム',
  description: '预约系统：保留客户原文，不翻译业务资料。',
  category: 'development',
  duration: '2026年11月',
  status: state == 'awaiting_acceptance'
      ? WorkStatus.awaitingAcceptance
      : WorkStatus.developing,
  ownerId: 'customer-1',
  providerId: 'provider-1',
  createdAt: DateTime.utc(2026, 10, 16),
  publicCode: 'REQ-9001',
  engagementId: 'engagement-1',
  pendingConfirmation: pending,
  agreementVersion: 2,
  agreementTerms: '双方合意の条款原文',
  intakeState: state,
  scope: const {
    'included_scope': '入力と保存',
    'excluded_scope': '決済は含まない',
    'deliverables': ['ソースコード', '操作手順'],
    'acceptance_criteria': ['保存できる'],
    'revision_terms': '合意範囲の修正1回',
  },
  deliveries: deliveries,
);

class LiveUiRepository extends MockOpcRepository
    implements RemoteOpcRepository {
  LiveUiRepository() : super(delay: Duration.zero);
  UserSession? user = const UserSession(
    id: 'customer-1',
    name: '実在のテスト顧客',
    email: 'customer@example.jp',
    role: UserRole.customer,
  );
  WorkItem item = record();
  RequestDraft? saved;
  RequestDraft? submitted;
  Delivery? delivery;
  bool offline = false;
  bool failDelivery = false;
  bool confirmed = false;
  int accepted = 0;
  int metadataReads = 0;
  final List<String> sent = [];
  final List<String> answers = [];
  bool notificationRead = false;
  bool expireOnFileRead = false;
  @override
  UserSession? get session => user;
  @override
  Future<RequestClassifications> requestClassifications() async =>
      const RequestClassifications();
  @override
  RequestDraft? get draft => saved;
  @override
  Future<void> logout() async {
    user = null;
  }

  @override
  Future<void> refresh() async {
    if (offline) {
      throw const RepositoryException('network_unavailable', 'Offline');
    }
  }

  @override
  List<WorkItem> myRequests() {
    if (offline) {
      throw const RepositoryException('network_unavailable', 'Offline');
    }
    return [item];
  }

  @override
  List<WorkItem> conversationRequests() => myRequests();
  @override
  List<NegotiationThread> negotiations(String id) => [];
  @override
  Future<String> startNegotiation(String id) async => 'negotiation-1';
  @override
  Future<Negotiation> negotiation(String threadId) =>
      throw UnimplementedError();
  @override
  Future<void> proposeClaim(
    Negotiation negotiation,
    String terms,
    int? amount,
    DateTime? dueAt,
  ) async {}
  @override
  Future<void> confirmClaim(Negotiation negotiation) async {}
  @override
  Future<void> claimProject(Negotiation negotiation) async {}
  @override
  Future<void> sendNegotiationMessage(String threadId, String text) async {}

  @override
  List<WorkItem> hall({String query = '', String category = 'すべて'}) => [item];
  @override
  WorkItem detail(String id) => item;
  @override
  Future<WorkItem> refreshItem(String id) async {
    await refresh();
    return item;
  }

  @override
  Future<void> saveDraft(RequestDraft request) async {
    saved = request;
  }

  @override
  Future<WorkItem> submitRequest(RequestDraft request) async {
    submitted = request;
    return item;
  }

  @override
  Future<void> submitDelivery(String id, Delivery value) async {
    delivery = value;
    if (failDelivery) {
      throw const RepositoryException('version_conflict', 'Changed');
    }
  }

  @override
  Future<void> confirmAgreement(String id) async {
    confirmed = true;
  }

  @override
  Future<void> sendMessage(String id, String text) async {
    sent.add(text);
  }

  @override
  Future<void> answerQuestion(String id, String text) async {
    answers.add(text);
  }

  @override
  Future<void> acceptDelivery(String id, int version) async {
    accepted = version;
  }

  @override
  List<AppNotification> notifications() {
    if (offline) {
      throw const RepositoryException('network_unavailable', 'Offline');
    }
    return [
      AppNotification(
        id: 'notice-1',
        templateKey: 'delivery.published',
        createdAt: DateTime.utc(2026, 10, 16),
        readAt: notificationRead ? DateTime.utc(2026, 10, 16) : null,
      ),
    ];
  }

  @override
  Future<void> markNotificationRead(String id) async {
    notificationRead = true;
  }

  @override
  Future<RemoteFile> uploadFile(String name, Uint8List bytes) async =>
      RemoteFile(id: 'upload-1', name: name, sizeBytes: bytes.length);
  @override
  Future<RemoteFile> fileMetadata(String id) async {
    metadataReads++;
    if (expireOnFileRead) {
      user = null;
      throw const RepositoryException('unauthenticated', 'Expired');
    }
    if (user == null || offline) {
      throw const RepositoryException('not_found', 'Not accessible');
    }
    return RemoteFile(
      id: id,
      name: '顧客の秘密.txt',
      sizeBytes: 20,
      mediaType: 'text/plain',
      scanStatus: 'clean',
    );
  }

  @override
  Future<Uint8List> downloadFile(String id) async =>
      Uint8List.fromList([1, 2, 3]);
  @override
  Future<RemotePreview> previewFile(String id) async => const RemotePreview(
    state: ReferencePreviewState.ready,
    mediaType: 'text/plain',
    text: '顧客の秘密の内容',
    truncated: true,
  );
}

Widget host(
  AppController app,
  Widget child, {
  Brightness brightness = Brightness.light,
}) => AnimatedBuilder(
  animation: app,
  builder: (context, _) => MaterialApp(
    locale: app.locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: opcTheme(brightness),
    home: child,
  ),
);

Future<void> tapKey(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'API configuration never defaults to Mock and release enforces HTTPS',
    () {
      expect(const AppConfig().isConfigured, isFalse);
      expect(const AppConfig().useMock, isFalse);
      expect(
        const AppConfig(baseUrl: 'http://127.0.0.1:8001').isConfigured,
        isTrue,
      );
      expect(
        const AppConfig(baseUrl: 'http://192.168.1.2:8001').isConfigured,
        isFalse,
      );
      expect(
        const AppConfig(
          baseUrl: 'http://127.0.0.1:8001',
          release: true,
        ).isConfigured,
        isFalse,
      );
      expect(
        const AppConfig(
          baseUrl: 'https://api.example.jp',
          release: true,
        ).isConfigured,
        isTrue,
      );
      expect(
        const AppConfig(
          baseUrl: 'https://user:pass@api.example.jp',
        ).isConfigured,
        isFalse,
      );
      expect(
        const AppConfig(environment: 'mock', release: true).useMock,
        isFalse,
      );
      expect(
        const AppConfig(
          environment: 'mock',
          release: true,
          explicitDemo: true,
        ).useMock,
        isTrue,
      );
    },
  );

  testWidgets(
    'live login hides sample credentials and keeps both language options',
    (tester) async {
      final app = AppController(LiveUiRepository());
      addTearDown(app.dispose);
      await tester.pumpWidget(host(app, AuthPage(app: app)));
      await tester.pumpAndSettle();
      expect(find.text('デモアカウント'), findsNothing);
      expect(find.text('customer@opc.demo'), findsNothing);
      expect(find.byKey(const Key('login-email')), findsOneWidget);
      expect(find.byKey(const Key('login-password')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real request persists pending file ID and exact customer input',
    (tester) async {
      final repo = LiveUiRepository();
      repo.saved = RequestDraft(
        description: '客户真实描述：开发预约与变更系统。',
        timing: '2026-11-15',
        budget: 'JPY 相談',
        files: const [
          RemoteFile(id: 'pending-upload', name: '私有資料.txt', sizeBytes: 28),
        ],
      );
      final app = AppController(repo);
      addTearDown(app.dispose);
      await tester.pumpWidget(host(app, ApiRequestPage(app: app)));
      await tester.pumpAndSettle();
      await tapKey(tester, 'api-submit-request');
      expect(repo.submitted!.description, '客户真实描述：开发预约与变更系统。');
      expect(repo.submitted!.files.single.id, 'pending-upload');
      expect(repo.submitted!.files.single.scanStatus, 'pending');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('request validation blocks missing timing and budget', (
    tester,
  ) async {
    final repo = LiveUiRepository();
    final app = AppController(repo);
    addTearDown(app.dispose);
    await tester.pumpWidget(host(app, ApiRequestPage(app: app)));
    await tester.enterText(
      find.byKey(const Key('api-request-description')),
      '予約管理のための開発を依頼します。',
    );
    await tapKey(tester, 'api-submit-request');
    expect(repo.submitted, isNull);
    expect(find.text('入力してください'), findsOneWidget);
    expect(find.text('希望完了日を選択してください'), findsWidgets);
  });

  testWidgets('an incomplete request can be saved as a server draft', (
    tester,
  ) async {
    final repo = LiveUiRepository();
    final app = AppController(repo);
    addTearDown(app.dispose);
    await tester.pumpWidget(host(app, ApiRequestPage(app: app)));
    await tester.enterText(
      find.byKey(const Key('api-request-description')),
      '待整理',
    );
    await tapKey(tester, 'api-save-draft');
    expect(repo.saved!.description, '待整理');
    expect(repo.saved!.timing, isEmpty);
    expect(repo.submitted, isNull);
  });

  testWidgets(
    'repository delivery includes archive evidence and conflict retains fields',
    (tester) async {
      final repo = LiveUiRepository()..failDelivery = true;
      final app = AppController(repo);
      addTearDown(app.dispose);
      await tester.pumpWidget(
        host(app, ApiDeliveryPage(app: app, id: 'request-1')),
      );
      await tester.enterText(
        find.byKey(const Key('api-source-repository')),
        'https://example.jp/customer/source',
      );
      await tester.enterText(
        find.byKey(const Key('api-source-commit')),
        'a' * 40,
      );
      await tester.enterText(
        find.byKey(const Key('api-source-archive-ref')),
        '顧客が取得できる固定アーカイブの証跡',
      );
      await tester.enterText(
        find.byKey(const Key('api-delivery-guide')),
        '導入と操作の実際の手順',
      );
      await tester.enterText(
        find.byKey(const Key('api-delivery-tests')),
        'pytest: 12 passed',
      );
      await tester.enterText(
        find.byKey(const Key('api-delivery-note')),
        '固定バージョンの納品',
      );
      await tapKey(tester, 'api-submit-delivery');
      expect(repo.delivery!.sourceArchiveRef, '顧客が取得できる固定アーカイブの証跡');
      expect(repo.delivery!.sourceRef, 'a' * 40);
      expect(repo.delivery!.sourceFileId, isNull);
      expect(find.textContaining('最新バージョン'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('api-delivery-note')))
            .controller!
            .text,
        '固定バージョンの納品',
      );
    },
  );

  testWidgets(
    'agreement renders complete scope and records explicit confirmation only',
    (tester) async {
      final repo = LiveUiRepository()
        ..item = record(pending: true, state: 'pending_confirmation');
      final app = AppController(repo);
      addTearDown(app.dispose);
      await tester.pumpWidget(
        host(app, ApiWorkPage(app: app, id: 'request-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('入力と保存'), findsOneWidget);
      expect(find.text('決済は含まない'), findsOneWidget);
      expect(find.text('保存できる'), findsOneWidget);
      expect(find.text('合意範囲の修正1回'), findsOneWidget);
      await tapKey(tester, 'api-confirm-agreement');
      expect(repo.confirmed, isFalse);
      await tapKey(tester, 'api-confirm-dialog');
      expect(repo.confirmed, isTrue);
    },
  );

  testWidgets('latest published delivery is accepted after confirmation', (
    tester,
  ) async {
    const delivery = Delivery(
      version: 4,
      sourceName: 'source.zip',
      sourceRef: '',
      guideName: '操作原文',
      testName: 'テスト原文',
      note: '納品原文',
      published: true,
    );
    final repo = LiveUiRepository()
      ..item = record(state: 'awaiting_acceptance', deliveries: [delivery]);
    final app = AppController(repo);
    addTearDown(app.dispose);
    await tester.pumpWidget(host(app, ApiWorkPage(app: app, id: 'request-1')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'api-accept-delivery');
    expect(repo.accepted, 0);
    await tapKey(tester, 'api-confirm-dialog');
    expect(repo.accepted, 4);
  });

  testWidgets('messages submit exact original text', (tester) async {
    final repo = LiveUiRepository();
    final app = AppController(repo);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      host(app, ApiWorkPage(app: app, id: 'request-1', showMessages: true)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-message-input')),
      '中文と日本語の原文です',
    );
    await tapKey(tester, 'api-message-send');
    expect(repo.sent.single, '中文と日本語の原文です');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-message-input')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('customer can answer a clarification during active cooperation', (
    tester,
  ) async {
    final repo = LiveUiRepository()
      ..item = record().copyWith(question: '新しい要件を確認してください');
    final app = AppController(repo);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      host(app, ApiWorkPage(app: app, id: 'request-1', showMessages: true)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-message-input')),
      '追加要件への正式な回答',
    );
    await tapKey(tester, 'api-message-send');
    expect(repo.answers.single, '追加要件への正式な回答');
    expect(repo.sent, isEmpty);
  });

  testWidgets('file preview is cleared immediately when session expires', (
    tester,
  ) async {
    final repo = LiveUiRepository();
    final app = AppController(repo);
    addTearDown(app.dispose);
    await tester.pumpWidget(host(app, ApiFilePage(app: app, fileId: 'file-1')));
    await tester.pumpAndSettle();
    expect(find.text('顧客の秘密の内容'), findsOneWidget);
    expect(find.textContaining('一部のみ'), findsOneWidget);
    await app.run(repo.logout);
    await tester.pumpAndSettle();
    expect(find.text('顧客の秘密の内容'), findsNothing);
    expect(find.text('顧客の秘密.txt'), findsNothing);
    expect(find.byKey(const Key('api-file-download')), findsNothing);
  });

  testWidgets(
    'workspace and notification reads fail into retry UI, never a red screen',
    (tester) async {
      final repo = LiveUiRepository()..offline = true;
      final app = AppController(repo);
      addTearDown(app.dispose);
      await tester.pumpWidget(host(app, ApiWorkspace(app: app)));
      await tester.pumpAndSettle();
      expect(find.textContaining('サーバーに接続できません'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(host(app, ApiNotificationsPage(app: app)));
      await tester.pumpAndSettle();
      expect(find.textContaining('サーバーに接続できません'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('file HTTP session expiry returns the application to login', (
    tester,
  ) async {
    final repo = LiveUiRepository();
    final app = AppController(repo);
    addTearDown(app.dispose);
    await tester.pumpWidget(OpcApp(controller: app));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ApiWorkspace));
    repo.expireOnFileRead = true;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApiFilePage(app: app, fileId: 'file-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.byType(ApiFilePage), findsNothing);
    expect(find.text('顧客の秘密の内容'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real server notification key is localized and mark-read updates',
    (tester) async {
      final repo = LiveUiRepository();
      final app = AppController(repo);
      addTearDown(app.dispose);
      await app.setLocale(const Locale('zh'));
      await tester.pumpWidget(host(app, ApiNotificationsPage(app: app)));
      await tester.pumpAndSettle();
      expect(find.text('待验收'), findsOneWidget);
      expect(find.text('delivery.published'), findsNothing);
      await tester.tap(find.text('标记已读'));
      await tester.pumpAndSettle();
      expect(repo.notificationRead, isTrue);
      expect(find.text('标记已读'), findsNothing);
    },
  );

  for (final language in ['ja', 'zh']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'live workspace respects $language $brightness at mobile dimensions',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final app = AppController(LiveUiRepository());
          addTearDown(app.dispose);
          await app.setLocale(Locale(language));
          await tester.pumpWidget(
            host(app, ApiWorkspace(app: app), brightness: brightness),
          );
          await tester.pumpAndSettle();
          expect(find.text('顧客原文の予約システム'), findsOneWidget);
          await tester.tap(find.byKey(const Key('tab-3')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('api-logout')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
