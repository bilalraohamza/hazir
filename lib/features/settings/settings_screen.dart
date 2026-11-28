import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/page_header.dart';
import 'accounts_screen.dart';
import 'categories_screen.dart';

import 'theme_control.dart';

const _currencyNames = {'CNY': 'Yuan', 'PKR': 'Rupees', 'USD': 'Dollars'};

final _versionProvider = FutureProvider.autoDispose<String>((ref) async {
  return (await PackageInfo.fromPlatform()).version;
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool savingCurrency = false;

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

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(mainCurrencyProvider).value;
    final accounts = ref.watch(settingsAccountsProvider).value;
    final categories = ref.watch(settingsCategoriesProvider).value;
    final version = ref.watch(_versionProvider).value;
    return Scaffold(
      appBar: PageHeader(
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
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
            section('Appearance', [
              row(
                leading: glyph(PhosphorIconsDuotone.sun),
                title: const Text('Theme'),
                trailing: const ThemeControl(),
              ),
            ]),
            section('Money', [
              row(
                leading: glyph(PhosphorIconsDuotone.coins),
                title: const Text('Main currency'),
                trailing: value(
                  currency == null
                      ? ''
                      : '${_currencyNames[currency] ?? ''} $currency'.trim(),
                ),
                onTap: currency == null || savingCurrency
                    ? null
                    : () => pickCurrency(currency),
              ),
              row(
                leading: glyph(PhosphorIconsDuotone.wallet),
                title: const Text('Accounts'),
                trailing: value(
                  accounts?.where((row) => !row.archived).length.toString() ??
                      '',
                ),
                onTap: () => open(const AccountsScreen()),
              ),
              row(
                leading: glyph(PhosphorIconsDuotone.tag),
                title: const Text('Categories'),
                trailing: value(
                  categories?.where((row) => !row.archived).length.toString() ??
                      '',
                ),
                onTap: () => open(const CategoriesScreen()),
              ),
            ]),
            const SizedBox(height: 24),
            Text(
              '${version == null || version.isEmpty ? 'Hazir' : 'Hazir $version'}. Rates by ExchangeRate-API',
              textAlign: TextAlign.center,
              style: text.bodySmall!.copyWith(color: colors.muted),
            ),
          ],
        ),
      ),
    );
  }

  void open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget section(String title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Semantics(header: true, child: Text(title, style: muted)),
        ),
        Material(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.rule, width: .7),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (index, item) in rows.indexed) ...[
                if (index > 0)
                  Divider(height: .7, thickness: .7, color: colors.rule),
                item,
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget glyph(IconData icon) => PhosphorIcon(
    icon,
    color: colors.muted,
    size: 20,
    duotoneSecondaryColor: colors.muted,
    duotoneSecondaryOpacity: .2,
  );

  Widget value(String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: muted),
      const SizedBox(width: 8),
      PhosphorIcon(
        PhosphorIconsRegular.caretRight,
        color: colors.muted,
        size: 14,
      ),
    ],
  );

  Widget row({
    required Widget title,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 10)],
          Expanded(child: title),
          if (trailing != null) ...[const SizedBox(width: 4), trailing],
        ],
      ),
    ),
  );
}
