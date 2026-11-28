import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/category_icons.dart';
import '../../ui/widgets/page_header.dart';
import '../ledger/ledger_errors.dart';
import '../categories/category_edit_sheet.dart';

import 'theme_control.dart';

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

  Future<void> openCategory(String kind, {Category? category}) async {
    await CategoryEditSheet.show(context, kind: kind, category: category);
  }

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
      appBar: PageHeader(
        onBack: () {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
          } else {
            context.go('/wealth');
          }
        },
        title: const Text('Settings'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
          children: [
            row(
              title: Text('Theme', style: muted),
              trailing: const ThemeControl(),
            ),
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
