import '../../../core/money/money.dart';
import '../../../data/db/app_database.dart';
import '../../fx/fx_service.dart';
import '../../ledger/deletion_service.dart';
import '../../ledger/deletion_texts.dart';
import '../../ledger/ledger_errors.dart';
import '../../ledger/ledger_service.dart';
import '../settings/agent_settings.dart';
import 'tool_args.dart';
import 'tool_registry.dart';
import 'tool_spec.dart';
import 'write_tool.dart';

const _amountFields = {
  'amount': 'Positive amount as a decimal string.',
  'currency': 'Amount currency code (CNY, PKR or USD).',
  'note': 'Optional note.',
  'at': 'Optional local ISO date or date and time. Defaults to now on a new entry.',
};
const _transferFields = {
  'to_account_id': 'Destination account ID for a transfer.',
  'received_amount': 'Optional destination amount as a decimal string. Takes precedence over rate.',
  'received_currency': 'Currency of the received amount. Defaults to the destination account currency.',
  'rate': 'Optional decimal string: destination currency units for one source currency unit.',
};
const _accountField = {
  'account_id': 'Source account ID, or destination account ID for income.',
};
const _categoryField = {
  'category_id': 'Active category ID matching the entry kind.',
};
const _entryField = {'entry_id': 'Existing transaction ID.'};

void registerEntryTools(
  ToolRegistry registry,
  AppDatabase db,
  LedgerService ledger,
  FxService fx,
  AgentSettingsRepository settings, {
  DateTime Function()? clock,
}) {
  final tools = _EntryTools(db, ledger, fx, settings);
  for (final kind in ['expense', 'income']) {
    registerWriteTool(
      registry,
      db,
      'add_$kind',
      'Record an $kind in the ledger.',
      {..._accountField, ..._categoryField, ..._amountFields},
      (args) => tools.prepare(kind, args),
      required: ['account_id', 'category_id', 'amount', 'currency'],
      clock: clock,
      freezeEntryDate: true,
    );
  }
  registerWriteTool(
    registry,
    db,
    'add_transfer',
    'Move money between accounts. Ask how much arrived if no rate is available.',
    {
      'from_account_id': 'Source account ID.',
      ..._transferFields,
      ..._amountFields,
    },
    (args) => tools.prepare('transfer', args),
    required: ['from_account_id', 'to_account_id', 'amount', 'currency'],
    clock: clock,
    freezeEntryDate: true,
  );
  registerWriteTool(
    registry,
    db,
    'edit_entry',
    'Edit an entry. Omitted fields retain their current values.',
    {
      ..._entryField,
      'kind': 'Replacement kind: expense, income or transfer.',
      ..._accountField,
      ..._categoryField,
      ..._transferFields,
      ..._amountFields,
    },
    (args) async {
      final old = await tools.entry(args.id('entry_id'));
      return tools.prepare(
        args.optionalText('kind') ?? old.kind,
        args,
        old: old,
      );
    },
    required: ['entry_id'],
    clock: clock,
  );
  registerWriteTool(
    registry,
    db,
    'delete_entry',
    'Delete an entry after confirmation.',
    _entryField,
    (args) async {
      final entry = await tools.entry(args.id('entry_id'));
      args.entryDate = entry.occurredAt.toLocal();
      final deletions = DeletionService(db);
      return WriteAction(
        'Delete entry',
        {
          'entry_id': entry.id,
          ...await tools.describeStored(entry),
          'entry_count': 1,
          'policy_amount': await tools.policyAmount(
            Money(entry.amountMinor, entry.currency),
          ),
          'warning': entryDeletionText.warning,
          'confirm_label': entryDeletionText.confirmLabel,
        },
        () async => ToolOk({
          'transaction_id': entry.id,
        }, deletionReceipt: await deletions.deleteTransaction(entry.id)),
      );
    },
    required: ['entry_id'],
    kind: ToolKind.destructive,
    clock: clock,
  );
}

class _EntryTools {
  _EntryTools(this.db, this.ledger, this.fx, this.settings);
  final AppDatabase db;
  final LedgerService ledger;
  final FxService fx;
  final AgentSettingsRepository settings;

  Future<Map<String, Object?>?> policyAmount(Money amount) async {
    final threshold = await settings.readLargeAmountThreshold();
    return policyMoney(fx, amount, threshold.currency);
  }

  Future<Transaction> entry(int id) async =>
      await (db.select(
        db.transactions,
      )..where((row) => row.id.equals(id))).getSingleOrNull() ??
      (throw const LedgerException(
        'unknown_transaction',
        'This entry is no longer available.',
      ));

  Future<Account?> account(int? id) => id == null
      ? Future.value()
      : (db.select(
          db.accounts,
        )..where((row) => row.id.equals(id))).getSingleOrNull();
  Future<Category?> category(int? id) => id == null
      ? Future.value()
      : (db.select(
          db.categories,
        )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<Map<String, Object?>> describe({
    required String kind,
    required int accountId,
    required Money amount,
    required int? categoryId,
    required int? toAccountId,
    required Money? received,
    required String? note,
    required DateTime at,
  }) async => {
    'kind': kind,
    'account_id': accountId,
    'account_name': (await account(accountId))?.name,
    'category_id': categoryId,
    'category_name': (await category(categoryId))?.name,
    'to_account_id': toAccountId,
    'to_account_name': (await account(toAccountId))?.name,
    'amount': moneyJson(amount),
    'received': received == null ? null : moneyJson(received),
    'note': note,
    'at': at.toLocal().toIso8601String(),
  };

  Money? storedReceived(Transaction? entry) =>
      entry?.toAmountMinor == null || entry?.toCurrency == null
      ? null
      : Money(entry!.toAmountMinor!, entry.toCurrency!);

  Future<Map<String, Object?>> describeStored(Transaction entry) => describe(
    kind: entry.kind,
    accountId: entry.accountId,
    amount: Money(entry.amountMinor, entry.currency),
    categoryId: entry.categoryId,
    toAccountId: entry.toAccountId,
    received: storedReceived(entry),
    note: entry.note,
    at: entry.occurredAt,
  );

  Future<WriteAction> prepare(
    String kind,
    WriteArgs args, {
    Transaction? old,
  }) async {
    if (!['expense', 'income', 'transfer'].contains(kind)) {
      throw const ToolError(
        'invalid_kind',
        'Choose expense, income or transfer.',
      );
    }
    final isTransfer = kind == 'transfer';
    final accountField = old == null && isTransfer
        ? 'from_account_id'
        : 'account_id';
    final accountId = args.has(accountField)
        ? args.id(accountField)
        : old?.accountId ?? args.id(accountField);
    final currency = args.has('currency')
        ? args.currency()
        : old?.currency ?? args.currency();
    if (old != null && currency != old.currency && !args.has('amount')) {
      throw missingArgument('amount');
    }
    final amount = args.has('amount')
        ? args.amount('amount', currency)
        : Money(old!.amountMinor, currency);
    final toId = isTransfer
        ? (args.has('to_account_id')
              ? args.id('to_account_id')
              : old?.toAccountId ?? args.id('to_account_id'))
        : null;
    final categoryId = args.has('category_id')
        ? args.id('category_id')
        : (isTransfer ? null : old?.categoryId);
    final to = await account(toId);
    final hasReceived = args.has('received_amount');
    final hasRate = args.has('rate');
    Money? received;
    if (hasReceived) {
      final code = args.has('received_currency')
          ? args.currency('received_currency')
          : to?.currency ?? args.currency('received_currency');
      received = args.amount('received_amount', code);
    } else if (!hasRate && toId != null && toId == old?.toAccountId) {
      received = storedReceived(old);
      if (received != null && args.has('received_currency')) {
        received = Money(received.minor, args.currency('received_currency'));
      }
    } else if (args.has('received_currency')) {
      throw missingArgument('received_amount');
    }
    final customRate = received != null ? null : args.rate();
    final note = args.has('note') ? args.optionalText('note') : old?.note;
    args.entryDate = args.date ?? old?.occurredAt.toLocal();
    final at = args.at;

    TransactionDraft draft({Money? destination, bool useCustomRate = false}) =>
        TransactionDraft(
          kind: kind,
          accountId: accountId,
          amount: amount,
          categoryId: categoryId,
          toAccountId: toId,
          received: destination,
          customRate: useCustomRate ? customRate : null,
          note: note,
          at: at,
        );

    final Money? resolved;
    try {
      resolved = await ledger.validateDraft(
        draft(destination: received, useCustomRate: true),
        useLatestRate: true,
      );
    } on LedgerException catch (error) {
      if (error.code != 'missing_to_amount') rethrow;
      throw const ToolError(
        'rate_needed',
        'How much did the destination account receive?',
      );
    }
    final values = await describe(
      kind: kind,
      accountId: accountId,
      amount: amount,
      categoryId: categoryId,
      toAccountId: toId,
      received: resolved,
      note: note,
      at: at,
    );
    final summary = old == null
        ? 'Add $kind of ${formatMoney(amount)}'
        : 'Edit entry to ${formatMoney(amount)}';
    return WriteAction(
      summary,
      {
        ...values,
        if (old != null) 'entry_id': old.id,
        if (old != null) 'old': await describeStored(old),
        if (old != null) 'new': values,
        'policy_amount': await policyAmount(amount),
      },
      () async {
        final replacement = draft(destination: resolved);
        final int id;
        if (old != null) {
          id = old.id;
          await ledger.replaceTransaction(id, replacement);
        } else {
          id = switch (kind) {
            'expense' => await ledger.addExpense(
              accountId: accountId,
              amount: amount,
              categoryId: categoryId!,
              note: note,
              at: at,
            ),
            'income' => await ledger.addIncome(
              accountId: accountId,
              amount: amount,
              categoryId: categoryId!,
              note: note,
              at: at,
            ),
            _ => await ledger.addTransfer(
              fromAccountId: accountId,
              toAccountId: toId!,
              amount: amount,
              received: resolved,
              note: note,
              at: at,
            ),
          };
        }
        return ToolOk({'transaction_id': id});
      },
    );
  }
}
