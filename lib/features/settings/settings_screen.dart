import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/category_icons.dart';
import '../ledger/ledger_errors.dart';

const _currencyNames = {'CNY': 'Yuan', 'PKR': 'Rupees', 'USD': 'Dollars'};

final _categoriesProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .select(db.categories)
      .watch()
      .map((rows) => rows..sort((a, b) => a.id.compareTo(b.id)));
});

final _versionProvider = FutureProvider.autoDispose<String>((ref) async {
  return (await PackageInfo.fromPlatform()).version;
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool archivedOpen = false;
  bool savingCurrency = false;
  final restoring = <int>{};
  final restoreErrors = <int, String>{};

  AppColors get colors => Theme.of(context).extension<AppColors>()!;
  TextTheme get text => Theme.of(context).textTheme;
  TextStyle get muted => text.bodyMedium!.copyWith(color: colors.muted);

  Future<void> pickCurrency(String current) async {
    if (savingCurrency) return;
    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.surface,
      barrierColor: colors.onBrass.withValues(alpha: .5),
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Main currency', style: text.titleLarge),
              ),
              for (final entry in _currencyNames.entries)
                row(
                  title: Text('${entry.value} ${entry.key}'),
                  trailing: entry.key == current
                      ? PhosphorIcon(
                          PhosphorIconsRegular.check,
                          color: colors.ink,
                        )
                      : null,
                  onTap: () => Navigator.pop(sheet, entry.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (selection == null || selection == current || !mounted) return;

    setState(() => savingCurrency = true);
    try {
      final db = ref.read(databaseProvider);
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(key: 'mainCurrency', value: selection),
          );
    } finally {
      if (mounted) setState(() => savingCurrency = false);
    }
  }

  Future<void> openCategory(String kind, {Category? category}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: colors.surface,
        barrierColor: colors.onBrass.withValues(alpha: .5),
        builder: (_) => _CategorySheet(kind: kind, category: category),
      );

  Future<void> unarchive(Category category) async {
    setState(() {
      restoring.add(category.id);
      restoreErrors.remove(category.id);
    });
    try {
      await ref.read(categoryServiceProvider).unarchiveCategory(category.id);
    } on LedgerException catch (error) {
      if (mounted) setState(() => restoreErrors[category.id] = error.message);
    } finally {
      if (mounted) setState(() => restoring.remove(category.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final main = ref.watch(mainCurrencyProvider);
    final categories = ref.watch(_categoriesProvider);
    final version = ref.watch(_versionProvider).value;
    final active = categories.value?.where((category) => !category.archived);
    final archived =
        categories.value?.where((category) => category.archived).toList() ??
        const <Category>[];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              context.go('/wealth');
            }
          },
          icon: PhosphorIcon(
            PhosphorIconsRegular.caretLeft,
            color: colors.ink,
            size: 18,
          ),
        ),
        title: const Text('Settings'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
          children: [
            if (main.value case final currency?)
              row(
                title: Text('Main currency', style: muted),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: _currencyNames[currency] ?? currency,
                        children: [
                          if (_currencyNames.containsKey(currency))
                            TextSpan(text: ' $currency', style: muted),
                        ],
                      ),
                      style: text.titleSmall,
                    ),
                    const SizedBox(width: 8),
                    caret(),
                  ],
                ),
                onTap: savingCurrency ? null : () => pickCurrency(currency),
              )
            else if (main.hasError)
              const Text('Could not load the main currency.'),
            if (categories.hasError) const Text('Could not load categories.'),
            if (active != null)
              for (final kind in ['expense', 'income']) ...[
                heading(
                  kind == 'expense'
                      ? 'Expense categories'
                      : 'Income categories',
                ),
                for (final category in active.where(
                  (item) => item.kind == kind,
                ))
                  row(
                    key: ValueKey('category-${category.id}'),
                    leading: categoryGlyph(category.iconKey),
                    title: Text(category.name),
                    trailing: caret(),
                    onTap: () => openCategory(kind, category: category),
                  ),
                row(
                  key: ValueKey('add-category-$kind'),
                  leading: PhosphorIcon(
                    PhosphorIconsRegular.plus,
                    color: colors.muted,
                    size: 20,
                  ),
                  title: Text('Add category', style: muted),
                  onTap: () => openCategory(kind),
                ),
              ],
            if (archived.isNotEmpty) ...[
              const SizedBox(height: 14),
              Semantics(
                expanded: archivedOpen,
                child: row(
                  title: Text('Archived categories', style: muted),
                  trailing: caret(open: archivedOpen),
                  onTap: () => setState(() => archivedOpen = !archivedOpen),
                ),
              ),
              if (archivedOpen)
                for (final category in archived) ...[
                  row(
                    leading: categoryGlyph(category.iconKey),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.name),
                        Text(
                          category.kind == 'expense' ? 'Expense' : 'Income',
                          style: muted,
                        ),
                      ],
                    ),
                    trailing: TextButton(
                      onPressed: restoring.contains(category.id)
                          ? null
                          : () => unarchive(category),
                      child: const Text('Unarchive'),
                    ),
                  ),
                  if (restoreErrors[category.id] case final error?)
                    Text(error, style: muted.copyWith(color: colors.warning)),
                ],
            ],
            const SizedBox(height: 24),
            Text(
              version == null || version.isEmpty ? 'Hazir' : 'Hazir $version',
              style: text.bodySmall!.copyWith(color: colors.muted),
            ),
            Text(
              'Rates by ExchangeRate-API',
              style: text.bodySmall!.copyWith(color: colors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget heading(String title) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 6),
    child: Semantics(header: true, child: Text(title, style: muted)),
  );

  Widget caret({bool open = false}) => PhosphorIcon(
    open ? PhosphorIconsRegular.caretDown : PhosphorIconsRegular.caretRight,
    size: 14,
    color: colors.muted,
  );

  Widget categoryGlyph(String key) => PhosphorIcon(
    categoryIcon(key),
    color: colors.muted,
    size: 20,
    duotoneSecondaryColor: colors.muted,
    duotoneSecondaryOpacity: .2,
  );

  Widget row({
    Key? key,
    Widget? leading,
    required Widget title,
    Widget? trailing,
    VoidCallback? onTap,
  }) => Column(
    key: key,
    children: [
      InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Row(
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 10)],
              Expanded(child: title),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
        ),
      ),
      Divider(height: .7, thickness: .7, color: colors.rule),
    ],
  );
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({required this.kind, this.category});
  final String kind;
  final Category? category;

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
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
      await service.createCategory(
        name: name.text,
        kind: widget.kind,
        iconKey: iconKey,
      );
    } else {
      await service.renameCategory(id, name.text);
    }
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
    await submit(
      () => ref
          .read(categoryServiceProvider)
          .archiveCategory(widget.category!.id),
    );
  }

  Future<void> submit(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) Navigator.pop(context);
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
              ] else
                TextButton(
                  onPressed: busy ? null : archive,
                  child: const Text('Archive'),
                ),
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
