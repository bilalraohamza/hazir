import 'package:budget_app/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Budget app starts', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BudgetApp()));

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
