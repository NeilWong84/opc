import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/data/mock_repository.dart';
import 'package:opc_app/main.dart';

void main() {
  testWidgets('app starts in Japanese without a Mock banner', (tester) async {
    final app = AppController(MockOpcRepository(delay: Duration.zero));
    await tester.pumpWidget(OpcApp(controller: app));
    expect(find.text('OPC'), findsOneWidget);
    expect(find.text('ログインする'), findsOneWidget);
    expect(find.byType(Banner), findsNothing);
    expect(find.text('日本語'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}
