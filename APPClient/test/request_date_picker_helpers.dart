import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DateTime> chooseCompletionDate(WidgetTester tester, {int? day}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final field = find.byKey(const Key('api-request-timing'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  final picker = find.byType(DatePickerDialog);
  final initial = tester.widget<DatePickerDialog>(picker).initialDate!;
  if (day != null) {
    await tester.tap(find.text('$day').last);
    await tester.pumpAndSettle();
  }
  final context = tester.element(picker);
  await tester.tap(
    find.widgetWithText(
      TextButton,
      MaterialLocalizations.of(context).okButtonLabel,
    ),
  );
  await tester.pumpAndSettle();
  return DateTime(initial.year, initial.month, day ?? initial.day);
}
