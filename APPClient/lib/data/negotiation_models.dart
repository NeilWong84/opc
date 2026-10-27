import 'models.dart';

class NegotiationThread {
  const NegotiationThread(this.id, this.name);
  final String id;
  final String name;
}

class ClaimProposal {
  ClaimProposal(Map<String, dynamic> data)
    : id = data['id'] as String,
      publicationId = data['publication_id'] as String,
      terms = data['terms'] as String,
      amount = data['quoted_amount'] as int?,
      dueAt = data['due_at'] == null
          ? null
          : DateTime.parse(data['due_at'] as String),
      confirmed = data['confirmed_at'] != null,
      rowVersion = data['row_version'] as int;
  final String id, publicationId, terms;
  final int? amount;
  final DateTime? dueAt;
  final bool confirmed;
  final int rowVersion;
}

class Negotiation {
  Negotiation(Map<String, dynamic> data, this.messages)
    : threadId = data['thread_id'] as String,
      requestId = data['request_id'] as String,
      providerId = data['provider_id'] as String,
      providerName = data['provider_name'] as String,
      customerId = data['customer_id'] as String,
      available = data['available'] == true,
      publicationId = data['publication_id'] as String?,
      scope = Map<String, dynamic>.from(data['scope'] as Map),
      proposal = data['proposal'] == null
          ? null
          : ClaimProposal(Map<String, dynamic>.from(data['proposal'] as Map));
  final String threadId, requestId, providerId, providerName, customerId;
  final bool available;
  final String? publicationId;
  final Map<String, dynamic> scope;
  final ClaimProposal? proposal;
  final List<ChatMessage> messages;
  bool get currentProposal =>
      available && proposal?.publicationId == publicationId;
}
