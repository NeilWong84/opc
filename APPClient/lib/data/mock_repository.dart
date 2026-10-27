import 'models.dart';
import 'reference_samples.dart';
import 'repository.dart';

/// In-memory, synthetic demo data. Nothing here authenticates against a server,
/// uploads files, performs a real review, or records a payment.
class MockOpcRepository implements OpcRepository {
  MockOpcRepository({
    this.delay = const Duration(milliseconds: 350),
    List<WorkItem> taskFixtures = const [],
  }) : _taskFixtures = List.unmodifiable(taskFixtures) {
    _seed();
  }

  final Duration delay;
  // Test/development fixtures still pass every ordinary read permission check.
  final List<WorkItem> _taskFixtures;
  bool failNext = false;
  UserSession? _session;
  final Map<String, _Account> _accounts = {};
  final Map<String, WorkItem> _items = {};
  final Map<String, RequestDraft> _drafts = {};
  final Map<String, List<ChatMessage>> _consultations = {};
  int _nextRequest = 1043;
  int _nextCustomer = 2;

  @override
  UserSession? get session => _session;

  @override
  RequestDraft? get draft {
    final current = _session;
    if (current == null ||
        !current.active ||
        current.role != UserRole.customer) {
      return null;
    }
    return _drafts[current.id];
  }

  Future<void> _wait() async {
    final initiatingSession = _session;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    } else {
      await Future<void>.value();
    }
    if (!identical(initiatingSession, _session)) {
      throw const RepositoryException(
        'session_changed',
        'アカウントの状態が変わりました。画面を開き直してください。',
      );
    }
    if (failNext) {
      failNext = false;
      throw const RepositoryException(
        'network_unavailable',
        'デモ通信に失敗しました。内容を確認して、もう一度お試しください。',
      );
    }
  }

  UserSession _signedIn() {
    final current = _session;
    if (current == null) {
      throw const RepositoryException('unauthenticated', 'ログインしてください。');
    }
    if (!current.active) {
      throw const RepositoryException('account_inactive', 'このアカウントは停止中です。');
    }
    return current;
  }

  UserSession _customer() {
    final current = _signedIn();
    if (current.role != UserRole.customer) {
      throw const RepositoryException(
        'customer_required',
        'お客様のアカウントでご利用ください。',
      );
    }
    return current;
  }

  UserSession _provider() {
    final current = _signedIn();
    if (current.role != UserRole.provider || !current.authorized) {
      throw const RepositoryException('provider_required', '有効な内部承接権限が必要です。');
    }
    return current;
  }

  WorkItem _find(String id) =>
      _items[id] ??
      (throw const RepositoryException('not_found', 'この案件を表示できません。'));

  WorkItem _owned(String id) {
    final current = _customer();
    final item = _find(id);
    if (item.ownerId != current.id) {
      throw const RepositoryException('not_found', 'この案件を表示できません。');
    }
    return item;
  }

  WorkItem _assigned(String id) {
    final current = _provider();
    final item = _find(id);
    if (item.providerId != current.id || !item.isPublished) {
      throw const RepositoryException('not_found', 'この案件を表示できません。');
    }
    return item;
  }

  bool _inHall(WorkItem item) =>
      item.isPublished &&
      item.status == WorkStatus.published &&
      item.providerId == null;

  List<TaskReference> _publishedReferences(WorkItem item) => List.unmodifiable(
    item.isPublished
        ? item.references.where(
            (reference) =>
                reference.publishedVersion > 0 &&
                reference.publishedVersion == item.publishedVersion,
          )
        : const <TaskReference>[],
  );

  WorkItem _providerView(WorkItem item) =>
      item.copyWith(references: _publishedReferences(item));

  WorkItem _customerView(WorkItem item) => item.copyWith(
    references: _publishedReferences(item),
    deliveries: item.deliveries
        .where((delivery) => delivery.published)
        .toList(),
  );

  WorkItem _hallView(WorkItem item, {bool includeOwnConsultation = false}) =>
      item.copyWith(
        clearQuestion: true,
        clearLatestNote: true,
        attachmentNames: const [],
        deliveries: const [],
        references: _publishedReferences(item),
        messages: includeOwnConsultation
            ? _consultations['${_session!.id}:${item.id}'] ?? const []
            : const [],
      );

  @override
  Future<UserSession> login(String email, String password) async {
    await _wait();
    final account = _accounts[email.trim().toLowerCase()];
    if (account == null || account.password != password) {
      throw const RepositoryException(
        'invalid_credentials',
        'メールアドレスまたはパスワードをご確認ください。',
      );
    }
    if (!account.user.active) {
      throw const RepositoryException('account_inactive', 'このアカウントは停止中です。');
    }
    return _session = account.user;
  }

  @override
  Future<UserSession> register(
    String name,
    String email,
    String password,
  ) async {
    await _wait();
    final normalizedEmail = email.trim().toLowerCase();
    if (name.trim().isEmpty || name.trim().length > 80) {
      throw const RepositoryException('invalid_name', 'お名前を80文字以内で入力してください。');
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
      throw const RepositoryException('invalid_email', '有効なメールアドレスを入力してください。');
    }
    if (password.length < 8) {
      throw const RepositoryException(
        'invalid_password',
        'パスワードは8文字以上で入力してください。',
      );
    }
    if (_accounts.containsKey(normalizedEmail)) {
      throw const RepositoryException('email_exists', 'このメールアドレスは登録済みです。');
    }
    final user = UserSession(
      id: 'customer-${_nextCustomer++}',
      name: name.trim(),
      email: normalizedEmail,
      role: UserRole.customer,
    );
    _accounts[normalizedEmail] = _Account(user, password);
    return _session = user;
  }

  @override
  Future<void> logout() async {
    await _wait();
    _session = null;
  }

  @override
  List<WorkItem> myRequests() {
    final current = _signedIn();
    if (current.role == UserRole.provider) {
      _provider();
      return List.unmodifiable(
        _items.values
            .where((item) => item.providerId == current.id && item.isPublished)
            .map(_providerView),
      );
    }
    return List.unmodifiable(
      _items.values
          .where((item) => item.ownerId == current.id)
          .map(_customerView),
    );
  }

  @override
  List<WorkItem> hall({String query = '', String category = 'すべて'}) {
    _provider();
    final normalizedQuery = query.trim().toLowerCase();
    return List.unmodifiable(
      _items.values
          .where(_inHall)
          .where((item) => category == 'すべて' || item.category == category)
          .where(
            (item) => '${item.id} ${item.title} ${item.description}'
                .toLowerCase()
                .contains(normalizedQuery),
          )
          .map((item) => _hallView(item)),
    );
  }

  @override
  WorkItem detail(String id) {
    final current = _signedIn();
    if (current.role == UserRole.provider) _provider();
    final item = _find(id);
    if (current.role == UserRole.customer) {
      if (item.ownerId == current.id) return _customerView(item);
    } else {
      if (item.providerId == current.id && item.isPublished) {
        return _providerView(item);
      }
      if (_inHall(item)) return _hallView(item, includeOwnConsultation: true);
    }
    throw const RepositoryException('not_found', 'この案件を表示できません。');
  }

  @override
  List<TaskReference> references(String taskId) => detail(taskId).references;

  @override
  TaskReference reference(String taskId, String referenceId) {
    final visible = references(taskId);
    for (final reference in visible) {
      if (reference.id == referenceId) return reference;
    }
    // An absent, private or old-version reference is indistinguishable here.
    throw const RepositoryException('not_found', 'この資料を表示できません。');
  }

  @override
  Future<TaskReference> prepareReference(
    String taskId,
    String referenceId,
  ) async {
    final initial = reference(taskId, referenceId);
    await _wait();
    final current = reference(taskId, referenceId);
    if (current.publishedVersion != initial.publishedVersion) {
      throw const RepositoryException('version_conflict', '公開中の資料を確認してください。');
    }
    if (current.previewState == ReferencePreviewState.ready ||
        current.previewState == ReferencePreviewState.unsupported) {
      return current;
    }
    final prepared = current.copyWith(
      previewState: ReferencePreviewState.ready,
    );
    _replaceReference(taskId, prepared);
    return prepared;
  }

  void _replaceReference(String taskId, TaskReference updated) {
    final item = _find(taskId);
    _items[taskId] = item.copyWith(
      references: [
        for (final existing in item.references)
          if (existing.id == updated.id) updated else existing,
      ],
    );
  }

  /// Development-only preview state control, with the same access checks as a
  /// normal preview. It cannot reveal a private or old-version reference.
  Future<void> simulateReferenceState(
    String taskId,
    String referenceId,
    ReferencePreviewState state,
  ) async {
    reference(taskId, referenceId);
    await _wait();
    final current = reference(taskId, referenceId);
    _replaceReference(taskId, current.copyWith(previewState: state));
  }

  /// Test a previously visible reference being withdrawn during a preview.
  /// This cannot promote an inaccessible reference or publish a task.
  Future<void> simulateReferenceWithdrawal(
    String taskId,
    String referenceId,
  ) async {
    reference(taskId, referenceId);
    await _wait();
    final current = reference(taskId, referenceId);
    _replaceReference(taskId, current.copyWith(publishedVersion: 0));
  }

  @override
  Future<WorkItem> submitRequest(RequestDraft request) async {
    await _wait();
    final current = _customer();
    final description = request.description.trim();
    if (description.length < 10 || description.length > 4000) {
      throw const RepositoryException(
        'invalid_description',
        'ご相談内容を10〜4,000文字で入力してください。',
      );
    }
    if (request.timing.trim().isEmpty || request.budget.trim().isEmpty) {
      throw const RepositoryException(
        'invalid_request',
        '希望時期とご予算の意向を選んでください。',
      );
    }
    _validateAttachments(request);
    final firstLine =
        description
            .split(RegExp(r'[。\n！？!?]'))
            .where((line) => line.trim().isNotEmpty)
            .firstOrNull
            ?.trim() ??
        description;
    final title = firstLine.length > 30
        ? '${firstLine.substring(0, 30)}…'
        : firstLine;
    final item = WorkItem(
      id: 'REQ-${_nextRequest++}',
      title: title,
      description: description,
      category: 'AI システム開発',
      duration: request.timing.trim(),
      status: WorkStatus.reviewing,
      ownerId: current.id,
      budget: request.budget.trim(),
      createdAt: DateTime.now().toUtc(),
      attachmentNames: request.attachmentNames,
      latestNote: '運営が用途の確認と技術整理を行います。案件一覧にはまだ公開されません。',
      messages: [
        ChatMessage(
          author: current.name,
          text: description,
          sentAt: DateTime.now().toUtc(),
        ),
      ],
    );
    _items[item.id] = item;
    _drafts.remove(current.id);
    return item;
  }

  void _validateAttachments(RequestDraft request) {
    if (request.attachmentNames.length > 5 ||
        request.attachmentNames.any((name) => name.trim().isEmpty)) {
      throw const RepositoryException(
        'invalid_attachments',
        '添付資料は5件以内で指定してください。',
      );
    }
  }

  @override
  Future<void> saveDraft(RequestDraft request) async {
    await _wait();
    final current = _customer();
    if (request.description.length > 4000) {
      throw const RepositoryException(
        'invalid_description',
        'ご相談内容は4,000文字以内で入力してください。',
      );
    }
    _validateAttachments(request);
    _drafts[current.id] = request;
  }

  String _validText(String text) {
    final value = text.trim();
    if (value.isEmpty || value.length > 4000) {
      throw const RepositoryException(
        'invalid_message',
        '内容を1〜4,000文字で入力してください。',
      );
    }
    return value;
  }

  ChatMessage _message(String text) => ChatMessage(
    author: _session!.name,
    text: text,
    sentAt: DateTime.now().toUtc(),
  );

  @override
  Future<void> answerQuestion(String id, String text) async {
    await _wait();
    final item = _owned(id);
    if (item.status != WorkStatus.needsInfo) {
      throw const RepositoryException('state_conflict', '現在、回答待ちの質問はありません。');
    }
    final answer = _validText(text);
    _items[id] = item.copyWith(
      status: WorkStatus.reviewing,
      version: item.version + 1,
      clearPublication: true,
      complianceApproved: false,
      technicalApproved: false,
      clearQuestion: true,
      latestNote: 'ご回答を受け付けました。運営が再確認しています。',
      messages: [...item.messages, _message(answer)],
    );
  }

  @override
  Future<void> consult(String id, String text) async {
    await _wait();
    final current = _provider();
    final item = _find(id);
    if (!_inHall(item)) {
      throw const RepositoryException('not_found', 'この案件を表示できません。');
    }
    final key = '${current.id}:$id';
    _consultations[key] = [
      ...(_consultations[key] ?? const []),
      _message(_validText(text)),
    ];
    // Consultation intentionally does not assign a provider or change status.
  }

  @override
  Future<void> sendMessage(String id, String text) async {
    await _wait();
    final current = _signedIn();
    final item = current.role == UserRole.customer ? _owned(id) : _assigned(id);
    final message = _message(_validText(text));
    _items[id] = item.copyWith(messages: [...item.messages, message]);
  }

  @override
  Future<void> submitDelivery(String id, Delivery delivery) async {
    await _wait();
    final item = _assigned(id);
    if (item.status != WorkStatus.developing &&
        item.status != WorkStatus.revision) {
      throw const RepositoryException('state_conflict', '現在は成果物を提出できません。');
    }
    final nextVersion = item.deliveries.isEmpty
        ? 1
        : item.deliveries.last.version + 1;
    if (delivery.version != nextVersion) {
      throw const RepositoryException(
        'version_conflict',
        '最新版を読み込み、提出し直してください。',
      );
    }
    if (delivery.sourceName.trim().isEmpty ||
        delivery.sourceRef.trim().isEmpty ||
        delivery.guideName.trim().isEmpty ||
        delivery.testName.trim().isEmpty ||
        delivery.note.trim().isEmpty) {
      throw const RepositoryException(
        'invalid_delivery',
        '固定ソース・操作説明・テスト資料・提出コメントを入力してください。',
      );
    }
    if (RegExp(
      r'^(main|master|head|latest)$',
      caseSensitive: false,
    ).hasMatch(delivery.sourceRef.trim())) {
      throw const RepositoryException(
        'source_not_fixed',
        'ソースの固定バージョンまたはチェックサムを指定してください。',
      );
    }
    _items[id] = item.copyWith(
      status: WorkStatus.internalReview,
      latestNote: '提出された成果物を運営が確認しています。',
      deliveries: [...item.deliveries, delivery.copyWith(published: false)],
    );
  }

  WorkItem _acceptanceItem(String id, int version) {
    final item = _owned(id);
    if (item.status != WorkStatus.awaitingAcceptance) {
      throw const RepositoryException('state_conflict', '現在は検収待ちではありません。');
    }
    if (item.deliveries.isEmpty ||
        !item.deliveries.last.published ||
        item.deliveries.last.version != version) {
      throw const RepositoryException(
        'version_conflict',
        '公開中の最新納品バージョンを確認してください。',
      );
    }
    return item;
  }

  @override
  Future<void> requestRevision(String id, int version, String text) async {
    await _wait();
    final item = _acceptanceItem(id, version);
    final feedback = _validText(text);
    _items[id] = item.copyWith(
      status: WorkStatus.revision,
      latestNote: '修正のご依頼を受け付けました。運営が内容を確認します。',
      messages: [...item.messages, _message('納品 v$version への修正依頼：$feedback')],
    );
  }

  @override
  Future<void> acceptDelivery(String id, int version) async {
    await _wait();
    final item = _acceptanceItem(id, version);
    _items[id] = item.copyWith(
      status: WorkStatus.completed,
      latestNote: '納品 v$version の検収が完了しました。お支払いの処理は行われません。',
      messages: [...item.messages, _message('納品 v$version の検収を完了しました。')],
    );
  }

  /// Developer scenario control only, intentionally absent from OpcRepository.
  /// This emulates the two review results; it never represents a real review.
  Future<void> simulateReview(String id, {bool approve = true}) async {
    await _wait();
    final item = _find(id);
    if (item.status != WorkStatus.reviewing &&
        item.status != WorkStatus.needsInfo) {
      throw const RepositoryException('state_conflict', 'このデモ案件は審査中ではありません。');
    }
    _items[id] = item.copyWith(
      status: approve ? WorkStatus.published : WorkStatus.needsInfo,
      publishedVersion: approve ? item.version : null,
      clearPublication: !approve,
      complianceApproved: approve,
      technicalApproved: approve,
      clearQuestion: approve,
      question: approve ? null : '利用する資料の種類と、利用権限について教えてください。',
      latestNote: approve
          ? 'デモ操作：用途確認・技術整理が完了し、このバージョンを案件一覧に公開しました。'
          : 'デモ操作：運営から確認事項が届いています。',
    );
  }

  /// Developer scenario control; a real backend must authorize and audit this.
  Future<void> simulateDeliveryPublication(String id) async {
    await _wait();
    final item = _find(id);
    if (item.status != WorkStatus.internalReview || item.deliveries.isEmpty) {
      throw const RepositoryException('state_conflict', '内部確認中の成果物がありません。');
    }
    _items[id] = item.copyWith(
      status: WorkStatus.awaitingAcceptance,
      deliveries: [
        ...item.deliveries.take(item.deliveries.length - 1),
        item.deliveries.last.copyWith(published: true),
      ],
      latestNote: 'デモ操作：内部確認を終え、納品内容をお客様に公開しました。',
    );
  }

  /// Allows deterministic tests of account suspension and revoked access.
  /// This method is deliberately not part of the production adapter interface.
  Future<void> simulateAccountAccess({bool? active, bool? authorized}) async {
    await _wait();
    final old = _session;
    if (old == null) {
      throw const RepositoryException('unauthenticated', 'ログインしてください。');
    }
    final updated = UserSession(
      id: old.id,
      name: old.name,
      email: old.email,
      role: old.role,
      active: active ?? old.active,
      authorized: authorized ?? old.authorized,
    );
    _session = updated;
    _accounts[old.email] = _Account(updated, _accounts[old.email]!.password);
  }

  @override
  Future<void> reset() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    _seed();
  }

  void _seed() {
    _session = null;
    failNext = false;
    _nextRequest = 1043;
    _nextCustomer = 2;
    _accounts.clear();
    _items.clear();
    _drafts.clear();
    _consultations.clear();
    const customer = UserSession(
      id: 'customer-1',
      name: '田中',
      email: 'customer@opc.demo',
      role: UserRole.customer,
    );
    const provider = UserSession(
      id: 'provider-1',
      name: '佐藤',
      email: 'member@opc.demo',
      role: UserRole.provider,
      authorized: true,
    );
    _accounts[customer.email] = const _Account(customer, 'demo1234');
    _accounts[provider.email] = const _Account(provider, 'demo1234');
    final date = DateTime.utc(2026, 10, 12, 5, 20);
    final fixtures = [
      WorkItem(
        id: 'REQ-1042',
        title: '社内資料を探せる AI FAQ',
        description: '社内マニュアルや規程を探し、質問への回答と根拠となる資料を確認できる仕組みを作りたいです。',
        category: 'AI システム開発',
        duration: '相談して決めたい',
        status: WorkStatus.needsInfo,
        ownerId: customer.id,
        createdAt: date,
        question: '社内資料には個人情報が含まれますか？ 利用する資料の種類と、利用権限について教えてください。',
        latestNote: '運営から確認事項が届いています。まだ案件一覧には公開されていません。',
        messages: [
          ChatMessage(
            author: 'OPC 運営',
            text: '社内資料の種類と、個人情報が含まれるかを教えてください。',
            sentAt: date,
          ),
        ],
      ),
      WorkItem(
        id: 'OPC-1028',
        title: '社内 FAQ システム',
        description: '社内資料を検索し、根拠となる資料を表示しながら回答できる FAQ システムを開発します。',
        category: 'AI システム開発',
        duration: '10月16日 デモ確認',
        status: WorkStatus.developing,
        ownerId: customer.id,
        providerId: provider.id,
        version: 2,
        publishedVersion: 2,
        complianceApproved: true,
        technicalApproved: true,
        createdAt: date.subtract(const Duration(days: 4)),
        latestNote: '次の予定：10月16日 デモ確認',
        messages: [
          ChatMessage(
            author: 'OPC 運営',
            text: 'デモでは、回答の根拠となる資料も表示できるか確認します。',
            sentAt: date,
          ),
        ],
      ),
      WorkItem(
        id: 'OPC-1017',
        title: 'お問い合わせ管理ツール',
        description: '問い合わせを登録・検索し、担当者と対応状況を更新できる Web ツールです。',
        category: 'Web アプリ',
        duration: '3〜4週間',
        status: WorkStatus.awaitingAcceptance,
        ownerId: customer.id,
        providerId: provider.id,
        publishedVersion: 1,
        complianceApproved: true,
        technicalApproved: true,
        createdAt: date.subtract(const Duration(days: 12)),
        latestNote: 'お客様向け公開版 v1.0.0・10月12日',
        deliveries: const [
          Delivery(
            version: 1,
            sourceName: 'opc-inquiry-v1.0.0.zip',
            sourceRef: 'demo-sha256:ab6312f9a264ee89000e5b377d076925',
            guideName: '操作説明書-v1.0.pdf',
            testName: 'テスト結果-v1.0.pdf',
            note: 'デモ用の納品情報です。問い合わせの登録・検索、担当者と対応状況の更新をご確認ください。',
            published: true,
          ),
        ],
        messages: [
          ChatMessage(
            author: 'OPC 運営',
            text: '納品内容を公開しました。操作説明書と確認項目をご確認ください。',
            sentAt: date,
          ),
        ],
      ),
      WorkItem(
        id: 'DEV-1036',
        title: 'お問い合わせ管理ツール',
        description: '問い合わせを一元管理し、対応状況を共有できる Web ツール。',
        category: 'Web アプリ',
        duration: '3〜4週間',
        status: WorkStatus.published,
        ownerId: 'demo-client-2',
        version: 3,
        publishedVersion: 3,
        complianceApproved: true,
        technicalApproved: true,
        references: inquiryReferenceSamples(),
        createdAt: date.subtract(const Duration(hours: 1)),
      ),
      WorkItem(
        id: 'DEV-1039',
        title: '見積書作成の自動化',
        description: '入力内容から見積書を作成し、PDF で出力する業務システム。',
        category: '業務自動化',
        duration: '2〜3週間',
        status: WorkStatus.published,
        ownerId: 'demo-client-3',
        publishedVersion: 1,
        complianceApproved: true,
        technicalApproved: true,
        references: quoteReferenceSamples(),
        createdAt: date.subtract(const Duration(hours: 2)),
      ),
    ];
    for (final item in fixtures) {
      _items[item.id] = item;
    }
    for (final item in _taskFixtures) {
      _items[item.id] = item;
    }
  }
}

class _Account {
  const _Account(this.user, this.password);
  final UserSession user;
  final String password;
}
