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

  testWidgets('all five tabs align their 48-pixel settings button', (
    tester,
  ) async {
    await start(tester);
    final gear = find.byTooltip('Settings');
    final center = tester.getCenter(gear);
    expect(tester.getSize(gear), const Size(48, 48));
    for (final tab in ['Chat', 'Spending', 'Goals', 'Upcoming', 'Wealth']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.getCenter(gear), center, reason: tab);
    }
  });

  testWidgets(
    'Chat, Wealth and Spending align their add buttons and open preset kinds',
    (tester) async {
      await start(tester);
      final add = find.byTooltip('Add entry');
      final center = tester.getCenter(add);
      for (final (tab, kind) in [
        ('Wealth', 'transfer'),
        ('Chat', 'expense'),
        ('Spending', 'expense'),
      ]) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.getCenter(add), center, reason: tab);
        expect(tester.getSize(add), const Size(56, 56));
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EntryFormScreen>(find.byType(EntryFormScreen))
              .initialKind,
          kind,
        );
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
      }
    },
  );

  Future<void> openScrollableWealth(WidgetTester tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await start(tester);
  }

  final wealthScroll = find.descendant(
    of: find.byType(WealthScreen),
    matching: find.byType(Scrollable),
  );
  final addButton = find.byTooltip('Add entry');

  testWidgets(
    'Wealth last row clears the visible add button after scrolling to the bottom',
    (tester) async {
      await openScrollableWealth(tester);
      final position = tester.state<ScrollableState>(wealthScroll).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();

      final lastRow = find
          .ancestor(
            of: find.text('Add account'),
            matching: find.byType(InkWell),
          )
          .first;
      final button = tester.getRect(addButton);
      expect(
        button.bottom,
        lessThan(tester.getTopLeft(find.text('Upcoming')).dy),
      );
      expect(tester.getRect(lastRow).bottom, lessThanOrEqualTo(button.top));
    },
  );

  testWidgets(
    'scrolling down slides the add button out and scrolling up brings it back',
    (tester) async {
      await openScrollableWealth(tester);
      final original = tester.getRect(addButton);
      await tester.timedDrag(
        wealthScroll,
        const Offset(0, -180),
        const Duration(milliseconds: 100),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final partial = tester.getRect(addButton);
      expect(partial.top, greaterThan(original.top));
      expect(partial.top, lessThan(tester.getRect(wealthScroll).bottom));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(addButton).top,
        greaterThanOrEqualTo(tester.getRect(wealthScroll).bottom),
      );
      await tester.drag(wealthScroll, const Offset(0, 90));
      await tester.pumpAndSettle();
      expect(tester.getRect(addButton), original);

      await tester.drag(wealthScroll, const Offset(0, -120));
      await tester.pumpAndSettle();
      final position = tester.state<ScrollableState>(wealthScroll).position;
      position.jumpTo(position.minScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getRect(addButton), original);
    },
  );

  testWidgets(
    'reduced motion hides and shows the add button without animation',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openScrollableWealth(tester);
      final original = tester.getRect(addButton);
      await tester.timedDrag(
        wealthScroll,
        const Offset(0, -180),
        const Duration(milliseconds: 100),
      );
      await tester.pump();
      expect(
        tester.getRect(addButton).top,
        greaterThanOrEqualTo(tester.getRect(wealthScroll).bottom),
      );
      await tester.drag(wealthScroll, const Offset(0, 90));
      await tester.pump();
      expect(tester.getRect(addButton), original);
    },
  );

  testWidgets(
    'dark theme applies immediately and survives rebuilding the app',
    (tester) async {
      await start(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(SettingsScreen)))
            .extension<AppColors>(),
        AppColors.dark,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await start(tester);
      expect(
        Theme.of(tester.element(find.byType(WealthScreen)))
            .extension<AppColors>(),
        AppColors.dark,
      );
    },
  );
}
