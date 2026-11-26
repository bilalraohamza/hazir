import 'dart:math' show max;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/providers.dart';
import '../../core/money/money.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/amount_text.dart';
import '../ledger/ledger_errors.dart';
import '../ledger/ledger_service.dart';
import 'account_edit_sheet.dart';

final _balancesProvider = StreamProvider.autoDispose<List<AccountBalance>>(
  (ref) => ref.watch(ledgerServiceProvider).watchBalances(),
);
final _worthProvider = StreamProvider.autoDispose<WorthSummary>(
  (ref) => ref.watch(ledgerServiceProvider).watchWorth(),
);

String _currencyName(String code, {bool upper = false}) {
  final name = switch (code) {
    'CNY' => 'yuan',
    'PKR' => 'rupees',
    'USD' => 'dollars',
    _ => code,
  };
  return upper ? name[0].toUpperCase() + name.substring(1) : name;
}

class WealthScreen extends ConsumerStatefulWidget {
  const WealthScreen({super.key});

  @override
  ConsumerState<WealthScreen> createState() => _WealthScreenState();
}

class _WealthScreenState extends ConsumerState<WealthScreen> {
  bool combined = true;
  bool archivedOpen = false;
  String? archiveError;
  final restoring = <int>{};

  AppColors get colors => Theme.of(context).extension<AppColors>()!;
  TextTheme get text => Theme.of(context).textTheme;
  TextStyle get muted => text.bodyMedium!.copyWith(color: colors.muted);

  @override
  Widget build(BuildContext context) {
    final main = ref.watch(mainCurrencyProvider);
    final worth = ref.watch(_worthProvider);
    final balances = ref.watch(_balancesProvider);
    final accounts = balances.value;
    final summary = worth.value;
    final currency = main.value;
    final canShowTotal = summary?.total?.currency == currency;
    final total = canShowTotal ? summary?.total : null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        titleSpacing: 18,
        title: currency == null
            ? null
            : Text(
                combined
                    ? 'Everything you have, in ${_currencyName(currency)}'
                    : 'Everything you have',
                style: muted,
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
        child: accounts == null || summary == null || currency == null
            ? Center(
                child: main.hasError || worth.hasError || balances.hasError
                    ? const Text('Could not load your accounts.')
                    : const SizedBox.shrink(),
              )
            : content(accounts, summary, currency, total),
      ),
    );
  }

  Widget content(
    List<AccountBalance> accounts,
    WorthSummary worth,
    String main,
    Money? total,
  ) {
    final subtotal = worth.byCurrency[main] ?? Money(0, main);
    final currencies = worth.byCurrency.keys.toList()
      ..sort((a, b) {
        if (a == main) return b == main ? 0 : -1;
        if (b == main) return 1;
        return a.compareTo(b);
      });
    final archived = accounts.where((item) => item.account.archived).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
          sliver: SliverList.list(
            children: [
              if (combined) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AmountText(
                      total ?? subtotal,
                      key: const Key('wealth-total'),
                      size: 44,
                      showDecimals: false,
                    ),
                  ),
                ),
                if (worth.ratesMissing)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      "Exchange rates aren't available yet. Connect to the internet to see your full total.",
                      style: muted,
                    ),
                  )
                else if (worth.ratesStale && worth.snapshotDay != null)
                  Text(
                    'Rates from ${DateFormat('d MMM y').format(DateTime.parse(worth.snapshotDay!))}',
                    style: muted,
                  ),
              ] else
                for (final code in currencies)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currencyName(code, upper: true),
                          style: text.titleSmall!.copyWith(
                            color: currencyColor(colors, code),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AmountText(
                              worth.byCurrency[code]!,
                              key: ValueKey('wealth-total-$code'),
                              size: 32,
                              showDecimals: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 16),
              toggle(),
              if (combined && total != null) ...[
                const SizedBox(height: 14),
                shareBar(currencies, worth.convertedByCurrency),
              ],
              for (final code in currencies)
                currencyGroup(
                  code,
                  worth.byCurrency[code]!,
                  combined && code != main
                      ? worth.convertedByCurrency[code]
                      : null,
                  accounts.where(
                    (item) =>
                        item.account.currency == code && !item.account.archived,
                  ),
                ),
              row(
                Row(
                  children: [
                    PhosphorIcon(
                      PhosphorIconsRegular.plus,
                      size: 18,
                      color: colors.muted,
                    ),
                    const SizedBox(width: 9),
                    Text('Add account', style: muted),
                  ],
                ),
                onTap: () => AccountEditSheet.show(context),
              ),
              if (archived.isNotEmpty) ...[
                row(
                  Text('Archived', style: muted),
                  onTap: () => setState(() => archivedOpen = !archivedOpen),
                  trailing: PhosphorIcon(
                    archivedOpen
                        ? PhosphorIconsRegular.caretDown
                        : PhosphorIconsRegular.caretRight,
                    size: 14,
                    color: colors.muted,
                  ),
                ),
                if (archivedOpen) ...[
                  for (final item in archived) accountRow(item, archived: true),
                  if (archiveError != null)
                    Text(
                      archiveError!,
                      style: muted.copyWith(color: colors.warning),
                    ),
                ],
              ],
            ],
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'Rates by ExchangeRate-API',
                style: text.bodySmall!.copyWith(color: colors.muted),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget toggle() => DecoratedBox(
    decoration: BoxDecoration(
      color: Color.alphaBlend(colors.rule.withValues(alpha: .4), colors.ground),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (final (label, value) in [
            ('Combined', true),
            ('By currency', false),
          ])
            Expanded(
              child: Semantics(
                selected: combined == value,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: combined == value ? colors.brass : null,
                    foregroundColor: combined == value
                        ? colors.onBrass
                        : colors.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => setState(() => combined = value),
                  child: Text(label),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget shareBar(List<String> codes, Map<String, Money> converted) {
    final weights = {
      for (final code in codes)
        if ((converted[code]?.minor ?? 0) != 0)
          code: BigInt.from(converted[code]!.minor).abs(),
    };
    if (weights.isEmpty) return const SizedBox.shrink();
    final sum = weights.values.fold(BigInt.zero, (a, b) => a + b);
    return Row(
      key: const Key('currency-share-bar'),
      spacing: 3,
      children: [
        for (final entry in weights.entries)
          Expanded(
            flex: max(1, (entry.value * BigInt.from(10000) ~/ sum).toInt()),
            child: Semantics(
              label: _currencyName(entry.key, upper: true),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: currencyColor(colors, entry.key),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget currencySubtotal(String code, Money subtotal, {Money? converted}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _currencyName(code, upper: true),
                style: text.titleSmall!.copyWith(
                  color: currencyColor(colors, code),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AmountText(subtotal, size: 18),
                if (converted != null && converted.minor != 0)
                  Text(
                    '≈ ${formatMoney(converted)}',
                    style: amountNumberStyle(colors.muted, 12),
                  ),
              ],
            ),
          ],
        ),
      );

  Widget currencyGroup(
    String code,
    Money subtotal,
    Money? converted,
    Iterable<AccountBalance> accounts,
  ) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      children: [
        currencySubtotal(code, subtotal, converted: converted),
        rule(),
        for (final item in accounts) accountRow(item),
      ],
    ),
  );

  Widget rule() => Divider(height: .7, thickness: .7, color: colors.rule);

  Widget row(Widget label, {Widget? trailing, VoidCallback? onTap}) => Column(
    children: [
      InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 43),
          child: Row(
            children: [
              Expanded(child: label),
              ?trailing,
            ],
          ),
        ),
      ),
      rule(),
    ],
  );

  Widget accountRow(AccountBalance item, {bool archived = false}) => row(
    Text(item.account.name, style: text.bodyMedium),
    onTap: archived
        ? null
        : () => AccountEditSheet.show(context, account: item.account),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AmountText(item.balance, size: 16),
        const SizedBox(width: 8),
        if (archived)
          TextButton(
            onPressed: restoring.contains(item.account.id)
                ? null
                : () => unarchive(item.account.id),
            child: const Text('Unarchive'),
          )
        else
          PhosphorIcon(
            PhosphorIconsRegular.caretRight,
            color: colors.muted,
            size: 14,
          ),
      ],
    ),
  );

  Future<void> unarchive(int id) async {
    setState(() {
      archiveError = null;
      restoring.add(id);
    });
    try {
      await ref.read(accountServiceProvider).unarchiveAccount(id);
    } on LedgerException catch (error) {
      if (mounted) setState(() => archiveError = error.message);
    } finally {
      if (mounted) setState(() => restoring.remove(id));
    }
  }
}
