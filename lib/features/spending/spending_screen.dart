import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/providers.dart';
import '../../core/money/money.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/amount_text.dart';
import '../../ui/widgets/category_icons.dart';
import '../entry/entry_form_screen.dart';
import '../ledger/ledger_service.dart';
import 'category_entries_screen.dart';

final _spendingProvider = StreamProvider.autoDispose
    .family<List<CategorySpend>, DateTime>(
      (ref, month) => ref.watch(ledgerServiceProvider).watchSpending(month),
    );

class SpendingScreen extends ConsumerStatefulWidget {
  const SpendingScreen({super.key, this.clock});
  final DateTime Function()? clock;

  @override
  ConsumerState<SpendingScreen> createState() => _SpendingScreenState();
}

class _SpendingScreenState extends ConsumerState<SpendingScreen> {
  DateTime get now => (widget.clock ?? DateTime.now)().toLocal();
  late DateTime month = DateUtils.dateOnly(DateTime(now.year, now.month));

  AppColors get colors => Theme.of(context).extension<AppColors>()!;
  TextTheme get text => Theme.of(context).textTheme;
  TextStyle get muted => text.bodyMedium!.copyWith(color: colors.muted);
  String get monthLabel => DateFormat('MMMM y').format(month);

  void switchMonth(int delta) {
    setState(() => month = DateTime(month.year, month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final today = now;
    final nextAllowed = month.isBefore(DateTime(today.year, today.month));
    final spending = ref.watch(_spendingProvider(month));
    final currency = ref.watch(mainCurrencyProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 6,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => switchMonth(-1),
              icon: PhosphorIcon(
                PhosphorIconsRegular.caretLeft,
                color: colors.ink,
                size: 18,
              ),
            ),
            Flexible(
              child: Text(
                monthLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: nextAllowed ? () => switchMonth(1) : null,
              icon: PhosphorIcon(
                PhosphorIconsRegular.caretRight,
                color: nextAllowed
                    ? colors.ink
                    : colors.muted.withValues(alpha: .45),
                size: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: PhosphorIcon(
              PhosphorIconsDuotone.gearSix,
              color: colors.muted,
              duotoneSecondaryColor: colors.muted,
              duotoneSecondaryOpacity: .2,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: spending.value == null || currency.value == null
            ? Center(
                child: spending.hasError || currency.hasError
                    ? const Text('Could not load spending.')
                    : const SizedBox.shrink(),
              )
            : content(spending.value!, currency.value!),
      ),
    );
  }

  Widget content(List<CategorySpend> categories, String main) {
    final total = categories.fold(
      Money(0, categories.firstOrNull?.total.currency ?? main),
      (sum, item) => sum + item.total,
    );
    final excluded = categories.fold(
      0,
      (sum, item) => sum + item.unconvertedCount,
    );
    return ListView(
      key: PageStorageKey(month),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
      children: [
        Text('Spent in ${DateFormat('MMMM').format(month)}', style: muted),
        const SizedBox(height: 5),
        Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AmountText(
              total,
              key: const Key('spending-total'),
              size: 44,
              showDecimals: false,
            ),
          ),
        ),
        if (excluded > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              "$excluded entries in other currencies aren't included yet. They'll be added when exchange rates are available.",
              style: muted,
            ),
          ),
        const SizedBox(height: 18),
        if (categories.isEmpty)
          empty()
        else
          for (final category in categories) categoryRow(category, total),
      ],
    );
  }

  Widget empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 34),
    child: Column(
      children: [
        PhosphorIcon(
          PhosphorIconsDuotone.receipt,
          size: 32,
          color: colors.muted,
          duotoneSecondaryColor: colors.muted,
          duotoneSecondaryOpacity: .2,
        ),
        const SizedBox(height: 10),
        Text(
          'No spending recorded in $monthLabel.',
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.brass,
            foregroundColor: colors.onBrass,
          ),
          onPressed: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) => const EntryFormScreen(initialKind: 'expense'),
            ),
          ),
          child: const Text('Add expense'),
        ),
      ],
    ),
  );

  Widget categoryRow(CategorySpend item, Money total) => Column(
    key: ValueKey('spending-category-${item.category.id}'),
    children: [
      InkWell(
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => CategoryEntriesScreen(
              category: item.category,
              month: month,
              clock: widget.clock,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              PhosphorIcon(
                categoryIcon(item.category.iconKey),
                size: 24,
                color: colors.muted,
                duotoneSecondaryColor: colors.muted,
                duotoneSecondaryOpacity: .2,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.category.name, style: text.titleSmall),
                              Text(
                                item.count == 1
                                    ? '1 entry'
                                    : '${item.count} entries',
                                style: text.bodySmall!.copyWith(
                                  color: colors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: AmountText(item.total, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: ColoredBox(
                        color: colors.rule,
                        child: SizedBox(
                          height: 4,
                          width: double.infinity,
                          child: FractionallySizedBox(
                            key: ValueKey('spending-share-${item.category.id}'),
                            alignment: Alignment.centerLeft,
                            widthFactor: total.minor == 0
                                ? 0
                                : item.total.minor / total.minor,
                            child: ColoredBox(
                              color: colors.ink.withValues(alpha: .7),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PhosphorIcon(
                PhosphorIconsRegular.caretRight,
                color: colors.muted,
                size: 14,
              ),
            ],
          ),
        ),
      ),
      Divider(height: .7, thickness: .7, color: colors.rule),
    ],
  );
}
