import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../ui/theme/app_colors.dart';

class ThemeControl extends ConsumerWidget {
  const ThemeControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final colors = Theme.of(context).extension<AppColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.rule.withValues(alpha: .4),
          colors.ground,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              Semantics(
                selected: mode == selected,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: mode == selected ? colors.brass : null,
                    foregroundColor: mode == selected
                        ? colors.onBrass
                        : colors.muted,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    final db = ref.read(databaseProvider);
                    await db
                        .into(db.settings)
                        .insertOnConflictUpdate(
                          SettingsCompanion.insert(
                            key: 'themeMode',
                            value: mode.name,
                          ),
                        );
                  },
                  child: Text(switch (mode) {
                    ThemeMode.system => 'System',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
