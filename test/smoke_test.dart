import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'app/shell_fixture.dart';

void main() {
  testWidgets('Budget app starts', (tester) async {
    final fixture = ShellFixture();
    addTearDown(fixture.db.close);
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
