import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_colors.dart';

class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab(
    this.title, {
    super.key,
    this.showSettings = false,
    this.showAdd = false,
  });
  final String title;
  final bool showSettings;
  final bool showAdd;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        if (showSettings)
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: PhosphorIcon(
              PhosphorIconsDuotone.gearSix,
              color: Theme.of(context).extension<AppColors>()!.muted,
              duotoneSecondaryColor: Theme.of(context)
                  .extension<AppColors>()!
                  .muted,
              duotoneSecondaryOpacity: .2,
            ),
          ),
      ],
    ),
    body: const Center(child: Text('Coming in the next update')),
    floatingActionButton: showAdd
        ? FloatingActionButton(
            tooltip: 'Add entry',
            onPressed: () => context.push('/entry'),
            child: const PhosphorIcon(PhosphorIconsDuotone.plus),
          )
        : null,
  );
}
