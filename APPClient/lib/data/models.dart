import 'reference_models.dart';

export 'reference_models.dart';

/// Pure Dart models shared by the mobile UI and replaceable data adapters.
enum UserRole { customer, provider }

class UserSession {
  const UserSession({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.active = true,
    this.authorized = false,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final bool active;

  /// Internal access only. This does not mean formal OPC certification.
  final bool authorized;
}

enum WorkStatus {
  needsInfo,
  reviewing,
  published,
  developing,
  internalReview,
  awaitingAcceptance,
  revision,
  completed,
}

class WorkItem {
  WorkItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    this.platformCode,
    this.developmentTypeCode,
    required this.duration,
    required this.status,
    required this.ownerId,
    this.providerId,
    this.version = 1,
    this.publishedVersion,
    this.complianceApproved = false,
    this.technicalApproved = false,
    this.question,
    this.latestNote,
    this.publicCode,
    this.engagementId,
    this.rowVersion = 1,
    this.agreementVersion = 0,
    this.agreementTerms = '',
    this.pendingConfirmation = false,
    this.confirmedByMe = false,
    this.quotedAmount,
    this.dueAt,
    this.intakeState = '',
    this.budget = '相談して決めたい',
    required this.createdAt,
    List<String> attachmentNames = const [],
    List<Delivery> deliveries = const [],
    List<ChatMessage> messages = const [],
    List<TaskReference> references = const [],
    List<RemoteFile> files = const [],
    Map<String, dynamic> scope = const {},
  }) : attachmentNames = List.unmodifiable(attachmentNames),
       deliveries = List.unmodifiable(deliveries),
       messages = List.unmodifiable(messages),
       references = List.unmodifiable(references),
       files = List.unmodifiable(files),
       scope = Map.unmodifiable(scope);

  final String id;
  final String title;
  final String description;
  final String category;
  final String? platformCode;
  final String? developmentTypeCode;
  final String duration;
  final WorkStatus status;
  final String ownerId;
  final String? providerId;
  final int version;
  final int? publishedVersion;
  final bool complianceApproved;
  final bool technicalApproved;
  final String? question;
  final String? latestNote;
  final String? publicCode;
  final String? engagementId;
  final int rowVersion;
  final int agreementVersion;
  final String agreementTerms;
  final bool pendingConfirmation;
  final bool confirmedByMe;
  final int? quotedAmount;
  final DateTime? dueAt;
  final String intakeState;
  final String budget;
  final DateTime createdAt;
  final List<String> attachmentNames;
  final List<Delivery> deliveries;
  final List<ChatMessage> messages;
  final List<TaskReference> references;
  final List<RemoteFile> files;
  final Map<String, dynamic> scope;

  bool get isPublished =>
      complianceApproved && technicalApproved && publishedVersion == version;

  /// Mobile entry visibility; the server independently validates every submit.
  bool canSubmitDeliveryBy(UserSession? user) =>
      user != null &&
      user.active &&
      user.authorized &&
      user.role == UserRole.provider &&
      providerId == user.id &&
      engagementId != null &&
      !pendingConfirmation &&
      [WorkStatus.developing, WorkStatus.revision].contains(status);

  WorkItem copyWith({
    WorkStatus? status,
    int? version,
    int? publishedVersion,
    bool clearPublication = false,
    bool? complianceApproved,
    bool? technicalApproved,
    String? question,
    bool clearQuestion = false,
    String? latestNote,
    bool clearLatestNote = false,
    List<String>? attachmentNames,
    List<Delivery>? deliveries,
    List<ChatMessage>? messages,
    List<TaskReference>? references,
  }) => WorkItem(
    id: id,
    title: title,
    description: description,
    category: category,
    platformCode: platformCode,
    developmentTypeCode: developmentTypeCode,
    duration: duration,
    status: status ?? this.status,
    ownerId: ownerId,
    providerId: providerId,
    version: version ?? this.version,
    publishedVersion: clearPublication
        ? null
        : publishedVersion ?? this.publishedVersion,
    complianceApproved: complianceApproved ?? this.complianceApproved,
    technicalApproved: technicalApproved ?? this.technicalApproved,
    question: clearQuestion ? null : question ?? this.question,
    latestNote: clearLatestNote ? null : latestNote ?? this.latestNote,
    publicCode: publicCode,
    engagementId: engagementId,
    rowVersion: rowVersion,
    agreementVersion: agreementVersion,
    agreementTerms: agreementTerms,
    pendingConfirmation: pendingConfirmation,
    confirmedByMe: confirmedByMe,
    quotedAmount: quotedAmount,
    dueAt: dueAt,
    intakeState: intakeState,
    budget: budget,
    createdAt: createdAt,
    attachmentNames: attachmentNames ?? this.attachmentNames,
    deliveries: deliveries ?? this.deliveries,
    messages: messages ?? this.messages,
    references: references ?? this.references,
    files: files,
    scope: scope,
  );
}

class Delivery {
  const Delivery({
    required this.version,
    required this.sourceName,
    required this.sourceRef,
    required this.guideName,
    required this.testName,
    required this.note,
    this.published = false,
    this.id,
    this.sourceFileId,
    this.repositoryUrl,
    this.sourceArchiveRef,
    this.files = const [],
  });

  final int version;
  final String sourceName;
  final String sourceRef;
  final String guideName;
  final String testName;
  final String note;
  final bool published;
  final String? id;
  final String? sourceFileId;
  final String? repositoryUrl;
  final String? sourceArchiveRef;
  final List<RemoteFile> files;

  Delivery copyWith({bool? published}) => Delivery(
    version: version,
    sourceName: sourceName,
    sourceRef: sourceRef,
    guideName: guideName,
    testName: testName,
    note: note,
    published: published ?? this.published,
    id: id,
    sourceFileId: sourceFileId,
    repositoryUrl: repositoryUrl,
    sourceArchiveRef: sourceArchiveRef,
    files: files,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.author,
    required this.text,
    required this.sentAt,
    this.authorId,
  });

  final String author;

  /// 服务端身份，用于区分客户、运营与当前项目承接者的消息。
  final String? authorId;
  final String text;
  final DateTime sentAt;
}

class RequestDraft {
  RequestDraft({
    this.description = '',
    this.platformCode,
    this.developmentTypeCode,
    this.timing = '相談して決めたい',
    this.budget = '相談して決めたい',
    List<String> attachmentNames = const [],
    List<RemoteFile> files = const [],
  }) : attachmentNames = List.unmodifiable(attachmentNames),
       files = List.unmodifiable(files);

  final String description;
  final String? platformCode;
  final String? developmentTypeCode;
  final String timing;
  final String budget;

  /// Display labels. Live requests require the corresponding server file IDs.
  final List<String> attachmentNames;
  final List<RemoteFile> files;
}

class RequestClassification {
  const RequestClassification({
    required this.code,
    required this.nameZh,
    required this.nameJa,
    this.enabled = true,
  });
  final String code;
  final String nameZh;
  final String nameJa;
  final bool enabled;
  String label(String language) => language == 'zh' ? nameZh : nameJa;
}

class RequestClassifications {
  const RequestClassifications({
    this.platforms = const [],
    this.developmentTypes = const [],
  });
  final List<RequestClassification> platforms;
  final List<RequestClassification> developmentTypes;
}

class RemoteFile {
  const RemoteFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    this.mediaType = 'application/octet-stream',
    this.scanStatus = 'pending',
    this.uploadStatus = 'ready',
    this.sha256 = '',
    this.purpose = 'other',
  });
  final String id;
  final String name;
  final int sizeBytes;
  final String mediaType;
  final String scanStatus;
  final String uploadStatus;
  final String sha256;
  final String purpose;
  bool get isReady => uploadStatus == 'ready' && scanStatus == 'clean';
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.templateKey,
    required this.createdAt,
    this.readAt,
    Map<String, dynamic> parameters = const {},
  }) : parameters = Map.unmodifiable(parameters);
  final String id;
  final String templateKey;
  final Map<String, dynamic> parameters;
  final DateTime createdAt;
  final DateTime? readAt;
  bool get isRead => readAt != null;
}

class RepositoryException implements Exception {
  const RepositoryException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}
