import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_colors.dart';

class PageHeader extends StatelessWidget implements PreferredSizeWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.titleSpacing = 18,
  });

  final Widget title;
  final VoidCallback? onBack;
  final double titleSpacing;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: preferredSize.height,
      titleSpacing: onBack == null ? titleSpacing : 0,
      leading: onBack == null
          ? null
          : IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: PhosphorIcon(
                PhosphorIconsRegular.caretLeft,
                color: colors.ink,
                size: 18,
              ),
            ),
      title: title,
      actions: [
        if (onBack == null) ...[
          SizedBox.square(
            dimension: 48,
            child: IconButton(
              tooltip: 'Settings',
              onPressed: () => context.push('/settings'),
              icon: PhosphorIcon(
                PhosphorIconsDuotone.gearSix,
                color: colors.muted,
                duotoneSecondaryColor: colors.muted,
                duotoneSecondaryOpacity: .2,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }
}
