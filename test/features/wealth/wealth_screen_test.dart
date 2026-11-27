import 'package:budget_app/app/providers.dart';
import 'package:budget_app/core/money/money.dart';
import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/wealth/wealth_screen.dart';
import 'package:budget_app/ui/widgets/amount_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/shell_fixture.dart';

void main() {
  late ShellFixture fixture;
  const missingRates =
      "Exchange rates aren't available yet. Connect to the internet to see your full total.";

  setUp(() {
    fixture = ShellFixture();
    addTearDown(fixture.db.close);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
  }

  ProviderContainer providers(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(WealthScreen)));

  Future<void> waitFor(WidgetTester tester, Future<void> write) async {
    await tester.pumpAndSettle();
    await write;
    await tester.pumpAndSettle();
  }

  Finder amount(Money value) =>
      find.byWidgetPredicate((w) => w is AmountText && w.m == value);

  testWidgets('Yuan group shows a negative WeChat balance after an expense', (
    tester,
  ) async {
    await open(tester);
    await waitFor(
      tester,
      providers(tester)
          .read(ledgerServiceProvider)
          .addExpense(
            accountId: 1,
            categoryId: 1,
            amount: const Money(2800, 'CNY'),
          )
          .then((_) {}),
    );
    expect(find.text('Yuan'), findsOneWidget);
    expect(find.text('WeChat'), findsOneWidget);
    expect(amount(const Money(-2800, 'CNY')), findsWidgets);
  });

  testWidgets('missing rates show only the main subtotal in the header', (
    tester,
  ) async {
    await open(tester);
    final ledger = providers(tester).read(ledgerServiceProvider);
    await waitFor(
      tester,
      ledger
          .addIncome(
            accountId: 5,
            categoryId: 14,
            amount: const Money(5000000, 'PKR'),
          )
          .then((_) {}),
    );
    await waitFor(
      tester,
      ledger
          .addIncome(
            accountId: 1,
            categoryId: 14,
            amount: const Money(12200, 'CNY'),
          )
          .then((_) {}),
    );
    expect(find.text(missingRates), findsOneWidget);
    final header = tester.widget<AmountText>(
      find.byKey(const Key('wealth-total')),
    );
    expect(header.m, const Money(12200, 'CNY'));
    expect(header.showDecimals, isFalse);
    expect(find.byKey(const Key('currency-share-bar')), findsNothing);
    await tester.tap(find.text('By currency'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wealth-total')), findsNothing);
    expect(find.text(missingRates), findsNothing);
    final nativeTotal = tester.widget<AmountText>(
      find.byKey(const ValueKey('wealth-total-PKR')),
    );
    expect(nativeTotal.m, const Money(5000000, 'PKR'));
    expect(nativeTotal.size, 32);
    expect(find.textContaining('≈'), findsNothing);
  });

  testWidgets('adding Huabei in the account sheet updates the Yuan group', (
    tester,
  ) async {
    await open(tester);
    final add = find.text('Add account');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('account-name')), 'wechat');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('An active account already has this name.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('account-name')), 'Huabei');
    await tester.enterText(find.byKey(const Key('opening-balance')), '8.25');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Huabei'), findsOneWidget);
    expect(amount(const Money(825, 'CNY')), findsWidgets);
  });

  testWidgets('account edits update Wealth and archive requires confirmation', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('WeChat'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('account-name')), 'Wallet');
    await tester.enterText(find.byKey(const Key('opening-balance')), '-15.50');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Wallet'), findsOneWidget);
    expect(amount(const Money(-1550, 'CNY')), findsWidgets);
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit account'), findsOneWidget);
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Archive'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Wallet'), findsNothing);
  });

  testWidgets('combined shares use FX and archives keep their balances', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final db = fixture.db;
      for (final (code, rate) in [('CNY', '1'), ('PKR', '2')]) {
        await db
            .into(db.fxSnapshots)
            .insert(
              FxSnapshotsCompanion.insert(
                day: '2026-11-26',
                currency: code,
                perUsd: rate,
                fetchedAt: fixture.now,
              ),
            );
      }
    });
    fixture.now = fixture.now.add(const Duration(days: 1));
    await open(tester);
    final ledger = providers(tester).read(ledgerServiceProvider);
    await waitFor(
      tester,
      ledger
          .addIncome(
            accountId: 5,
            categoryId: 14,
            amount: const Money(20000, 'PKR'),
          )
          .then((_) {}),
    );
    await waitFor(
      tester,
      ledger
          .addIncome(
            accountId: 1,
            categoryId: 14,
            amount: const Money(2000, 'CNY'),
          )
          .then((_) {}),
    );
    expect(
      tester.widget<AmountText>(find.byKey(const Key('wealth-total'))).m.minor,
      12000,
    );
    expect(find.text('Rates from 26 Nov 2026'), findsOneWidget);
    expect(find.text('≈ ¥0.00'), findsNothing);
    expect(find.byKey(const Key('currency-share-bar')), findsOneWidget);
    final accounts = providers(tester).read(accountServiceProvider);
    await waitFor(tester, accounts.archiveAccount(5));
    expect(find.text('Pakistani bank'), findsNothing);
    expect(
      tester.widget<AmountText>(find.byKey(const Key('wealth-total'))).m,
      const Money(12000, 'CNY'),
    );
    final archived = find.text('Archived');
    await tester.ensureVisible(archived);
    await tester.tap(archived);
    await tester.pumpAndSettle();
    expect(find.text('Pakistani bank'), findsOneWidget);
    final restore = find.text('Unarchive');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text('Archived'), findsNothing);
  });

  testWidgets(
    'opening balance starts empty, limits decimals, and formats on blur',
    (tester) async {
      await open(tester);
      final add = find.text('Add account');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('opening-balance'));
      final controller = tester.widget<TextField>(field).controller!;
      expect(controller.text, isEmpty);
      expect(tester.widget<TextField>(field).decoration!.hintText, '0.00');
      await tester.enterText(field, '5000');
      expect(controller.text, '5000');
      await tester.enterText(field, '5000.12');
      await tester.enterText(field, '5000.123');
      expect(controller.text, '5000.12');
      await tester.tap(find.byKey(const Key('account-name')));
      await tester.pumpAndSettle();
      expect(controller.text, '5,000.12');
    },
  );

  testWidgets(
    'tapping an existing opening balance selects it for replacement',
    (tester) async {
      await open(tester);
      await waitFor(
        tester,
        providers(tester)
            .read(accountServiceProvider)
            .setOpeningBalance(1, const Money(500000, 'CNY')),
      );
      await tester.tap(find.text('WeChat'));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('opening-balance'));
      final controller = tester.widget<TextField>(field).controller!;
      expect(controller.text, '5,000.00');
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(controller.text, '5000.00');
      expect(
        controller.selection,
        TextSelection(baseOffset: 0, extentOffset: controller.text.length),
      );
      await tester.enterText(field, '−1.25');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(amount(const Money(-125, 'CNY')), findsWidgets);
    },
  );

  testWidgets(
    'account delete dialog counts entries and counterparties and Undo restores them',
    (tester) async {
      await open(tester);
      final ledger = providers(tester).read(ledgerServiceProvider);
      await waitFor(
        tester,
        ledger
            .addExpense(
              accountId: 1,
              categoryId: 1,
              amount: const Money(2800, 'CNY'),
            )
            .then((_) {}),
      );
      await waitFor(
        tester,
        ledger
            .addTransfer(
              fromAccountId: 1,
              toAccountId: 2,
              amount: const Money(1200, 'CNY'),
            )
            .then((_) {}),
      );
      await tester.tap(find.text('WeChat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete WeChat?'), findsOneWidget);
      expect(
        find.text(
          'This permanently deletes the account and its 2 entries, including 1 transfer with Alipay. Their balances will change.',
        ),
        findsOneWidget,
      );
      expect(find.text('Archive instead'), findsOneWidget);
      await tester.tap(find.text('Delete account and 2 entries'));
      await tester.pumpAndSettle();
      expect(find.text('WeChat'), findsNothing);
      expect(find.text('WeChat and 2 entries deleted'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('WeChat'), findsOneWidget);
      expect(amount(const Money(-4000, 'CNY')), findsWidgets);
      expect(amount(const Money(1200, 'CNY')), findsWidgets);
    },
  );
}
