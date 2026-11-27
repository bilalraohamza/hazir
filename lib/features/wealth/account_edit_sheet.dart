import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/providers.dart';
import '../../core/money/money.dart';
import '../../data/db/app_database.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/amount_text.dart';
import '../../ui/widgets/money_input.dart';
import '../../ui/widgets/deletion_feedback.dart';
import '../ledger/deletion_service.dart';
import '../ledger/ledger_errors.dart';

enum _DeleteAccountAction { delete, archive }

class AccountEditSheet extends ConsumerStatefulWidget {
  const AccountEditSheet({super.key, this.account});
  final Account? account;

  static Future<void> show(BuildContext context, {Account? account}) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colors.surface,
      barrierColor: colors.onBrass.withValues(alpha: .5),
      builder: (_) => AccountEditSheet(account: account),
    );
  }

  @override
  ConsumerState<AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends ConsumerState<AccountEditSheet> {
  late final name = TextEditingController(text: widget.account?.name);
  late final opening = TextEditingController(
    text: (widget.account?.openingMinor ?? 0) == 0
        ? ''
        : formatMoney(
            Money(widget.account!.openingMinor, currency),
            withSymbol: false,
          ),
  );
  late String currency = widget.account?.currency ?? 'CNY';
  final errors = <String, String>{};
  bool busy = false;

  AppColors get colors => Theme.of(context).extension<AppColors>()!;
  TextStyle get muted =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.muted);

  @override
  void dispose() {
    name.dispose();
    opening.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(errors.clear);
    final label = name.text.trim();
    if (label.isEmpty) {
      setState(() => errors['Name'] = 'Enter an account name.');
      return;
    }
    final Money balance;
    try {
      balance = opening.text.isEmpty
          ? Money(0, currency)
          : Money.parse(opening.text, currency);
    } on FormatException catch (error) {
      setState(() => errors['Opening balance'] = error.message);
      return;
    }

    final service = ref.read(accountServiceProvider);
    final id = widget.account?.id;
    setState(() => busy = true);
    try {
      if (id == null) {
        await service.createAccount(
          name: label,
          currency: currency,
          openingMinor: balance.minor,
        );
      } else {
        await ref.read(databaseProvider).transaction(() async {
          await service.renameAccount(id, label);
          await service.setOpeningBalance(id, balance);
        });
      }
      if (mounted) Navigator.pop(context);
    } on LedgerException catch (error) {
      final field = switch (error.code) {
        'duplicate_name' => 'Name',
        'unknown_currency' => 'Currency',
        'currency_mismatch' => 'Opening balance',
        _ => 'Account',
      };
      if (mounted) setState(() => errors[field] = error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: colors.onBrass.withValues(alpha: .5),
      builder: (dialog) => AlertDialog(
        backgroundColor: colors.surface,
        surfaceTintColor: colors.surface,
        shadowColor: colors.onBrass,
        title: const Text('Archive this account?'),
        content: const Text('Its balance will still count in Wealth.'),
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
    if (confirmed != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      await ref.read(accountServiceProvider).archiveAccount(widget.account!.id);
      if (mounted) Navigator.pop(context);
    } on LedgerException catch (error) {
      if (mounted) setState(() => errors['Account'] = error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteAccount() async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      errors.remove('Account');
    });
    try {
      final deletion = ref.read(deletionServiceProvider);
      final details = await deletion.accountDeletionDetails(widget.account!.id);
      if (!mounted) return;
      final action = await confirmDeletion(details);
      if (!mounted || action == null) return;
      final id = details.account.id;
      final undo = deletionUndoFor(context);
      switch (action) {
        case _DeleteAccountAction.archive:
          await ref.read(accountServiceProvider).archiveAccount(id);
        case _DeleteAccountAction.delete:
          final receipt = await deletion.deleteAccount(id);
          final name = details.account.name;
          final count = details.entryCount;
          undo(
            count == 0
                ? '$name deleted'
                : '$name and ${entryCountLabel(count)} deleted',
            receipt,
          );
      }
      if (mounted) Navigator.pop(context);
    } on LedgerException catch (error) {
      if (mounted) setState(() => errors['Account'] = error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<_DeleteAccountAction?> confirmDeletion(
    AccountDeletionDetails details,
  ) {
    final name = details.account.name;
    final entryCount = details.entryCount;
    final transfers = details.transferCount;
    final names = details.counterpartNames;
    final counterparts = names.length < 2
        ? names.join()
        : '${names.take(names.length - 1).join(', ')} and ${names.last}';
    final countLabel = entryCountLabel(entryCount);
    final description = StringBuffer('This permanently deletes the account');
    if (entryCount > 0) description.write(' and its $countLabel');
    if (transfers > 0) {
      description.write(
        ', including $transfers ${transfers == 1 ? 'transfer' : 'transfers'}',
      );
      if (counterparts.isNotEmpty) description.write(' with $counterparts');
    }
    description.write('.');
    if (transfers > 0) description.write(' Their balances will change.');
    return showModalBottomSheet<_DeleteAccountAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colors.surface,
      barrierColor: colors.onBrass.withValues(alpha: .5),
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Delete $name?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(description.toString()),
              const SizedBox(height: 8),
              Text(
                "This can't be undone after a few seconds. To keep the history, archive it instead.",
                style: muted,
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: deleteButtonStyle(),
                onPressed: () =>
                    Navigator.pop(sheet, _DeleteAccountAction.delete),
                child: Text(
                  entryCount == 0
                      ? 'Delete account'
                      : 'Delete account and $countLabel',
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.rule),
                ),
                onPressed: () =>
                    Navigator.pop(sheet, _DeleteAccountAction.archive),
                child: const Text('Archive instead'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget field(String label, Widget control) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.rule, width: .7)),
        ),
        child: Row(
          children: [
            Text(label, style: muted),
            const SizedBox(width: 16),
            Expanded(child: control),
          ],
        ),
      ),
      if (errors[label] case final message?)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(message, style: muted.copyWith(color: colors.warning)),
        ),
    ],
  );

  InputDecoration placeholder(String hint) =>
      InputDecoration.collapsed(hintText: hint, hintStyle: muted);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adding = widget.account == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      adding ? 'Add account' : 'Edit account',
                      style: theme.textTheme.titleLarge,
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
              const SizedBox(height: 6),
              field(
                'Name',
                TextField(
                  key: const Key('account-name'),
                  controller: name,
                  enabled: !busy,
                  textAlign: TextAlign.end,
                  textCapitalization: TextCapitalization.words,
                  decoration: placeholder('Account name'),
                  onChanged: (_) => setState(() => errors.remove('Name')),
                ),
              ),
              field(
                'Currency',
                Align(
                  alignment: Alignment.centerRight,
                  child: adding
                      ? DropdownButton<String>(
                          value: currency,
                          dropdownColor: colors.surface,
                          underline: const SizedBox.shrink(),
                          icon: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: PhosphorIcon(
                              PhosphorIconsRegular.caretRight,
                              color: colors.muted,
                              size: 16,
                            ),
                          ),
                          items: [
                            for (final code in ['CNY', 'PKR', 'USD'])
                              DropdownMenuItem(value: code, child: Text(code)),
                          ],
                          onChanged: busy
                              ? null
                              : (value) => setState(() {
                                  currency = value!;
                                  errors.remove('Currency');
                                  errors.remove('Opening balance');
                                }),
                        )
                      : Text(currency, style: theme.textTheme.titleSmall),
                ),
              ),
              if (!adding)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "Currency can't be changed after creating the account.",
                    style: muted,
                  ),
                ),
              field(
                'Opening balance',
                MoneyInput(
                  inputKey: const Key('opening-balance'),
                  currency: currency,
                  allowNegative: true,
                  controller: opening,
                  enabled: !busy,
                  textAlign: TextAlign.end,
                  style: amountNumberStyle(colors.ink, 16),
                  onChanged: (_) =>
                      setState(() => errors.remove('Opening balance')),
                ),
              ),
              if (errors['Account'] case final message?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    message,
                    style: muted.copyWith(color: colors.warning),
                  ),
                ),
              if (!adding)
                TextButton(
                  onPressed: busy ? null : archive,
                  child: const Text('Archive'),
                ),
              if (!adding)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: colors.warning),
                  onPressed: busy ? null : deleteAccount,
                  child: const Text('Delete account'),
                ),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brass,
                  foregroundColor: colors.onBrass,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
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
