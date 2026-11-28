import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/providers.dart';
import '../../core/money/currency.dart';
import '../../data/db/app_database.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/page_header.dart';
import '../ledger/ledger_errors.dart';
import '../wealth/account_edit_sheet.dart';

final settingsAccountsProvider = StreamProvider.autoDispose<List<Account>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db
      .select(db.accounts)
      .watch()
      .map(
        (rows) => rows
          ..sort((a, b) {
            final order = a.sortOrder.compareTo(b.sortOrder);
            return order == 0 ? a.id.compareTo(b.id) : order;
          }),
      );
});

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  bool saving = false;
  String? error;

  Future<void> change(Future<void> Function() action) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await action();
    } on LedgerException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(settingsAccountsProvider);
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final group = <String, List<Account>>{};
    final archived = <Account>[];
    for (final account in data.value ?? const <Account>[]) {
      if (account.archived) {
        archived.add(account);
      } else {
        group.putIfAbsent(account.currency, () => []).add(account);
      }
    }
    return Scaffold(
      appBar: PageHeader(
        title: const Text('Accounts'),
        onBack: () => Navigator.pop(context),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
          child: CustomScrollView(
            slivers: [
              if (data.hasError)
                const SliverToBoxAdapter(
                  child: Text('Could not load accounts.'),
                ),
              if (error case final message?)
                SliverToBoxAdapter(
                  child: Text(message, style: TextStyle(color: colors.warning)),
                ),
              for (final entry in group.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      currencyName(entry.key),
                      style: theme.textTheme.titleSmall!.copyWith(
                        color: currencyColor(colors, entry.key),
                      ),
                    ),
                  ),
                ),
                SliverReorderableList(
                  key: ValueKey('accounts-${entry.key}'),
                  itemCount: entry.value.length,
                  proxyDecorator: (child, _, _) =>
                      Material(color: colors.ground, child: child),
                  onReorderItem: (oldIndex, newIndex) {
                    final ids = entry.value
                        .map((account) => account.id)
                        .toList();
                    final id = ids.removeAt(oldIndex);
                    ids.insert(newIndex, id);
                    change(
                      () => ref
                          .read(accountServiceProvider)
                          .reorderAccounts(entry.key, ids),
                    );
                  },
                  itemBuilder: (context, index) {
                    final account = entry.value[index];
                    return Column(
                      key: ValueKey(account.id),
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(account.name),
                          onTap: () =>
                              AccountEditSheet.show(context, account: account),
                          trailing: ReorderableDelayedDragStartListener(
                            key: ValueKey('reorder-${account.id}'),
                            index: index,
                            enabled: !saving && entry.value.length > 1,
                            child: SizedBox.square(
                              dimension: 44,
                              child: ColoredBox(
                                color: colors.ground,
                                child: Center(
                                  child: PhosphorIcon(
                                    PhosphorIconsRegular.dotsSixVertical,
                                    color: colors.muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Divider(height: .7, thickness: .7, color: colors.rule),
                      ],
                    );
                  },
                ),
              ],
              SliverList.list(
                children: [
                  if (archived.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        'Archived',
                        style: TextStyle(color: colors.muted),
                      ),
                    ),
                    for (final account in archived)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(account.name),
                        subtitle: Text(account.currency),
                        trailing: TextButton(
                          onPressed: saving
                              ? null
                              : () => change(
                                  () => ref
                                      .read(accountServiceProvider)
                                      .unarchiveAccount(account.id),
                                ),
                          child: const Text('Unarchive'),
                        ),
                      ),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: PhosphorIcon(
                      PhosphorIconsRegular.plus,
                      color: colors.muted,
                    ),
                    title: const Text('Add account'),
                    onTap: () => AccountEditSheet.show(context),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
