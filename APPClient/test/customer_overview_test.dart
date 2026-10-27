import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/data/customer_overview.dart';
import 'package:opc_app/data/models.dart';

WorkItem overviewItem(
  String id, {
  WorkStatus status = WorkStatus.reviewing,
  String state = 'submitted',
  String owner = 'customer',
  bool project = false,
  bool pending = false,
  bool confirmed = false,
  String? question,
  DateTime? dueAt,
  List<Delivery> deliveries = const [],
  List<ChatMessage> messages = const [],
}) => WorkItem(
  id: id,
  title: '项目原文 $id',
  description: '原文の内容',
  category: 'development',
  duration: '',
  status: status,
  ownerId: owner,
  providerId: project ? 'provider' : null,
  engagementId: project ? 'project-$id' : null,
  createdAt: DateTime.utc(2026, 10, 25),
  intakeState: state,
  pendingConfirmation: pending,
  confirmedByMe: confirmed,
  question: question,
  dueAt: dueAt,
  deliveries: deliveries,
  messages: messages,
);

const visibleDelivery = Delivery(
  version: 1,
  sourceName: '',
  sourceRef: '',
  guideName: '',
  testName: '',
  note: '',
  published: true,
);

void main() {
  test(
    'statistics separate reviews, active cooperation, acceptance and actual completion',
    () {
      final overview = CustomerOverview([
        overviewItem('review'),
        overviewItem('question', status: WorkStatus.needsInfo),
        overviewItem('published', status: WorkStatus.published),
        overviewItem('active', project: true, status: WorkStatus.developing),
        overviewItem('terms', project: true, pending: true),
        overviewItem(
          'accept',
          project: true,
          status: WorkStatus.awaitingAcceptance,
        ),
        overviewItem('done', project: true, status: WorkStatus.completed),
        overviewItem(
          'closed-intake',
          state: 'closed',
          status: WorkStatus.completed,
        ),
        overviewItem('rejected', state: 'rejected'),
        overviewItem('withdrawn', state: 'withdrawn'),
        overviewItem('cancelled', project: true, state: 'cancelled'),
        overviewItem('draft', state: 'draft'),
        overviewItem('someone-else', owner: 'other'),
      ], 'customer');
      expect(overview.items, hasLength(12));
      expect(
        overview.filtered(CustomerRequestFilter.reviewing).map((i) => i.id),
        ['review', 'question'],
      );
      expect(overview.filtered(CustomerRequestFilter.active).map((i) => i.id), [
        'active',
        'terms',
      ]);
      expect(
        overview.filtered(CustomerRequestFilter.acceptance).single.id,
        'accept',
      );
      expect(
        overview.filtered(CustomerRequestFilter.completed).single.id,
        'done',
      );
      expect(overview.reviews.map((i) => i.id), [
        'review',
        'question',
        'published',
      ]);
      expect(overview.projects.map((i) => i.id), ['active', 'terms', 'accept']);
    },
  );

  test(
    'todos keep cooperation clarification, skip confirmed terms and private delivery',
    () {
      final overview = CustomerOverview([
        overviewItem(
          'active-question',
          project: true,
          status: WorkStatus.developing,
          question: '実行中の追加質問',
        ),
        overviewItem('terms', project: true, pending: true),
        overviewItem(
          'confirmed',
          project: true,
          pending: true,
          confirmed: true,
        ),
        overviewItem(
          'accept',
          project: true,
          status: WorkStatus.awaitingAcceptance,
          deliveries: [visibleDelivery],
        ),
        overviewItem(
          'private',
          project: true,
          status: WorkStatus.awaitingAcceptance,
        ),
        overviewItem(
          'cancelled',
          project: true,
          state: 'cancelled',
          pending: true,
          question: '不可操作',
        ),
      ], 'customer');
      expect(overview.todos.map((t) => t.kind), [
        CustomerTodoKind.clarification,
        CustomerTodoKind.agreement,
        CustomerTodoKind.acceptance,
      ]);
    },
  );

  test(
    'feedback identifies current provider by ID and sorts by message time',
    () {
      ChatMessage message(String authorId, int hour, String text) =>
          ChatMessage(
            author: '同名ユーザー',
            authorId: authorId,
            text: text,
            sentAt: DateTime.utc(2026, 10, 25, hour),
          );
      final overview = CustomerOverview([
        overviewItem(
          'a',
          project: true,
          messages: [
            message('provider', 3, 'earlier'),
            message('customer', 8, 'own-message'),
            message('operator', 9, 'operations'),
            message('old-provider', 10, 'old'),
            ChatMessage(
              author: 'provider',
              text: 'unidentified',
              sentAt: DateTime.utc(2026),
            ),
          ],
        ),
        overviewItem(
          'b',
          project: true,
          messages: [message('provider', 4, 'latest')],
        ),
        overviewItem(
          'foreign',
          owner: 'other',
          project: true,
          messages: [message('provider', 6, 'private')],
        ),
      ], 'customer');
      expect(overview.feedback.map((f) => f.message.text), [
        'latest',
        'earlier',
      ]);
      expect(overview.feedback.first.item.id, 'b');
    },
  );

  test(
    'projects use agreed due dates, not a synthetic progress percentage',
    () {
      final overview = CustomerOverview([
        overviewItem('no-date', project: true),
        overviewItem('later', project: true, dueAt: DateTime.utc(2026, 12)),
        overviewItem('soon', project: true, dueAt: DateTime.utc(2026, 11)),
      ], 'customer');
      expect(overview.projects.map((i) => i.id), ['soon', 'later', 'no-date']);
    },
  );
}
