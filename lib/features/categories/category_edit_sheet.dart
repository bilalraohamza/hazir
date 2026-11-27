import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/category_icons.dart';
import '../../ui/widgets/deletion_feedback.dart';
import '../ledger/deletion_service.dart';
import '../ledger/ledger_errors.dart';

class CategoryEditSheet extends ConsumerStatefulWidget {
  const CategoryEditSheet({super.key, required this.kind, this.category});

  static Future<int?> show(
    BuildContext context, {
    required String kind,
    Category? category,
  }) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colors.surface,
      barrierColor: colors.onBrass.withValues(alpha: .5),
      builder: (_) => CategoryEditSheet(kind: kind, category: category),
    );
  }

  final String kind;
  final Category? category;

  @override
  ConsumerState<CategoryEditSheet> createState() => CategoryEditSheetState();
}

class CategoryEditSheetState extends ConsumerState<CategoryEditSheet> {
  late final name = TextEditingController(text: widget.category?.name);
  String iconKey = 'tag';
  bool busy = false;
  String? error;

  AppColors get colors => Theme.of(context).extension<AppColors>()!;
  TextTheme get text => Theme.of(context).textTheme;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() => submit(() async {
    final service = ref.read(categoryServiceProvider);
    final id = widget.category?.id;
    if (id == null) {
      return service.createCategory(
        name: name.text,
        kind: widget.kind,
        iconKey: iconKey,
      );
    }
    await service.renameCategory(id, name.text);
    return id;
  });

  Future<void> archive() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: colors.onBrass.withValues(alpha: .5),
      builder: (dialog) => AlertDialog(
        backgroundColor: colors.surface,
        surfaceTintColor: colors.surface,
        shadowColor: colors.onBrass,
        title: const Text('Archive this category?'),
        content: const Text('Existing entries will keep this category.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = widget.category!.id;
    await submit(() async {
      await ref.read(categoryServiceProvider).archiveCategory(id);
      return id;
    });
  }

  Future<void> deleteCategory() async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final deletion = ref.read(deletionServiceProvider);
      final details = await deletion.categoryDeletionDetails(
        widget.category!.id,
      );
      if (!mounted) return;
      final Category? destination;
      if (details.entryCount == 0) {
        if (!await confirmEmptyCategory(details.category.name) || !mounted) {
          return;
        }
        destination = null;
      } else {
        destination = await chooseDestination(details);
        if (destination == null || !mounted) return;
      }
      final undo = deletionUndoFor(context);
      final receipt = await deletion.deleteCategory(
        details.category.id,
        moveToCategoryId: destination?.id,
      );
      final name = details.category.name;
      final movement = destination == null
          ? ''
          : ', ${entryCountLabel(details.entryCount)} moved to ${destination.name}';
      undo('$name deleted$movement', receipt);
      if (mounted) Navigator.pop(context);
    } on LedgerException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirmEmptyCategory(String name) async {
    return await showDialog<bool>(
          context: context,
          barrierColor: colors.onBrass.withValues(alpha: .5),
          builder: (dialog) => AlertDialog(
            backgroundColor: colors.surface,
            surfaceTintColor: colors.surface,
            shadowColor: colors.onBrass,
            title: Text('Delete $name?'),
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

  Future<Category?> chooseDestination(CategoryDeletionDetails details) {
    Category? destination;
    final count = details.entryCount;
    final subject = count == 1
        ? 'uses this category. Choose where it goes'
        : 'use this category. Choose where they go';
    final muted = text.bodyMedium!.copyWith(color: colors.muted);
    return showDialog<Category>(
      context: context,
      barrierColor: colors.onBrass.withValues(alpha: .5),
      builder: (dialog) => StatefulBuilder(
        builder: (context, select) => AlertDialog(
          scrollable: true,
          backgroundColor: colors.surface,
          surfaceTintColor: colors.surface,
          shadowColor: colors.onBrass,
          title: Text('Delete ${details.category.name}?'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${entryCountLabel(count)} $subject, so your spending history stays correct.',
              ),
              const SizedBox(height: 12),
              Text('Move entries to', style: muted),
              DropdownButton<Category>(
                key: const ValueKey('move-category-picker'),
                dropdownColor: colors.surface,
                underline: Divider(height: .7, color: colors.rule),
                isExpanded: true,
                icon: PhosphorIcon(
                  PhosphorIconsRegular.caretDown,
                  size: 14,
                  color: colors.muted,
                ),
                value: destination,
                hint: const Text('Choose a category'),
                items: [
                  for (final category in details.destinations)
                    DropdownMenuItem(
                      value: category,
                      child: Text(category.name),
                    ),
                ],
                onChanged: details.destinations.isEmpty
                    ? null
                    : (choice) => select(() => destination = choice),
              ),
              if (details.destinations.isEmpty)
                Text(
                  'Add another category of this type or archive this one.',
                  style: muted,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: deleteButtonStyle(),
              onPressed: destination == null
                  ? null
                  : () => Navigator.pop(dialog, destination),
              child: Text('Move ${entryCountLabel(count)} and delete'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> submit(Future<int> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = await action();
      if (mounted) Navigator.pop(context, id);
    } on LedgerException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.category == null;
    final muted = text.bodyMedium!.copyWith(color: colors.muted);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      adding ? 'Add category' : 'Edit category',
                      style: text.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: PhosphorIcon(
                      PhosphorIconsRegular.x,
                      color: colors.ink,
                    ),
                  ),
                ],
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Text('Name', style: muted),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('category-name'),
                        enabled: !busy,
                        controller: name,
                        textAlign: TextAlign.end,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration.collapsed(
                          hintText: 'Category name',
                          hintStyle: muted,
                        ),
                        onChanged: (_) => setState(() => error = null),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: .7, thickness: .7, color: colors.rule),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    error!,
                    style: muted.copyWith(color: colors.warning),
                  ),
                ),
              if (adding) ...[
                const SizedBox(height: 14),
                Text('Icon', style: muted),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 6,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  mainAxisExtent: 44,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final choice in categoryIconChoices.entries)
                      Tooltip(
                        message: choice.value.label,
                        child: Semantics(
                          selected: iconKey == choice.key,
                          button: true,
                          child: Material(
                            color: iconKey == choice.key
                                ? colors.brass
                                : colors.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: colors.rule, width: .7),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: ValueKey('category-icon-${choice.key}'),
                              onTap: busy
                                  ? null
                                  : () => setState(() => iconKey = choice.key),
                              child: Center(
                                child: PhosphorIcon(
                                  choice.value.icon,
                                  color: iconKey == choice.key
                                      ? colors.onBrass
                                      : colors.muted,
                                  duotoneSecondaryColor: iconKey == choice.key
                                      ? colors.onBrass
                                      : colors.muted,
                                  duotoneSecondaryOpacity: .2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ] else ...[
                TextButton(
                  onPressed: busy ? null : archive,
                  child: const Text('Archive'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: colors.warning),
                  onPressed: busy ? null : deleteCategory,
                  child: const Text('Delete category'),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  backgroundColor: colors.brass,
                  foregroundColor: colors.onBrass,
                ),
                onPressed: busy ? null : save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
