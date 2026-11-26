import 'package:budget_app/core/money/money.dart';
import 'package:budget_app/features/fx/fx_service.dart';
import 'package:budget_app/features/ledger/ledger_service.dart';
import 'package:budget_app/features/spending/spending_screen.dart';
import 'package:budget_app/ui/theme/app_theme.dart';
import 'package:budget_app/ui/widgets/amount_text.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/shell_fixture.dart';

void main() {
  late ShellFixture fixture;
  late FxService fx;
  late LedgerService ledger;
  final november = DateTime(2026, 11, 26, 15);
  final december = DateTime(2026, 12, 2, 15);

  setUp(() async {
    fixture = ShellFixture()..now = november;
    addTearDown(fixture.db.close);
    await fixture.db.seedIfEmpty();
    fx = FxService(fixture.db, fixture.api, clock: () => fixture.now);
    ledger = LedgerService(fixture.db, fx, clock: () => fixture.now);
  });

  Future<void> show(WidgetTester tester, {DateTime? today}) async {
    await tester.pumpWidget(
      fixture.build(
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: SpendingScreen(clock: () => today ?? november),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<int> expense(
    int amount, {
    int account = 1,
    int category = 1,
    String currency = 'CNY',
    DateTime? at,
    String? note,
  }) => ledger.addExpense(
    accountId: account,
    categoryId: category,
    amount: Money(amount, currency),
    at: at,
    note: note,
  );

  Money total(WidgetTester tester) =>
      tester.widget<AmountText>(find.byKey(const Key('spending-total'))).m;

  testWidgets('November categories sort by amount with counts and share bars', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await expense(1200);
      await expense(2500);
      await expense(600, category: 3);
    });
    await show(tester);
    expect(find.text('Spent in November'), findsOneWidget);
    expect(find.text('2 entries'), findsOneWidget);
    expect(find.text('1 entry'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Food')).dy,
      lessThan(tester.getTopLeft(find.text('Transport')).dy),
    );
    expect(total(tester), const Money(4300, 'CNY'));
    final foodBar = find.byKey(const ValueKey('spending-share-1'));
    expect(foodBar, findsOneWidget);
    expect(
      tester.widget<FractionallySizedBox>(foodBar).widthFactor,
      closeTo(37 / 43, .001),
    );
    expect(find.byKey(const ValueKey('spending-share-3')), findsOneWidget);
  });

  testWidgets(
    'switching from November to December shows the empty state and opens Add expense',
    (tester) async {
      await tester.runAsync(() => expense(2800));
      await show(tester, today: december);
      await tap(tester, find.byTooltip('Previous month'));
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      await tap(tester, find.byTooltip('Next month'));
      expect(
        find.text('No spending recorded in December 2026.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Add expense'));
      expect(find.text('New entry'), findsOneWidget);
      expect(find.text('Expense'), findsOneWidget);
    },
  );

  testWidgets('editing an entry recalculates the category and month totals', (
    tester,
  ) async {
    await tester.runAsync(() => expense(2800, note: 'Lunch'));
    await show(tester);
    await tap(tester, find.text('Food'));
    await tap(tester, find.text('Lunch'));
    expect(find.text('Edit entry'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('Amount')), '45');
    await tap(tester, find.text('Save'));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AmountText && widget.m == const Money(-4500, 'CNY'),
      ),
      findsOneWidget,
    );
    await tap(tester, find.byTooltip('Back'));
    expect(total(tester), const Money(4500, 'CNY'));
    final foodAmount = find.descendant(
      of: find.byKey(const ValueKey('spending-category-1')),
      matching: find.byType(AmountText),
    );
    expect(tester.widget<AmountText>(foodAmount).m, const Money(4500, 'CNY'));
  });

  testWidgets('unconverted expense note clears after a snapshot arrives', (
    tester,
  ) async {
    await tester.runAsync(() => expense(150000, account: 5, currency: 'PKR'));
    await show(tester);
    final note = find.text(
      "1 entries in other currencies aren't included yet. They'll be added when exchange rates are available.",
    );
    expect(note, findsOneWidget);
    expect(total(tester), const Money(0, 'CNY'));
    fixture.api.response.complete({
      'CNY': Decimal.one,
      'PKR': Decimal.fromInt(40),
    });
    await tester.runAsync(() => fx.refreshIfNeeded());
    await tester.pumpAndSettle();
    expect(note, findsNothing);
    expect(total(tester), const Money(3750, 'CNY'));
    await tap(tester, find.text('Food'));
    expect(find.text('Pakistani bank'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AmountText && widget.m == const Money(-150000, 'PKR'),
      ),
      findsOneWidget,
    );
    expect(find.text('≈ −¥37.50'), findsOneWidget);
  });

  testWidgets('next month is disabled for the current month', (tester) async {
    await show(tester);
    final button = find
        .byType(IconButton)
        .evaluate()
        .map((element) => element.widget as IconButton)
        .singleWhere((button) => button.tooltip == 'Next month');
    expect(button.onPressed, isNull);
    expect(find.text('November 2026'), findsOneWidget);
  });

  testWidgets(
    'category entries group by local day with note and account fallback',
    (tester) async {
      await tester.runAsync(() async {
        await expense(2800, at: DateTime(2026, 11, 26, 9), note: 'Lunch');
        await expense(1200, at: DateTime(2026, 11, 26, 18), note: 'Dinner');
        await expense(600, at: DateTime(2026, 11, 25, 23).toUtc());
        await expense(800, at: DateTime(2026, 11, 24, 22), note: 'Snack');
      });
      await show(tester);
      await tap(tester, find.text('Food'));
      for (final text in [
        'Today',
        'Yesterday',
        'Tue 24 Nov',
        'Lunch',
        'Dinner',
        'WeChat',
        'Snack',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(
        tester.getTopLeft(find.text('Dinner')).dy,
        lessThan(tester.getTopLeft(find.text('Lunch')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Lunch')).dy,
        lessThan(tester.getTopLeft(find.text('Yesterday')).dy),
      );
      expect(
        tester.getTopLeft(find.text('WeChat')).dy,
        lessThan(tester.getTopLeft(find.text('Tue 24 Nov')).dy),
      );
    },
  );
}
