import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_colors.dart';

class AddEntryButton extends StatelessWidget {
  const AddEntryButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return FloatingActionButton(
      heroTag: null,
      tooltip: 'Add entry',
      backgroundColor: colors.brass,
      foregroundColor: colors.onBrass,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onPressed: onPressed,
      child: const PhosphorIcon(PhosphorIconsRegular.plus),
    );
  }
}
