import 'package:budget_app/features/entry/entry_form_screen.dart';
import 'package:budget_app/features/settings/settings_screen.dart';
import 'package:budget_app/features/spending/spending_screen.dart';
import 'package:budget_app/features/wealth/wealth_screen.dart';
import 'package:budget_app/ui/theme/app_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'shell_fixture.dart';

void main() {
  late ShellFixture fixture;
  setUp(() {
    fixture = ShellFixture();
    addTearDown(fixture.db.close);
  });
  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'opens Wealth and switches to Spending in ${brightness.name} mode',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await start(tester);
        final wealth = find.byType(WealthScreen);
        expect(wealth, findsOneWidget);
        final original = tester.element(wealth);
        final theme = Theme.of(original);
        expect(theme.brightness, brightness);
        final colors = theme.extension<AppColors>()!;
        final wallet = tester.widget<PhosphorIcon>(
          find.byWidgetPredicate(
            (w) => w is PhosphorIcon && w.icon == PhosphorIconsDuotone.wallet,
          ),
        );
        expect(wallet.color, colors.onBrass);
        expect(wallet.duotoneSecondaryOpacity, .3);
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Spending'));
        await tester.pumpAndSettle();
        expect(find.byType(SpendingScreen), findsOneWidget);
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Wealth'));
        await tester.pumpAndSettle();
        expect(tester.element(wealth), same(original));
      },
    );
  }
  testWidgets('Chat opens full-screen entry and accepts a transfer link', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add entry'));
    await tester.pumpAndSettle();
    final entry = find.byType(EntryFormScreen);
    expect(tester.widget<EntryFormScreen>(entry).initialKind, 'expense');
    expect(find.text('Upcoming'), findsNothing);
    GoRouter.of(tester.element(entry)).go('/entry?kind=transfer');
    await tester.pumpAndSettle();
    expect(tester.widget<EntryFormScreen>(entry).initialKind, 'transfer');
  });
  testWidgets('seeded shell opens during refresh and refreshes on resume', (
    tester,
  ) async {
    await start(tester);
    expect(find.byType(WealthScreen), findsOneWidget);
    final accounts = fixture.db.select(fixture.db.accounts).get();
    await tester.pump();
    expect(await accounts, hasLength(9));
    expect(fixture.api.calls, 1);
    fixture.api.response.complete({});
    await tester.pumpAndSettle();
    fixture.now = fixture.now.add(const Duration(days: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.api.calls, 2);
  });
}
