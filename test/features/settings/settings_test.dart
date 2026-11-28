import 'package:budget_app/core/money/money.dart';
import 'package:budget_app/features/fx/fx_service.dart';
import 'package:budget_app/features/ledger/ledger_service.dart';
import 'package:budget_app/ui/widgets/amount_text.dart';
import 'package:budget_app/ui/theme/app_colors.dart';
import 'package:budget_app/features/settings/theme_control.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../../app/shell_fixture.dart';

void main() {
  late ShellFixture fixture;
  late LedgerService ledger;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Hazir',
      packageName: 'com.rao.budget_app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    fixture = ShellFixture();
    addTearDown(fixture.db.close);
    await fixture.db.seedIfEmpty();
    final fx = FxService(fixture.db, fixture.api, clock: () => fixture.now);
    ledger = LedgerService(fixture.db, fx);
  });

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  Future<void> settingsRow(
    WidgetTester tester,
    Finder row, {
    double delta = 230,
  }) async {
    await tester.scrollUntilVisible(
      row,
      delta,
      scrollable: find.byType(Scrollable),
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tap(tester, row);
  }

  Future<void> entry(WidgetTester tester) async {
    await tap(tester, find.text('Chat'));
    await tap(tester, find.byTooltip('Add entry'));
  }

  Iterable<String?> pickerLabels(WidgetTester tester) {
    final list = tester.widget<ListView>(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListView),
      ),
    );
    return (list.childrenDelegate as SliverChildListDelegate).children
        .whereType<ListTile>()
        .map((tile) => (tile.title! as Text).data);
  }

  testWidgets(
    'main currency picker switches Wealth and already opened Spending to PKR',
    (tester) async {
      await tester.runAsync(
        () => ledger.addExpense(
          accountId: 5,
          categoryId: 1,
          amount: const Money(150000, 'PKR'),
        ),
      );
      await open(tester);
      await tap(tester, find.text('Spending'));
      final spending = key('spending-total');
      expect(tester.widget<AmountText>(spending).m.currency, 'CNY');
      await tap(tester, find.byTooltip('Settings'));
      await tap(tester, find.text('Main currency'));
      await tap(tester, find.text('Rupees PKR'));
      await tap(tester, find.byTooltip('Back'));
      expect(tester.widget<AmountText>(spending).m, const Money(150000, 'PKR'));
      await tap(tester, find.text('Wealth'));
      expect(find.text('Everything you have, in rupees'), findsOneWidget);
      expect(
        tester.widget<AmountText>(key('wealth-total')).m,
        const Money(-150000, 'PKR'),
      );
    },
  );

  testWidgets(
    'renaming expense Other updates the picker and leaves income Other intact',
    (tester) async {
      await open(tester);
      await tap(tester, find.byTooltip('Settings'));
      await tap(tester, find.text('Categories'));
      await settingsRow(tester, key('category-12'));
      await tester.enterText(key('category-name'), 'Food');
      await tap(tester, find.text('Save'));
      expect(
        find.text('A category of this type already has this name.'),
        findsOneWidget,
      );
      await tester.enterText(key('category-name'), 'Misc');
      await tap(tester, find.text('Save'));
      await tap(tester, find.byTooltip('Back'));
      await tap(tester, find.byTooltip('Back'));
      await entry(tester);
      await tap(tester, find.text('More'));
      expect(pickerLabels(tester), contains('Misc'));
      expect(pickerLabels(tester), isNot(contains('Other')));
      await tester.tapAt(const Offset(20, 80));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Income'));
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Misc'), findsNothing);
    },
  );

  testWidgets(
    'archiving hides Food from both pickers and retains it in historical Spending',
    (tester) async {
      await tester.runAsync(
        () => ledger.addExpense(
          accountId: 1,
          categoryId: 1,
          amount: const Money(2800, 'CNY'),
        ),
      );
      await open(tester);
      await tap(tester, find.byTooltip('Settings'));
      await tap(tester, find.text('Categories'));
      await tap(tester, key('category-1'));
      await tap(tester, find.text('Archive'));
      await tap(tester, find.text('Cancel'));
      expect(find.text('Edit category'), findsOneWidget);
      await tap(tester, find.text('Archive'));
      await tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Archive'),
        ),
      );
      await tap(tester, find.byTooltip('Back'));
      await tap(tester, find.byTooltip('Back'));
      await entry(tester);
      expect(find.text('Food'), findsNothing);
      await tap(tester, find.text('More'));
      expect(pickerLabels(tester), isNot(contains('Food')));
      await tester.tapAt(const Offset(20, 80));
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Close'));
      await tap(tester, find.text('Spending'));
      expect(find.text('Food'), findsOneWidget);
      expect(
        tester.widget<AmountText>(key('spending-total')).m,
        const Money(2800, 'CNY'),
      );
      await tap(tester, find.byTooltip('Settings'));
      await tap(tester, find.text('Categories'));
      await settingsRow(tester, find.text('Archived categories'));
      await settingsRow(tester, find.text('Unarchive'));
      expect(find.text('Archived categories'), findsNothing);
      await settingsRow(tester, key('category-1'), delta: -230);
      expect(find.text('Edit category'), findsOneWidget);
    },
  );

  testWidgets(
    'adding a category saves the selected icon and displays it in Categories',
    (tester) async {
      await open(tester);
      await tap(tester, find.byTooltip('Settings'));
      await tap(tester, find.text('Categories'));
      await settingsRow(tester, key('add-category-expense'));
      await tester.enterText(key('category-name'), 'Cafeteria');
      await tap(tester, key('category-icon-coffee'));
      await tap(tester, find.text('Save'));
      expect(find.text('Cafeteria'), findsOneWidget);
      final categories = await tester.runAsync(
        () => fixture.db.select(fixture.db.categories).get(),
      );
      expect(
        categories!
            .singleWhere((category) => category.name == 'Cafeteria')
            .iconKey,
        'coffee',
      );
    },
  );

  testWidgets(
    'category deletion requires a destination and Undo returns moved entries',
    (tester) async {
      await tester.runAsync(
        () => ledger.addExpense(
          accountId: 1,
          categoryId: 1,
          amount: const Money(2800, 'CNY'),
        ),
      );
      await open(tester);
      await tap(tester, find.byTooltip('Settings'));
      await tap(tester, find.text('Categories'));
      await tap(tester, key('category-1'));
      await tap(tester, find.text('Delete category'));
      expect(
        find.text(
          '1 entry uses this category. Choose where it goes, so your spending history stays correct.',
        ),
        findsOneWidget,
      );
      final move = find.widgetWithText(FilledButton, 'Move 1 entry and delete');
      expect(
        find.ancestor(of: move, matching: find.byType(BottomSheet)),
        findsOneWidget,
      );
      expect(find.text('Move entries to'), findsOneWidget);
      expect(tester.widget<FilledButton>(move).onPressed, isNull);
      await tap(tester, key('move-category-picker'));
      await tap(tester, find.text('Groceries').last);
      final destination = find.descendant(
        of: key('move-category-picker'),
        matching: find.text('Groceries'),
      );
      final theme = Theme.of(tester.element(destination));
      expect(
        tester.widget<Text>(destination).style?.color,
        theme.extension<AppColors>()!.ink,
      );
      await tap(tester, move);
      expect(
        find.text('Food deleted, 1 entry moved to Groceries'),
        findsOneWidget,
      );
      expect(key('category-1'), findsNothing);
      await tap(tester, find.text('Undo'));
      expect(key('category-1'), findsOneWidget);
      await tap(tester, find.byTooltip('Back'));
      await tap(tester, find.byTooltip('Back'));
      await tap(tester, find.text('Spending'));
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
    },
  );

  testWidgets(
    'Settings shows Assistant, Appearance and Money and opens both management pages',
    (tester) async {
      await open(tester);
      await tap(tester, find.byTooltip('Settings'));
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where(
              (item) => item.properties.header == true && item.child is Text,
            )
            .map((item) => (item.child! as Text).data),
        ['Assistant', 'Appearance', 'Money'],
      );
      expect(
        find.text('Hazir 1.0.0. Rates by ExchangeRate-API'),
        findsOneWidget,
      );
      await tap(tester, find.text('Categories'));
      expect(find.text('Expense'), findsOneWidget);
      await tap(tester, find.byTooltip('Back'));
      await tap(tester, find.text('Accounts'));
      expect(find.text('Add account'), findsOneWidget);
    },
  );

  testWidgets('Accounts uses Wealth currency group names and colors', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.byTooltip('Settings'));
    await tap(tester, find.text('Accounts'));
    for (final (name, code) in [
      ('Yuan', 'CNY'),
      ('Rupees', 'PKR'),
      ('Dollars', 'USD'),
    ]) {
      final group = find.text(name);
      expect(group, findsOneWidget);
      final colors = Theme.of(tester.element(group)).extension<AppColors>()!;
      expect(
        tester.widget<Text>(group).style?.color,
        currencyColor(colors, code),
      );
    }
  });

  testWidgets('theme control aligns with Settings values in both themes', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.byTooltip('Settings'));
    for (final mode in ['Light', 'Dark']) {
      await tap(tester, find.text(mode));
      expect(
        tester.getRect(find.byType(ThemeControl)).right,
        tester.getRect(find.text('Yuan CNY')).right,
      );
    }
  });

  testWidgets('reordering accounts within CNY updates their order on Wealth', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.byTooltip('Settings'));
    await tap(tester, find.text('Accounts'));
    final handle = key('reorder-2');
    expect(handle, findsOneWidget);
    final drag = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 600));
    await drag.moveBy(const Offset(0, -16));
    await tester.pumpAndSettle();
    await drag.moveBy(const Offset(0, -25));
    await tester.pump(const Duration(milliseconds: 350));
    await drag.up();
    await tester.pumpAndSettle();
    final accounts = await tester.runAsync(
      () => fixture.db.select(fixture.db.accounts).get(),
    );
    expect(
      accounts!.singleWhere((item) => item.name == 'Alipay').sortOrder,
      lessThan(accounts.singleWhere((item) => item.name == 'WeChat').sortOrder),
    );
    await tap(tester, find.byTooltip('Back'));
    await tap(tester, find.byTooltip('Back'));
    expect(
      tester.getTopLeft(find.text('Alipay')).dy,
      lessThan(tester.getTopLeft(find.text('WeChat')).dy),
    );
  });
}
