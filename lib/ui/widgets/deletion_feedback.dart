import 'package:material_ui/material_ui.dart';

import '../../features/ledger/deletion_service.dart';
import '../theme/app_colors.dart';

String entryCountLabel(int count) =>
    '$count ${count == 1 ? 'entry' : 'entries'}';

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
          title: const Text('Delete this entry?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: deleteButtonStyle(),
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Delete'),
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
        backgroundColor: colors.ink,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Expanded(
              child: Text(message, style: TextStyle(color: colors.ground)),
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
                        backgroundColor: colors.ink,
                        content: Text(
                          'Could not undo this deletion.',
                          style: TextStyle(color: colors.ground),
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
