import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/providers.dart';
import '../../core/money/convert.dart';
import '../../core/money/money.dart';
import '../../data/db/app_database.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/amount_text.dart';
import '../../ui/widgets/page_header.dart';
import '../../ui/widgets/deletion_feedback.dart';
import '../ledger/ledger_errors.dart';
import '../entry/entry_form_screen.dart';

class _ExpenseRow {
  const _ExpenseRow(this.entry, this.label, this.converted);
  final Transaction entry;
  final String label;
  final Money? converted;
}

final _entriesProvider = StreamProvider.autoDispose
    .family<List<_ExpenseRow>, ({int categoryId, DateTime month, String main})>(
      (ref, query) {
        final db = ref.watch(databaseProvider);
        final ledger = ref.watch(ledgerServiceProvider);
        final fx = ref.watch(fxServiceProvider);
        return ledger
            .watchEntries(categoryId: query.categoryId, month: query.month)
            .asyncMap((entries) async {
              final names = {
                for (final account in await db.select(db.accounts).get())
                  account.id: account.name,
              };
              final rates = <(String, String), Decimal?>{};
              final rows = <_ExpenseRow>[];
              for (final entry in entries.where(
                (item) => item.kind == 'expense',
              )) {
                Money? converted;
                final day = entry.fxDay;
                if (entry.currency != query.main && day != null) {
                  final key = (entry.currency, day);
                  if (!rates.containsKey(key)) {
                    rates[key] = await fx.rateForDay(
                      entry.currency,
                      query.main,
                      day,
                    );
                  }
                  final rate = rates[key];
                  if (rate != null) {
                    converted = convert(
                      Money(-entry.amountMinor, entry.currency),
                      rate,
                      query.main,
                    );
                  }
                }
                final note = entry.note?.trim();
                rows.add(
                  _ExpenseRow(
                    entry,
                    note != null && note.isNotEmpty
                        ? note
                        : names[entry.accountId] ?? 'Account',
                    converted,
                  ),
                );
              }
              return rows;
            });
      },
    );

class CategoryEntriesScreen extends ConsumerWidget {
  const CategoryEntriesScreen({
    super.key,
    required this.category,
    required this.month,
    this.clock,
  });
  final Category category;
  final DateTime month;
  final DateTime Function()? clock;

  String dayLabel(DateTime day, DateTime today) {
    if (day == today) return 'Today';
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return 'Yesterday';
    }
    return DateFormat('EEE d MMM').format(day);
  }

  Future<bool> _confirmSwipe(
    BuildContext context,
    WidgetRef ref,
    _ExpenseRow row,
  ) async {
    if (!await confirmEntryDeletion(context) || !context.mounted) return false;
    final undo = deletionUndoFor(context);
    try {
      final receipt = await ref
          .read(deletionServiceProvider)
          .deleteTransaction(row.entry.id);
      undo(deletedEntryMessage(row.entry.note), receipt);
    } on LedgerException catch (error) {
      if (context.mounted) {
        final colors = Theme.of(context).extension<AppColors>()!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: colors.ink,
            content: Text(
              error.message,
              style: TextStyle(color: colors.ground),
            ),
          ),
        );
      }
    }
    // The query stream removes the row once the database transaction commits.
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final text = theme.textTheme;
    final main = ref.watch(mainCurrencyProvider);
    final entries = main.value == null
        ? null
        : ref.watch(
            _entriesProvider((
              categoryId: category.id,
              month: month,
              main: main.value!,
            )),
          );
    final today = DateUtils.dateOnly((clock ?? DateTime.now)().toLocal());
    final days = <DateTime, List<_ExpenseRow>>{};
    for (final row in entries?.value ?? const <_ExpenseRow>[]) {
      final day = DateUtils.dateOnly(row.entry.occurredAt.toLocal());
      days.putIfAbsent(day, () => []).add(row);
    }

    return Scaffold(
      appBar: PageHeader(
        onBack: () => Navigator.pop(context),
        title: Text(category.name),
      ),
      body: SafeArea(
        top: false,
        child: entries?.value == null
            ? Center(
                child: entries?.hasError == true || main.hasError
                    ? const Text('Could not load entries.')
                    : const SizedBox.shrink(),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
                children: [
                  if (days.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 26),
                      child: Text(
                        'No entries this month.',
                        style: text.bodyMedium!.copyWith(color: colors.muted),
                      ),
                    ),
                  for (final section in days.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 7),
                      child: Text(
                        dayLabel(section.key, today),
                        style: text.titleSmall!.copyWith(color: colors.muted),
                      ),
                    ),
                    Divider(height: .7, thickness: .7, color: colors.rule),
                    for (final row in section.value) ...[
                      Dismissible(
                        key: ValueKey(row.entry.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 14),
                          color: AppColors.light.warning,
                          child: PhosphorIcon(
                            PhosphorIconsRegular.trash,
                            color: AppColors.light.surface,
                          ),
                        ),
                        confirmDismiss: (_) => _confirmSwipe(context, ref, row),
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => EntryFormScreen(
                                editTransactionId: row.entry.id,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    row.label,
                                    style: text.bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          AmountText(
                                            Money(
                                              -row.entry.amountMinor,
                                              row.entry.currency,
                                            ),
                                            size: 16,
                                          ),
                                          if (row.converted
                                              case final converted?)
                                            Text(
                                              '≈ ${formatMoney(converted)}',
                                              style: amountNumberStyle(
                                                colors.muted,
                                                12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
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
                      ),
                      Divider(height: .7, thickness: .7, color: colors.rule),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}
