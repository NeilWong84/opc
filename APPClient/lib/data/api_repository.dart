import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'models.dart';
import 'repository.dart';

typedef Json = Map<String, dynamic>;

class _PendingCommand {
  _PendingCommand(this.key, this.body);
  final String key;
  final Json body;
}

/// PostgreSQL-backed mobile adapter. Reads are an explicitly refreshed snapshot;
/// no Mock records or synthetic success enter the live repository.
class ApiOpcRepository implements RemoteOpcRepository {
  ApiOpcRepository({
    required String baseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  }) {
    _api = OpcApiClient(
      baseUrl: baseUrl,
      client: client,
      timeout: timeout,
      onUnauthorized: _clearSession,
    );
  }

  late final OpcApiClient _api;
  UserSession? _session;
  RequestDraft? _draft;
  int _draftVersion = 0;
  int _epoch = 0;
  int _refreshRevision = 0;
  RepositoryException? _readError;
  final Map<String, RepositoryException> _itemReadErrors = {};
  final Set<String> _freshItems = {};
  Map<String, WorkItem> _items = {};
  Set<String> _mine = {};
  Set<String> _hall = {};
  List<AppNotification> _notifications = [];
  Map<String, Json> _requestJson = {};
  Map<String, List<Json>> _threads = {};
  final Map<String, _PendingCommand> _pending = {};
  final Map<String, String> _messageKeys = {};

  @override
  UserSession? get session => _session;
  @override
  RequestDraft? get draft => _draft;

  void _clearSession() {
    _epoch++;
    _session = null;
    _draft = null;
    _draftVersion = 0;
    _items = {};
    _mine = {};
    _hall = {};
    _notifications = [];
    _requestJson = {};
    _threads = {};
    _pending.clear();
    _messageKeys.clear();
    _readError = null;
    _itemReadErrors.clear();
    _freshItems.clear();
  }

  UserSession _requireSession() {
    final user = _session;
    if (user == null) {
      throw const RepositoryException('unauthenticated', 'Login required');
    }
    return user;
  }

  void _requireReadable([String? id]) {
    _requireSession();
    if (id != null && _itemReadErrors[id] != null) throw _itemReadErrors[id]!;
    if (_readError != null && (id == null || !_freshItems.contains(id))) {
      throw _readError!;
    }
  }

  UserSession _parseUser(Json data) {
    final roles = (data['roles'] as List? ?? []).cast<String>();
    if (!roles.contains('customer') && !roles.contains('provider')) {
      throw const RepositoryException(
        'mobile_role_required',
        'Mobile business role required',
      );
    }
    return UserSession(
      id: data['id'] as String,
      name: data['display_name'] as String,
      email: data['email'] as String,
      role: roles.contains('customer') ? UserRole.customer : UserRole.provider,
      active: data['status'] == 'active',
      authorized: data['internally_authorized'] == true,
    );
  }

  @override
  Future<UserSession> login(String email, String password) async {
    _api.setToken(null);
    _clearSession();
    final epoch = _epoch;
    try {
      final result = await _api.json(
        'POST',
        'mobile/auth/login',
        authenticated: false,
        body: {'email': email.trim(), 'password': password},
      );
      if (result['audience'] != 'mobile' || result['access_token'] is! String) {
        throw const RepositoryException(
          'invalid_response',
          'Invalid mobile session',
        );
      }
      _api.setToken(result['access_token'] as String);
      _session = _parseUser(await _api.json('GET', 'mobile/auth/me'));
      await refresh();
      return _session!;
    } catch (_) {
      // A slower previous login must not revoke a newer account's session.
      if (epoch == _epoch) {
        _api.setToken(null);
        _clearSession();
      }
      rethrow;
    }
  }

  @override
  Future<UserSession> register(
    String name,
    String email,
    String password,
  ) async {
    await _api.json(
      'POST',
      'mobile/auth/register',
      authenticated: false,
      body: {
        'display_name': name.trim(),
        'email': email.trim(),
        'password': password,
        'ui_locale': 'ja',
      },
    );
    return login(email, password);
  }

  @override
  Future<void> logout() async {
    try {
      if (_session != null) await _api.json('POST', 'mobile/auth/logout');
    } finally {
      // Offline logout always removes the local token; a failed server revoke is
      // still reported to the caller, never represented as successful revocation.
      _api.setToken(null);
      _clearSession();
    }
  }

  void close() {
    _api.close();
    _clearSession();
  }

  Future<List<Json>> _all(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final rows = <Json>[];
    for (var offset = 0; ; offset += 100) {
      final page = await _api.json(
        'GET',
        path,
        query: {...query, 'limit': '100', 'offset': '$offset'},
      );
      final items = _maps(page['items']);
      rows.addAll(items);
      if (items.length < 100 ||
          (page['total'] is int && rows.length >= page['total'])) {
        break;
      }
    }
    return rows;
  }

  @override
  Future<RequestClassifications> requestClassifications() async {
    _requireSession();
    final epoch = _epoch;
    final result = await _api.json('GET', 'mobile/request-classifications');
    if (result['platforms'] is! List || result['development_types'] is! List) {
      throw const RepositoryException(
        'invalid_response',
        'Invalid classification dictionary',
      );
    }
    if (epoch != _epoch) {
      throw const RepositoryException('session_changed', 'Session changed');
    }
    List<RequestClassification> parse(dynamic rows) => _maps(rows)
        .map(
          (row) => RequestClassification(
            code: row['code'] as String,
            nameZh: row['name_zh'] as String,
            nameJa: row['name_ja'] as String,
            enabled: row['enabled'] == true,
          ),
        )
        .toList();
    return RequestClassifications(
      platforms: parse(result['platforms']),
      developmentTypes: parse(result['development_types']),
    );
  }

  @override
  Future<void> refresh() async {
    final epoch = _epoch;
    final revision = ++_refreshRevision;
    _requireSession();
    try {
      final user = _parseUser(await _api.json('GET', 'mobile/auth/me'));
      final items = <String, WorkItem>{};
      final mine = <String>{};
      final hallIds = <String>{};
      final requests = <String, Json>{};
      final engagements = <String, Json>{};
      RequestDraft? draft;
      var draftVersion = 0;
      if (user.role == UserRole.customer) {
        final saved = _map((await _api.json('GET', 'mobile/draft'))['draft']);
        if (saved.isNotEmpty) {
          final files = _maps(saved['files']).map(_file).toList();
          draft = RequestDraft(
            platformCode: saved['platform_code'] as String?,
            developmentTypeCode: saved['development_type_code'] as String?,
            description: _str(saved['description']),
            timing: _str(saved['timing_text']),
            budget: _str(saved['budget_text']),
            attachmentNames: files.map((f) => f.name).toList(),
            files: files,
          );
          draftVersion = _int(saved['row_version']);
        }
        for (final row in await _all('mobile/requests')) {
          final id = row['id'] as String;
          final data = await _api.json('GET', 'mobile/requests/$id');
          requests[id] = data;
          items[id] = _request(data, user);
          mine.add(id);
        }
      } else if (user.authorized) {
        // A disabled hall is distinct from an empty hall and must be displayed.
        for (final row in await _all('mobile/hall')) {
          final id = row['request_id'] as String;
          final data = await _api.json('GET', 'mobile/hall/$id');
          items[id] = _hallItem(data);
          hallIds.add(id);
        }
      }
      if (user.role == UserRole.customer || user.authorized) {
        final perspective = user.role == UserRole.customer
            ? 'customer'
            : 'provider';
        for (final row in await _all(
          'mobile/engagements',
          query: {'perspective': perspective},
        )) {
          final data = await _api.json(
            'GET',
            'mobile/engagements/${row['id']}',
          );
          final id = _map(data['engagement'])['request_id'] as String;
          // Most recent engagement is listed first. A cancelled earlier relation
          // must not hide a later active relation of the same request.
          if (engagements.containsKey(id)) continue;
          engagements[id] = data;
          items[id] = _engagement(data, user, items[id]);
          mine.add(id);
        }
      }
      final threads = <String, List<Json>>{};
      for (final thread in await _all('mobile/threads')) {
        final id = thread['request_id'] as String;
        (threads[id] ??= []).add(thread);
        final messages = await _all('mobile/threads/${thread['id']}/messages');
        final item = items[id];
        if (item != null) {
          final parsed = messages.map(
            (message) => ChatMessage(
              author: _str(message['author_name'], _str(message['author_id'])),
              authorId: message['author_id'] as String?,
              text: _str(message['body']),
              sentAt: _date(message['sent_at']),
            ),
          );
          final merged = [...item.messages, ...parsed]
            ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
          items[id] = item.copyWith(messages: merged);
        }
      }
      final notifications = (await _all(
        'mobile/notifications',
      )).map(_notification).toList();
      if (epoch != _epoch) {
        throw const RepositoryException('session_changed', 'Session changed');
      }
      if (revision != _refreshRevision) {
        throw const RepositoryException(
          'refresh_superseded',
          'A newer refresh is in progress',
        );
      }
      _session = user;
      _items = items;
      _mine = mine;
      _hall = hallIds;
      _draft = draft;
      _draftVersion = draftVersion;
      _requestJson = requests;
      _threads = threads;
      _notifications = notifications;
      _readError = null;
      _itemReadErrors.clear();
      _freshItems.clear();
    } on RepositoryException catch (error) {
      if (epoch == _epoch && revision == _refreshRevision) {
        _readError = error;
        _freshItems.clear();
      }
      rethrow;
    } catch (_) {
      const error = RepositoryException(
        'invalid_response',
        'Invalid service response',
      );
      if (epoch == _epoch && revision == _refreshRevision) {
        _readError = error;
        _freshItems.clear();
      }
      throw error;
    }
  }

  @override
  Future<WorkItem> refreshItem(String id) async {
    final epoch = _epoch;
    final revision = ++_refreshRevision;
    final previousUser = _requireSession();
    try {
      final user = _parseUser(await _api.json('GET', 'mobile/auth/me'));
      // 权限发生变化时废弃整个旧快照，不能保留旧大厅或其他角色的数据。
      if (user.id != previousUser.id ||
          user.role != previousUser.role ||
          user.active != previousUser.active ||
          user.authorized != previousUser.authorized) {
        if (epoch == _epoch) {
          _api.setToken(null);
          _clearSession();
        }
        throw const RepositoryException('session_changed', 'Session changed');
      }
      Json? request;
      WorkItem? item;
      if (user.role == UserRole.customer) {
        request = await _api.json('GET', 'mobile/requests/$id');
        item = _request(request, user);
      } else if (!user.authorized) {
        throw const RepositoryException(
          'provider_required',
          'Internal authorization required',
        );
      }
      // 服务端按需求过滤后分页；只读取当前需求的最新合作详情。
      // 不依赖缓存的合作 ID，以便正确反映新建合作、取消和重新指定人员。
      final engagements = await _all(
        'mobile/engagements',
        query: {
          'perspective': user.role == UserRole.customer
              ? 'customer'
              : 'provider',
          'request_id': id,
        },
      );
      final engagement = engagements
          .where((row) => row['request_id'] == id)
          .firstOrNull;
      if (engagement != null) {
        item = _engagement(
          await _api.json('GET', 'mobile/engagements/${engagement['id']}'),
          user,
          item,
        );
      } else if (user.role == UserRole.provider) {
        item = _hallItem(await _api.json('GET', 'mobile/hall/$id'));
      }
      final currentThreads = (await _all(
        'mobile/threads',
        query: {'request_id': id},
      )).where((row) => row['request_id'] == id).toList();
      final messages = <ChatMessage>[];
      for (final thread in currentThreads) {
        for (final message in await _all(
          'mobile/threads/${thread['id']}/messages',
        )) {
          messages.add(
            ChatMessage(
              author: _str(message['author_name'], _str(message['author_id'])),
              authorId: message['author_id'] as String?,
              text: _str(message['body']),
              sentAt: _date(message['sent_at']),
            ),
          );
        }
      }
      messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      final result = item!.copyWith(messages: messages);
      if (epoch != _epoch) {
        throw const RepositoryException('session_changed', 'Session changed');
      }
      if (revision != _refreshRevision) {
        throw const RepositoryException(
          'refresh_superseded',
          'A newer refresh is in progress',
        );
      }
      _session = user;
      _itemReadErrors.remove(id);
      _freshItems.add(id);
      _items[id] = result;
      if (request != null) _requestJson[id] = request;
      _threads[id] = currentThreads;
      if (user.role == UserRole.customer || engagement != null) _mine.add(id);
      if (user.role == UserRole.provider) {
        if (engagement == null) {
          _mine.remove(id);
          _hall.add(id);
        } else {
          _hall.remove(id);
        }
      }
      return result;
    } on RepositoryException catch (error) {
      if (epoch == _epoch && revision == _refreshRevision) {
        _itemReadErrors[id] = error;
        _freshItems.remove(id);
      }
      rethrow;
    } catch (_) {
      const error = RepositoryException(
        'invalid_response',
        'Invalid service response',
      );
      if (epoch == _epoch && revision == _refreshRevision) {
        _itemReadErrors[id] = error;
        _freshItems.remove(id);
      }
      throw error;
    }
  }

  @override
  List<WorkItem> myRequests() {
    _requireReadable();
    return List.unmodifiable(
      _mine.map((id) => _items[id]!).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  @override
  List<WorkItem> conversationRequests() {
    _requireReadable();
    return _threads.keys
        .where(_items.containsKey)
        .map((id) => _items[id]!)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  List<NegotiationThread> negotiations(String id) => (_threads[id] ?? [])
      .where((t) => t['kind'] == 'negotiation')
      .map(
        (t) => NegotiationThread(t['id'] as String, _str(t['initiator_name'])),
      )
      .toList();

  @override
  Future<String> startNegotiation(String id) async {
    final row = await _api.json('POST', 'mobile/requests/$id/negotiation');
    await refreshItem(id);
    return row['id'] as String;
  }

  @override
  Future<Negotiation> negotiation(String threadId) async {
    final epoch = _epoch;
    _requireSession();
    final data = await _api.json('GET', 'mobile/threads/$threadId/negotiation');
    final messages = await _all('mobile/threads/$threadId/messages');
    if (epoch != _epoch) {
      throw const RepositoryException('session_changed', 'Session changed');
    }
    return Negotiation(
      data,
      messages
          .map(
            (m) => ChatMessage(
              author: _str(m['author_name']),
              authorId: m['author_id'] as String?,
              text: _str(m['body']),
              sentAt: _date(m['sent_at']),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> proposeClaim(
    Negotiation negotiation,
    String terms,
    int? amount,
    DateTime? dueAt,
  ) async {
    final body = <String, dynamic>{
      'publication_id': negotiation.publicationId,
      'terms': terms.trim(),
      'quoted_amount': amount,
      'due_at': dueAt?.toUtc().toIso8601String(),
    };
    await _command(
      'mobile/threads/${negotiation.threadId}/proposal',
      body,
      intent: 'proposal:${negotiation.threadId}:${jsonEncode(body)}',
      itemId: negotiation.requestId,
    );
  }

  @override
  Future<void> confirmClaim(Negotiation negotiation) async {
    final proposal = negotiation.proposal!;
    await _api.json(
      'POST',
      'mobile/claim-proposals/${proposal.id}/confirm',
      body: {'expected_version': proposal.rowVersion},
    );
  }

  @override
  Future<void> claimProject(Negotiation negotiation) async {
    final proposal = negotiation.proposal!;
    await _command(
      'mobile/claim-proposals/${proposal.id}/claim',
      {'expected_version': proposal.rowVersion},
      intent: 'claim:${proposal.id}',
      itemId: negotiation.requestId,
    );
  }

  @override
  Future<void> sendNegotiationMessage(String threadId, String text) async {
    final intent = '$threadId:${text.trim()}';
    final key = _messageKeys.putIfAbsent(intent, _uuid);
    await _api.json(
      'POST',
      'mobile/threads/$threadId/messages',
      body: {'body': text.trim(), 'client_message_id': key},
    );
    _messageKeys.remove(intent);
  }

  @override
  List<WorkItem> hall({String query = '', String category = 'すべて'}) {
    _requireReadable();
    if (_session!.role != UserRole.provider || !_session!.authorized) {
      throw const RepositoryException(
        'provider_required',
        'Internal authorization required',
      );
    }
    final search = query.trim().toLowerCase();
    return List.unmodifiable(
      _hall
          .map((id) => _items[id]!)
          .where(
            (item) =>
                (category == 'すべて' || category == item.category) &&
                '${item.title} ${item.description}'.toLowerCase().contains(
                  search,
                ),
          ),
    );
  }

  @override
  WorkItem detail(String id) {
    _requireReadable(id);
    return _cached(id);
  }

  WorkItem _cached(String id) =>
      _items[id] ??
      (throw const RepositoryException('not_found', 'Item not available'));

  @override
  List<TaskReference> references(String taskId) => detail(taskId).references;
  @override
  TaskReference reference(String taskId, String referenceId) {
    for (final file in references(taskId)) {
      if (file.id == referenceId) return file;
    }
    throw const RepositoryException('not_found', 'Reference not available');
  }

  @override
  Future<TaskReference> prepareReference(
    String taskId,
    String referenceId,
  ) async {
    await refreshItem(taskId);
    final value = reference(taskId, referenceId);
    await fileMetadata(value.id);
    return value;
  }

  List<String> _fileIds(RequestDraft value) {
    if (value.attachmentNames.isNotEmpty && value.files.isEmpty) {
      throw const RepositoryException(
        'invalid_attachments',
        'Select actual uploaded files',
      );
    }
    return value.files.map((f) => f.id).toList();
  }

  /// A retry reuses both the idempotency key and the ORIGINAL expected version.
  /// Removing only after refresh makes a lost response or failed read safe to retry.
  Future<Json> _command(
    String path,
    Json body, {
    required String intent,
    String? itemId,
  }) async {
    _requireSession();
    final command = _pending.putIfAbsent(
      intent,
      () => _PendingCommand(_uuid(), body),
    );
    var responseReceived = false;
    try {
      final result = await _api.json(
        'POST',
        path,
        body: command.body,
        idempotencyKey: command.key,
      );
      responseReceived = true;
      if (itemId == null) {
        await refresh();
      } else {
        await refreshItem(itemId);
      }
      _pending.remove(intent);
      return result;
    } on RepositoryException catch (error) {
      if (!responseReceived &&
          ![
            'network_unavailable',
            'invalid_response',
            'database_unavailable',
            'storage_unavailable',
            'request_failed',
            'lock_conflict',
          ].contains(error.code)) {
        _pending.remove(intent);
      }
      rethrow;
    }
  }

  @override
  Future<WorkItem> submitRequest(RequestDraft request) async {
    final body = <String, dynamic>{
      'service_code': 'development',
      'platform_code': request.platformCode,
      'development_type_code': request.developmentTypeCode,
      'original_description': request.description,
      'timing_text': request.timing,
      'budget_text': request.budget,
      'file_ids': _fileIds(request),
    };
    final result = await _command(
      'mobile/requests',
      body,
      intent: 'request:${jsonEncode(body)}',
    );
    return detail(result['id'] as String);
  }

  @override
  Future<void> saveDraft(RequestDraft request) async {
    _requireSession();
    final result = await _api.json(
      'PUT',
      'mobile/draft',
      body: {
        'expected_version': _draftVersion,
        'platform_code': request.platformCode,
        'development_type_code': request.developmentTypeCode,
        'description': request.description,
        'timing_text': request.timing,
        'budget_text': request.budget,
        'file_ids': _fileIds(request),
      },
    );
    final saved = _map(result['draft']);
    final files = _maps(saved['files']).map(_file).toList();
    _draftVersion = _int(saved['row_version']);
    _draft = RequestDraft(
      platformCode: saved['platform_code'] as String?,
      developmentTypeCode: saved['development_type_code'] as String?,
      description: _str(saved['description']),
      timing: _str(saved['timing_text']),
      budget: _str(saved['budget_text']),
      files: files,
      attachmentNames: files.map((f) => f.name).toList(),
    );
  }

  @override
  Future<void> answerQuestion(String id, String text) async {
    final row = _requestJson[id];
    if (row == null) {
      throw const RepositoryException('not_found', 'Request not found');
    }
    final questions = _maps(
      row['clarifications'],
    ).where((q) => q['answer'] == null).toList();
    if (questions.isEmpty) {
      throw const RepositoryException(
        'state_conflict',
        'No unanswered question',
      );
    }
    await _api.json(
      'POST',
      'mobile/requests/$id/clarifications/${questions.first['id']}/answer',
      body: {'answer': text.trim(), 'expected_version': row['row_version']},
    );
    await refreshItem(id);
  }

  @override
  Future<void> consult(String id, String text) async {
    _requireSession();
    final thread = await _api.json('POST', 'mobile/requests/$id/consultation');
    await _send(thread['id'] as String, text, id);
  }

  @override
  Future<void> sendMessage(String id, String text) async {
    _requireSession();
    final threads = _threads[id] ?? [];
    final project = threads
        .where((t) => t['kind'] == 'customer_project')
        .toList();
    if (project.isNotEmpty) {
      await _send(project.first['id'] as String, text, id);
    } else {
      await consult(id, text);
    }
  }

  Future<void> _send(String threadId, String text, String itemId) async {
    final clean = text.trim();
    if (clean.isEmpty) {
      throw const RepositoryException(
        'invalid_message',
        'Message cannot be empty',
      );
    }
    final intent = '$threadId:$clean';
    final key = _messageKeys.putIfAbsent(intent, _uuid);
    await _api.json(
      'POST',
      'mobile/threads/$threadId/messages',
      body: {'body': clean, 'client_message_id': key},
    );
    await refreshItem(itemId);
    _messageKeys.remove(intent);
  }

  @override
  Future<void> confirmAgreement(String id) async {
    final item = _cached(id);
    if (item.engagementId == null || !item.pendingConfirmation) {
      throw const RepositoryException('state_conflict', 'No pending agreement');
    }
    await _api.json(
      'POST',
      'mobile/engagements/${item.engagementId}/agreements/${item.agreementVersion}/confirm',
      body: {'expected_version': item.rowVersion},
    );
    await refreshItem(id);
  }

  @override
  Future<void> submitDelivery(String id, Delivery delivery) async {
    final item = _cached(id);
    if (item.engagementId == null) {
      throw const RepositoryException('state_conflict', 'Cooperation required');
    }
    final payload = <String, dynamic>{
      'agreement_version': item.agreementVersion,
      'note': delivery.note,
      'guide_text': delivery.guideName,
      'test_report_text': delivery.testName,
      'source_file_id': delivery.sourceFileId,
      'repository_url': delivery.sourceFileId == null
          ? delivery.repositoryUrl
          : null,
      'source_commit': delivery.sourceFileId == null
          ? delivery.sourceRef
          : null,
      'source_archive_ref': delivery.sourceFileId == null
          ? delivery.sourceArchiveRef
          : null,
      'files': delivery.files
          .where((f) => f.id != delivery.sourceFileId)
          .map((f) => {'file_id': f.id, 'purpose': f.purpose})
          .toList(),
    };
    await _command(
      'mobile/engagements/${item.engagementId}/deliveries',
      {...payload, 'expected_version': item.rowVersion},
      intent: 'delivery:$id:${jsonEncode(payload)}',
      itemId: id,
    );
  }

  Future<void> _accept(
    String id,
    int version,
    String decision,
    String feedback,
  ) async {
    final item = _cached(id);
    final delivery = item.deliveries
        .where((d) => d.version == version && d.published)
        .firstOrNull;
    if (delivery?.id == null || item.engagementId == null) {
      throw const RepositoryException(
        'version_conflict',
        'Published delivery required',
      );
    }
    final payload = <String, dynamic>{
      'decision': decision,
      'feedback': feedback,
    };
    await _command(
      'mobile/engagements/${item.engagementId}/deliveries/${delivery!.id}/acceptance',
      {...payload, 'expected_version': item.rowVersion},
      intent: 'accept:${delivery.id}:${jsonEncode(payload)}',
      itemId: id,
    );
  }

  @override
  Future<void> requestRevision(String id, int version, String text) =>
      _accept(id, version, 'revision_requested', text.trim());
  @override
  Future<void> acceptDelivery(String id, int version) =>
      _accept(id, version, 'accepted', '');

  @override
  List<AppNotification> notifications() {
    _requireReadable();
    return List.unmodifiable(_notifications);
  }

  @override
  Future<void> markNotificationRead(String id) async {
    await _api.json('POST', 'mobile/notifications/$id/read');
    await refresh();
  }

  @override
  Future<RemoteFile> uploadFile(String name, Uint8List bytes) async {
    _requireSession();
    final result = await _api.send(
      'POST',
      'mobile/files',
      fileName: name,
      bytes: bytes,
    );
    return _file(_api.decode(result));
  }

  @override
  Future<RemoteFile> fileMetadata(String id) async =>
      _file(await _api.json('GET', 'mobile/files/$id'));
  @override
  Future<Uint8List> downloadFile(String id) async =>
      (await _api.send('GET', 'mobile/files/$id/download')).bodyBytes;
  @override
  Future<RemotePreview> previewFile(String id) async {
    final response = await _api.send(
      'GET',
      'mobile/files/$id/preview',
      requestTimeout: const Duration(seconds: 90),
    );
    final type = response.headers['content-type']?.split(';').first ?? '';
    if (type == 'application/json') {
      final data = _api.decode(response);
      return RemotePreview(
        state: data['state'] == 'ready'
            ? ReferencePreviewState.ready
            : ReferencePreviewState.unsupported,
        text: _str(data['text']),
        truncated: data['truncated'] == true,
        mediaType: data['format'] == 'text' ? 'text/plain' : '',
        errorCode: data['error_code'] as String?,
      );
    }
    if (const [
      'image/png',
      'image/jpeg',
      'image/webp',
      'image/gif',
      'application/pdf',
      'video/mp4',
      'video/webm',
      'audio/mpeg',
      'audio/mp4',
      'audio/wav',
      'audio/ogg',
      'audio/flac',
    ].contains(type)) {
      return RemotePreview(
        state: ReferencePreviewState.ready,
        mediaType: type,
        bytes: response.bodyBytes,
      );
    }
    throw const RepositoryException(
      'invalid_response',
      'Unsupported preview response',
    );
  }

  @override
  Future<void> reset() async => throw const RepositoryException(
    'unsupported',
    'Live data cannot be reset',
  );

  static Json _map(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};
  static List<Json> _maps(dynamic value) =>
      value is List ? value.map(_map).toList() : [];
  static String _str(dynamic value, [String fallback = '']) =>
      value is String ? value : fallback;
  static int _int(dynamic value, [int fallback = 0]) =>
      value is int ? value : fallback;
  static int? _amount(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String && RegExp(r'^\d+(?:\.0+)?$').hasMatch(value)) {
      return int.parse(value.split('.').first);
    }
    throw const RepositoryException('invalid_response', 'Invalid JPY amount');
  }

  static DateTime _date(dynamic value) => DateTime.parse(value as String);
  static RemoteFile _file(Json row) => RemoteFile(
    id: _str(row['id'], _str(row['file_id'])),
    name: _str(row['original_name']),
    sizeBytes: _int(row['size_bytes']),
    mediaType: _str(row['media_type'], 'application/octet-stream'),
    scanStatus: _str(row['scan_status'], 'clean'),
    uploadStatus: _str(row['upload_status'], 'ready'),
    sha256: _str(row['sha256']),
    purpose: _str(row['purpose'], 'other'),
  );
  static AppNotification _notification(Json row) => AppNotification(
    id: row['id'].toString(),
    templateKey: _str(row['template_key']),
    parameters: _map(row['parameters']),
    createdAt: _date(row['created_at']),
    readAt: row['read_at'] == null ? null : _date(row['read_at']),
  );
  static TaskReference _reference(Json row, int version) {
    final kind =
        ReferenceKind.values
            .where((kind) => kind.name == row['kind'])
            .firstOrNull ??
        ReferenceKind.other;
    return TaskReference(
      id: _str(row['file_id'], _str(row['id'])),
      fileName: _str(row['original_name']),
      kind: kind,
      sizeBytes: _int(row['size_bytes']),
      assetPath: '',
      remote: true,
      publishedVersion: version,
      durationSeconds: _int(row['duration_ms']) ~/ 1000,
      previewState:
          [
            ReferenceKind.image,
            ReferenceKind.video,
            ReferenceKind.text,
          ].contains(kind)
          ? ReferencePreviewState.ready
          : ReferencePreviewState.unsupported,
    );
  }

  WorkItem _request(Json row, UserSession user) {
    final original = _map(row['original']);
    final scope = _map(row['scope']);
    final scopeVersion = _int(row['current_scope_version']);
    final reviews = _maps(
      row['reviews'],
    ).where((r) => r['scope_version'] == scopeVersion);
    final compliance = reviews.any(
      (r) => r['kind'] == 'compliance' && r['decision'] == 'approved',
    );
    final technical = reviews.any(
      (r) => r['kind'] == 'technical' && r['decision'] == 'approved',
    );
    final publication = _maps(row['publications'])
        .where(
          (p) =>
              p['withdrawn_at'] == null && p['scope_version'] == scopeVersion,
        )
        .firstOrNull;
    final questions = _maps(
      row['clarifications'],
    ).where((q) => q['answer'] == null).toList();
    final state = _str(row['intake_status']);
    // Backend closes rejected intake as `closed`; only an accepted engagement
    // is completed work. Preserve this distinction in the mobile status label.
    final rejected =
        state == 'closed' &&
        reviews.any((review) => review['decision'] == 'rejected');
    final published = publication != null && compliance && technical;
    final description = _str(original['original_description']);
    return WorkItem(
      id: row['id'] as String,
      publicCode: _str(row['public_code']),
      title: _str(
        scope['title'],
        description.length > 60
            ? '${description.substring(0, 60)}…'
            : description,
      ),
      description: description,
      category: _str(scope['category'], 'development'),
      platformCode: original['platform_code'] as String?,
      developmentTypeCode: original['development_type_code'] as String?,
      duration: _str(scope['duration_text'], _str(original['timing_text'])),
      status: state == 'needs_info'
          ? WorkStatus.needsInfo
          : state == 'closed' && !rejected
          ? WorkStatus.completed
          : published
          ? WorkStatus.published
          : WorkStatus.reviewing,
      ownerId: user.id,
      version: scopeVersion > 0
          ? scopeVersion
          : _int(row['current_request_version'], 1),
      publishedVersion: published ? scopeVersion : null,
      complianceApproved: compliance,
      technicalApproved: technical,
      rowVersion: _int(row['row_version'], 1),
      question: questions.isEmpty ? null : _str(questions.first['question']),
      budget: _str(original['budget_text']),
      createdAt: _date(row['created_at']),
      intakeState: rejected ? 'rejected' : state,
      attachmentNames: _maps(
        row['private_files'],
      ).map((f) => _str(f['original_name'])).toList(),
      files: _maps(row['private_files']).map(_file).toList(),
      scope: scope,
      references: _maps(
        scope['reference_files'],
      ).map((f) => _reference(f, scopeVersion)).toList(),
    );
  }

  WorkItem _hallItem(Json row) {
    final version = _int(row['scope_version'], 1);
    return WorkItem(
      id: row['request_id'] as String,
      publicCode: _str(row['public_code']),
      title: _str(row['title']),
      description: _str(row['public_summary']),
      category: _str(row['category']),
      duration: _str(row['duration_text']),
      status: WorkStatus.published,
      ownerId: '',
      version: version,
      publishedVersion: version,
      complianceApproved: true,
      technicalApproved: true,
      budget: '',
      createdAt: _date(row['published_at']),
      scope: row,
      references: _maps(
        row['references'],
      ).map((f) => _reference(f, version)).toList(),
    );
  }

  WorkItem _engagement(Json data, UserSession user, WorkItem? original) {
    final row = _map(data['engagement']);
    final agreements = _maps(data['agreements']);
    final agreement = agreements.isEmpty
        ? <String, dynamic>{}
        : agreements.last;
    final scope = _map(agreement['scope']);
    final version = _int(agreement['scope_version'], 1);
    final deliveries = _maps(data['deliveries']).map((d) {
      final files = _maps(d['files']).map(_file).toList();
      final source = files
          .where((f) => f.id == d['source_file_id'])
          .firstOrNull;
      return Delivery(
        id: d['id'] as String,
        version: _int(d['version']),
        sourceName: source?.name ?? _str(d['repository_url']),
        sourceRef: _str(d['source_commit']),
        guideName: _str(d['guide_text']),
        testName: _str(d['test_report_text']),
        note: _str(d['note']),
        published: d['published'] == true,
        sourceFileId: d['source_file_id'] as String?,
        repositoryUrl: d['repository_url'] as String?,
        sourceArchiveRef: d['source_archive_ref'] as String?,
        files: files,
      );
    }).toList();
    final acceptances = _maps(data['acceptances']);
    final confirmations = _maps(data['confirmations']);
    final status = switch (row['status']) {
      'executing' => WorkStatus.developing,
      'internal_review' => WorkStatus.internalReview,
      'awaiting_acceptance' => WorkStatus.awaitingAcceptance,
      'revision' => WorkStatus.revision,
      'completed' => WorkStatus.completed,
      _ => WorkStatus.reviewing,
    };
    return WorkItem(
      id: row['request_id'] as String,
      publicCode: _str(row['public_code']),
      engagementId: row['id'] as String,
      rowVersion: _int(row['row_version'], 1),
      title: _str(scope['title'], original?.title ?? ''),
      description: _str(scope['goal'], original?.description ?? ''),
      category: original?.category ?? 'development',
      platformCode: original?.platformCode,
      developmentTypeCode: original?.developmentTypeCode,
      duration: _str(scope['duration_text']),
      status: status,
      ownerId: _str(
        row['customer_id'],
        user.role == UserRole.customer ? user.id : '',
      ),
      providerId: row['provider_id'] as String?,
      version: version,
      complianceApproved: true,
      technicalApproved: true,
      publishedVersion: version,
      agreementVersion: _int(agreement['version']),
      agreementTerms: _str(agreement['terms']),
      pendingConfirmation: row['status'] == 'pending_confirmation',
      confirmedByMe: confirmations.any(
        (c) =>
            c['agreement_version'] == agreement['version'] &&
            c['confirmed_by'] == user.id,
      ),
      quotedAmount: _amount(agreement['quoted_amount']),
      dueAt: agreement['due_at'] == null ? null : _date(agreement['due_at']),
      budget: agreement['quoted_amount'] == null
          ? ''
          : 'JPY ${agreement['quoted_amount']}',
      createdAt: _date(row['created_at']),
      deliveries: deliveries,
      intakeState: _str(row['status']),
      latestNote: acceptances.isEmpty
          ? null
          : _str(acceptances.last['feedback']),
      // Intake clarification and cooperation progress are independent. The
      // customer must still be able to answer a new question while executing.
      question: original?.question,
      attachmentNames: original?.attachmentNames ?? [],
      files: original?.files ?? [],
      scope: scope,
      references: scope.containsKey('reference_files')
          ? _maps(
              scope['reference_files'],
            ).map((f) => _reference(f, version)).toList()
          : original?.references ?? [],
    );
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
