import 'dart:typed_data';
import 'models.dart';
import 'negotiation_models.dart';
export 'negotiation_models.dart';

/// UI data boundary. A production adapter must enforce these rules server-side.
/// The bundled Mock implementation has no backend, real auth or file transport.
abstract class OpcRepository {
  UserSession? get session;
  RequestDraft? get draft;

  Future<UserSession> login(String email, String password);
  Future<UserSession> register(String name, String email, String password);
  Future<void> logout();
  List<WorkItem> myRequests();
  List<WorkItem> hall({String query = '', String category = 'すべて'});
  WorkItem detail(String id);

  /// Only current, explicitly published references visible to this session.
  List<TaskReference> references(String taskId);
  TaskReference reference(String taskId, String referenceId);
  Future<TaskReference> prepareReference(String taskId, String referenceId);
  Future<WorkItem> submitRequest(RequestDraft request);
  Future<void> saveDraft(RequestDraft request);
  Future<void> answerQuestion(String id, String text);
  Future<void> consult(String id, String text);
  Future<void> sendMessage(String id, String text);
  Future<void> submitDelivery(String id, Delivery delivery);
  Future<void> requestRevision(String id, int version, String text);
  Future<void> acceptDelivery(String id, int version);
  Future<void> reset();
}

/// Live HTTP capabilities. Synchronous methods expose only a fully loaded
/// snapshot; callers refresh on entry/resume and before permission-sensitive use.
abstract class RemoteOpcRepository implements OpcRepository {
  Future<RequestClassifications> requestClassifications();
  Future<void> refresh();
  Future<WorkItem> refreshItem(String id);
  List<WorkItem> conversationRequests();
  List<NegotiationThread> negotiations(String id);
  Future<String> startNegotiation(String id);
  Future<Negotiation> negotiation(String threadId);
  Future<void> proposeClaim(
    Negotiation negotiation,
    String terms,
    int? amount,
    DateTime? dueAt,
  );
  Future<void> confirmClaim(Negotiation negotiation);
  Future<void> claimProject(Negotiation negotiation);
  Future<void> sendNegotiationMessage(String threadId, String text);
  List<AppNotification> notifications();
  Future<void> markNotificationRead(String id);
  Future<void> confirmAgreement(String id);
  Future<RemoteFile> uploadFile(String name, Uint8List bytes);
  Future<RemoteFile> fileMetadata(String id);
  Future<Uint8List> downloadFile(String id);
  Future<RemotePreview> previewFile(String id);
}

class RemotePreview {
  const RemotePreview({
    required this.state,
    this.bytes,
    this.mediaType = '',
    this.text = '',
    this.truncated = false,
    this.errorCode,
  });
  final ReferencePreviewState state;
  final Uint8List? bytes;
  final String mediaType;
  final String text;
  final bool truncated;
  final String? errorCode;
}
