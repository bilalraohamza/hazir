import 'package:budget_app/app/providers.dart';
import 'package:budget_app/features/entry/entry_form_screen.dart';
import 'package:budget_app/core/money/money.dart';
import 'package:budget_app/data/db/app_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/shell_fixture.dart';

void main() {
  late ShellFixture fixture;
  setUp(() {
    fixture = ShellFixture();
    addTearDown(fixture.db.close);
  });

  Future<void> open(
    WidgetTester t, {
    bool editing = false,
    bool history = false,
  }) async {
    await t.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(fixture.build());
    await t.pumpAndSettle();
    await t.tap(find.text('Chat'));
    await t.pumpAndSettle();
    if (history) {
      final ledger = ProviderScope.containerOf(
        t.element(find.byTooltip('Add entry')),
      ).read(ledgerServiceProvider);
      for (final id in [8, 8, 3]) {
        final insert = ledger.addExpense(
          accountId: 1,
          categoryId: id,
          amount: const Money(100, 'CNY'),
          at: DateTime.now().subtract(const Duration(days: 2)),
        );
        await t.pumpAndSettle();
        await insert;
      }
    }
    if (editing) {
      final context = t.element(find.byTooltip('Add entry'));
      final ledger = ProviderScope.containerOf(context)
          .read(ledgerServiceProvider);
      final insert = ledger.addExpense(
        accountId: 1,
        categoryId: 1,
        amount: const Money(150, 'CNY'),
      );
      await t.pumpAndSettle();
      final id = await insert;
      Navigator.of(
        t.element(find.byTooltip('Add entry')),
        rootNavigator: true,
      ).push(
        MaterialPageRoute<void>(
          builder: (_) => EntryFormScreen(editTransactionId: id),
        ),
      );
    } else {
      await t.tap(find.byTooltip('Add entry'));
    }
    await t.pumpAndSettle();
  }

  Future<List<Transaction>> rows(WidgetTester t) async {
    final read = fixture.db.select(fixture.db.transactions).get();
    await t.pump();
    return read;
  }

  Future<void> tap(WidgetTester t, String label) async {
    final item = find.text(label).last;
    await t.ensureVisible(item);
    await t.pumpAndSettle();
    await t.tap(item);
    await t.pumpAndSettle();
  }

  testWidgets('saving 28 Food WeChat creates one expense', (t) async {
    await open(t);
    await t.enterText(find.byKey(const Key('Amount')), '28');
    await tap(t, 'Save');
    final row = (await rows(t)).single;
    expect(
      [row.kind, row.amountMinor, row.accountId, row.categoryId],
      ['expense', 2800, 1, 1],
    );
    expect(find.byType(EntryFormScreen), findsNothing);
  });

  testWidgets('zero amount keeps the form open and saves nothing', (t) async {
    await open(t);
    await t.enterText(find.byKey(const Key('Amount')), '0');
    await tap(t, 'Save');
    expect(find.text('The amount must be greater than zero.'), findsOneWidget);
    expect(await rows(t), isEmpty);
  });

  testWidgets(
    'income uses its category and reports a malformed amount inline',
    (t) async {
      await open(t);
      await tap(t, 'Income');
      expect(find.text('Scholarship/Stipend'), findsOneWidget);
      final amount = find.byKey(const Key('Amount'));
      await t.enterText(amount, '1.2.3');
      await tap(t, 'Save');
      expect(find.text('Invalid amount for CNY'), findsOneWidget);
      expect(await rows(t), isEmpty);
      await t.enterText(amount, '7.25');
      await tap(t, 'Save');
      final saved = (await rows(t)).single;
      expect(
        [saved.kind, saved.amountMinor, saved.categoryId],
        ['income', 725, 13],
      );
    },
  );

  testWidgets(
    'PKR to CNY transfer stores 122 received and supports rate overrides',
    (t) async {
      await open(t);
      await tap(t, 'Transfer');
      expect(find.byKey(const Key('Received')), findsNothing);
      expect(find.byKey(const Key('Rate')), findsNothing);
      await tap(t, 'From');
      await tap(t, 'Pakistani bank, PKR');
      await t.enterText(find.byKey(const Key('Amount')), '5000');
      await tap(t, 'Rate');
      await t.enterText(find.byKey(const Key('Rate')), '0.025');
      expect(
        t.widget<TextField>(find.byKey(const Key('Received'))).controller!.text,
        '125.00',
      );
      await t.enterText(find.byKey(const Key('Received')), '122');
      await t.pumpAndSettle();
      expect(find.text('0.0244'), findsOneWidget);
      await tap(t, 'Save');
      final row = (await rows(t)).single;
      expect(
        [row.currency, row.toCurrency, row.toAmountMinor],
        ['PKR', 'CNY', 12200],
      );
    },
  );

  testWidgets('editing prefills and replaces the original transaction', (
    t,
  ) async {
    await open(t, editing: true);
    final field = t.widget<TextField>(find.byKey(const Key('Amount')));
    final span = field.controller!.buildTextSpan(
      context: t.element(find.byKey(const Key('Amount'))),
      style: field.style,
      withComposing: false,
    );
    expect(span.toPlainText(), '1.50');
    expect((span.children!.last as TextSpan).text, '.50');
    expect(span.children!.last.style!.fontSize, 30);
    await t.enterText(find.byKey(const Key('Amount')), '3');
    await tap(t, 'Save');
    expect((await rows(t)).single.amountMinor, 300);
  });

  testWidgets('deleting an entry requires confirmation', (t) async {
    await open(t, editing: true);
    await tap(t, 'Delete');
    await tap(t, 'Cancel');
    expect(await rows(t), hasLength(1));
    await tap(t, 'Delete');
    await tap(t, 'Delete');
    expect(await rows(t), isEmpty);
  });

  testWidgets('More brings a selected category into the grid', (t) async {
    await open(t);
    expect(find.text('Gifts'), findsNothing);
    await tap(t, 'More');
    await t.drag(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListView),
      ),
      const Offset(0, -300),
    );
    await t.pumpAndSettle();
    await tap(t, 'Gifts');
    expect(find.text('Gifts'), findsOneWidget);
    await t.enterText(find.byKey(const Key('Amount')), '1');
    await tap(t, 'Save');
    expect((await rows(t)).single.categoryId, 10);
  });
  testWidgets('recent category use ranks grid tiles before starter order', (
    t,
  ) async {
    await open(t, history: true);
    final labels = t
        .widgetList<Text>(
          find.descendant(
            of: find.byType(GridView),
            matching: find.byType(Text),
          ),
        )
        .map((w) => w.data);
    expect(labels.take(3), ['Health', 'Transport', 'Food']);
  });
  testWidgets(
    'transfer card rounds the displayed rate and hides an unavailable quote',
    (t) async {
      await open(t);
      await tap(t, 'Transfer');
      await tap(t, 'From');
      await tap(t, 'Pakistani bank, PKR');
      await t.enterText(find.byKey(const Key('Amount')), '3');
      await t.enterText(find.byKey(const Key('Received')), '2');
      await t.pumpAndSettle();
      expect(find.text('Alipay receives'), findsOneWidget);
      expect(find.text('0.666667'), findsOneWidget);
      expect(find.textContaining("Today's rate would give"), findsNothing);
      expect(find.text('Tap either number to change it.'), findsOneWidget);
    },
  );

  testWidgets(
    'rounded rate display preserves exact received minor units on save',
    (t) async {
      await open(t);
      await tap(t, 'Transfer');
      await tap(t, 'From');
      await tap(t, 'Pakistani bank, PKR');
      await t.enterText(find.byKey(const Key('Amount')), '500000');
      await t.enterText(find.byKey(const Key('Received')), '122.01');
      await t.pumpAndSettle();
      expect(find.text('0.000244'), findsOneWidget);
      await tap(t, 'Save');
      expect((await rows(t)).single.toAmountMinor, 12201);
    },
  );
}
