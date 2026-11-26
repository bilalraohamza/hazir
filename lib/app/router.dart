import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../features/entry/entry_form_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/spending/spending_screen.dart';
import '../features/wealth/wealth_screen.dart';
import '../ui/theme/app_colors.dart';
import '../ui/widgets/placeholder_tab.dart';

const _tabs = [
  (
    label: 'Chat',
    icon: PhosphorIconsDuotone.chatCircleText,
    screen: PlaceholderTab('Chat', showAdd: true),
  ),
  (label: 'Wealth', icon: PhosphorIconsDuotone.wallet, screen: WealthScreen()),
  (
    label: 'Spending',
    icon: PhosphorIconsDuotone.chartPieSlice,
    screen: SpendingScreen(),
  ),
  (
    label: 'Goals',
    icon: PhosphorIconsDuotone.flagBanner,
    screen: PlaceholderTab('Goals'),
  ),
  (
    label: 'Upcoming',
    icon: PhosphorIconsDuotone.calendarDots,
    screen: PlaceholderTab('Upcoming'),
  ),
];

GoRouter buildRouter() => GoRouter(
  initialLocation: '/wealth',
  routes: [
    StatefulShellRoute.indexedStack(
      branches: [
        for (final tab in _tabs)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/${tab.label.toLowerCase()}',
                builder: (_, _) => tab.screen,
              ),
            ],
          ),
      ],
      builder: (_, _, shell) =>
          Scaffold(body: shell, bottomNavigationBar: _TabBar(shell)),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(
      path: '/entry',
      builder: (_, state) {
        final kind = state.uri.queryParameters['kind'];
        return EntryFormScreen(
          initialKind: kind == 'income' || kind == 'transfer'
              ? kind!
              : 'expense',
        );
      },
    ),
  ],
);

class _TabBar extends StatelessWidget {
  const _TabBar(this.shell);
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<AppColors>()!;
    return Material(
      color: c.ground,
      shape: Border(top: BorderSide(color: c.rule)),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final (index, tab) in _tabs.indexed)
              Expanded(
                child: Builder(
                  builder: (context) {
                    final active = shell.currentIndex == index;
                    final iconColor = active ? c.onBrass : c.muted;
                    return Semantics(
                      button: true,
                      selected: active,
                      child: InkWell(
                        onTap: () => shell.goBranch(index),
                        overlayColor: WidgetStatePropertyAll(
                          c.ink.withValues(alpha: .08),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 54,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: ShapeDecoration(
                                  color: active ? c.brass : null,
                                  shape: const StadiumBorder(),
                                ),
                                child: PhosphorIcon(
                                  tab.icon,
                                  size: 24,
                                  color: iconColor,
                                  duotoneSecondaryColor: iconColor,
                                  duotoneSecondaryOpacity: active ? .3 : .2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                tab.label,
                                style: theme.textTheme.labelMedium!.copyWith(
                                  color: active ? c.ink : c.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
