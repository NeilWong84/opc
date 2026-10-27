import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/api_workspace.dart';

import 'api_ui_test.dart' show LiveUiRepository, host, tapKey;
import 'request_date_picker_helpers.dart';

String iso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void main() {
  testWidgets(
    'completion field opens calendar and submits selected date as ISO',
    (tester) async {
      final repo = LiveUiRepository()
        ..saved = RequestDraft(
          description: '客户希望开发预约系统，并保留原始需求。',
          timing: '',
          budget: 'JPY 要相談',
        );
      final app = AppController(repo);
      addTearDown(app.dispose);
      await app.setLocale(const Locale('zh'));
      await tester.pumpWidget(host(app, ApiRequestPage(app: app)));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('api-request-timing'));
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)),
            )
            .readOnly,
        isTrue,
      );
      await tapKey(tester, 'api-submit-request');
      expect(repo.submitted, isNull);
      final selected = await chooseCompletionDate(tester, day: 15);
      expect(find.byType(DatePickerDialog), findsNothing);
      final context = tester.element(field);
      expect(
        tester.widget<TextFormField>(field).controller!.text,
        MaterialLocalizations.of(context).formatShortDate(selected),
      );
      await tapKey(tester, 'api-submit-request');
      expect(repo.submitted!.timing, iso(selected));
      expect(repo.submitted!.description, repo.saved!.description);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved ISO date restores selection; cancel and locale changes preserve it',
    (tester) async {
      final repo = LiveUiRepository()
        ..saved = RequestDraft(
          description: '社内システムの開発を依頼します。',
          timing: '2027-01-15',
          budget: '相談',
        );
      final app = AppController(repo);
      addTearDown(app.dispose);
      await tester.pumpWidget(host(app, ApiRequestPage(app: app)));
      await tester.pumpAndSettle();
      await tapKey(tester, 'api-pick-completion-date');
      final picker = find.byType(DatePickerDialog);
      expect(
        tester.widget<DatePickerDialog>(picker).initialDate,
        DateTime(2027, 1, 15),
      );
      await tester.tap(
        find.widgetWithText(
          TextButton,
          MaterialLocalizations.of(tester.element(picker)).cancelButtonLabel,
        ),
      );
      await tester.pumpAndSettle();
      await app.setLocale(const Locale('zh'));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('api-request-timing'));
      expect(
        tester.widget<TextFormField>(field).controller!.text,
        MaterialLocalizations.of(
          tester.element(field),
        ).formatShortDate(DateTime(2027, 1, 15)),
      );
      await tapKey(tester, 'api-save-draft');
      expect(repo.saved!.timing, '2027-01-15');
      await tapKey(tester, 'api-submit-request');
      expect(repo.submitted!.timing, '2027-01-15');
      expect(tester.takeException(), isNull);
    },
  );

  for (final previous in ['下个月', '2026-02-31']) {
    testWidgets(
      'legacy or invalid date "$previous" is preserved in draft and requires selection',
      (tester) async {
        final repo = LiveUiRepository()
          ..saved = RequestDraft(
            description: '开发内部信息管理系统并保留历史原文。',
            timing: previous,
            budget: 'JPY 相談',
          );
        final app = AppController(repo);
        addTearDown(app.dispose);
        await app.setLocale(const Locale('zh'));
        await tester.pumpWidget(host(app, ApiRequestPage(app: app)));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const Key('api-request-timing')),
              )
              .controller!
              .text,
          previous,
        );
        await tapKey(tester, 'api-save-draft');
        expect(repo.saved!.timing, previous);
        await tapKey(tester, 'api-submit-request');
        expect(repo.submitted, isNull);
        final selected = await chooseCompletionDate(tester);
        await tapKey(tester, 'api-submit-request');
        expect(repo.submitted!.timing, iso(selected));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in ['ja', 'zh']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'completion calendar fits 320px $language $brightness with large text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 740);
          tester.platformDispatcher.textScaleFactorTestValue = 1.4;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final repo = LiveUiRepository();
          final app = AppController(repo);
          addTearDown(app.dispose);
          await app.setLocale(Locale(language));
          await tester.pumpWidget(
            host(app, ApiRequestPage(app: app), brightness: brightness),
          );
          await tester.pumpAndSettle();
          final selected = await chooseCompletionDate(tester, day: 15);
          await tapKey(tester, 'api-save-draft');
          expect(repo.saved!.timing, iso(selected));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
