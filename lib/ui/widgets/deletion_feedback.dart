import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../features/ledger/deletion_service.dart';
import '../../features/ledger/deletion_texts.dart';
import '../theme/app_colors.dart';

ButtonStyle deleteButtonStyle() => FilledButton.styleFrom(
  backgroundColor: AppColors.light.warning,
  foregroundColor: AppColors.light.surface,
);

Future<bool> confirmEntryDeletion(BuildContext context) async {
  final colors = Theme.of(context).extension<AppColors>()!;
  return await showDialog<bool>(
        context: context,
        barrierColor: colors.onBrass.withValues(alpha: .5),
        builder: (dialog) => AlertDialog(
          backgroundColor: colors.surface,
          surfaceTintColor: colors.surface,
          shadowColor: colors.onBrass,
          title: Text(entryDeletionText.warning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: deleteButtonStyle(),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(entryDeletionText.confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

String deletedEntryMessage(String? note) {
  final label = note?.trim();
  return label == null || label.isEmpty ? 'Entry deleted' : '$label deleted';
}

void Function(String, DeletionReceipt) deletionUndoFor(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  final colors = Theme.of(context).extension<AppColors>()!;
  return (message, receipt) {
    if (!messenger.mounted) return;
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        backgroundColor: colors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.rule, width: .7),
        ),
        content: Row(
          children: [
            PhosphorIcon(
              PhosphorIconsDuotone.trash,
              size: 18,
              color: colors.muted,
              duotoneSecondaryColor: colors.muted,
              duotoneSecondaryOpacity: .2,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: TextStyle(color: colors.ink)),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.brass,
                foregroundColor: colors.onBrass,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
              ),
              onPressed: () async {
                messenger.hideCurrentSnackBar();
                try {
                  await receipt.restore();
                } catch (_) {
                  if (messenger.mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: colors.surface,
                        content: Text(
                          'Could not undo this deletion.',
                          style: TextStyle(color: colors.ink),
                        ),
                      ),
                    );
                  }
                }
              },
              child: const Text('Undo'),
            ),
          ],
        ),
      ),
    );
  };
}
