import '../../../data/db/app_database.dart';
import '../../accounts/account_service.dart';
import '../../ledger/deletion_service.dart';
import '../../ledger/deletion_texts.dart';
import '../../../core/money/money.dart';
import 'tool_args.dart';
import 'tool_registry.dart';
import 'tool_spec.dart';
import 'write_tool.dart';

void registerAccountTools(ToolRegistry registry, AppDatabase db) {
  final service = AccountService(db);
  final deletions = DeletionService(db);
  const accountId = {'account_id': 'Account ID.'};

  registerWriteTool(
    registry,
    db,
    'create_account',
    'Create an account with one currency.',
    {
      'name': 'Name of the new account.',
      'currency': 'Account currency code (CNY, PKR or USD).',
      'opening_amount':
          'Optional opening balance as a decimal string. Defaults to zero.',
    },
    (args) async {
      final currency = args.currency();
      final name = await service.validateNewAccount(
        name: args.text('name'),
        currency: currency,
      );
      final opening = args.has('opening_amount')
          ? args.amount('opening_amount', currency)
          : Money(0, currency);
      return WriteAction(
        'Create $name',
        {
          'account_name': name,
          'currency': currency,
          'opening_amount': moneyJson(opening),
        },
        () async {
          final id = await service.createAccount(
            name: name,
            currency: currency,
            openingMinor: opening.minor,
          );
          return ToolOk({'account_id': id});
        },
      );
    },
    required: ['name', 'currency'],
  );

  registerWriteTool(
    registry,
    db,
    'rename_account',
    'Rename an existing account.',
    {...accountId, 'name': 'New account name.'},
    (args) async {
      final id = args.id('account_id');
      final account = await service.validateAccount(id);
      final name = await service.validateRename(id, args.text('name'));
      return WriteAction(
        'Rename ${account.name} to $name',
        {'account_id': id, 'account_name': account.name, 'new_name': name},
        () async {
          await service.renameAccount(id, name);
          return ToolOk({'account_id': id});
        },
      );
    },
    required: ['account_id', 'name'],
  );

  registerWriteTool(
    registry,
    db,
    'archive_account',
    'Archive an account and retain its history.',
    accountId,
    (args) async {
      final id = args.id('account_id');
      final account = await service.validateAccount(id);
      return WriteAction(
        'Archive ${account.name}',
        {
          'account_id': id,
          'account_name': account.name,
          'archived': account.archived,
        },
        () async {
          await service.archiveAccount(id);
          return ToolOk({'account_id': id});
        },
      );
    },
    required: ['account_id'],
  );

  registerWriteTool(
    registry,
    db,
    'delete_account',
    'Delete an account and its entries after confirmation.',
    accountId,
    (args) async {
      final id = args.id('account_id');
      final details = await deletions.accountDeletionDetails(id);
      final copy = accountDeletionText(details);
      final data = <String, Object?>{
        'account_id': id,
        'entry_count': details.entryCount,
        'transfer_count': details.transferCount,
      };
      return WriteAction(
        'Delete ${details.account.name}',
        {
          ...data,
          'account_name': details.account.name,
          'counterpart_names': details.counterpartNames,
          'warning': copy.warning,
          'confirm_label': copy.confirmLabel,
        },
        () async =>
            ToolOk(data, deletionReceipt: await deletions.deleteAccount(id)),
      );
    },
    required: ['account_id'],
    kind: ToolKind.destructive,
  );
}
