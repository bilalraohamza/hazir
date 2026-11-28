import 'package:drift/drift.dart';

import '../../../core/money/convert.dart';
import '../../../core/money/money.dart';
import '../../../data/db/app_database.dart';
import '../../fx/fx_service.dart';
import '../../ledger/ledger_service.dart';
import 'tool_args.dart';
import 'tool_registry.dart';
import 'tool_spec.dart';

const _id = {'type': 'integer'};
const _string = {'type': 'string'};
const _kinds = {'expense', 'income', 'transfer'};

void registerReadTools(
  ToolRegistry registry,
  AppDatabase db,
  LedgerService ledger,
  FxService fx, {
  DateTime Function()? clock,
}) {
  final tools = _ReadTools(db, ledger, fx, clock ?? DateTime.now);

  void register(
    String name,
    String description,
    ToolCallback run, {
    Map<String, Object?> properties = const {},
    List<String> required = const [],
  }) => registry.register(
    ToolSpec(
      name: name,
      description: description,
      parameters: {
        'type': 'object',
        'properties': properties,
        if (required.isNotEmpty) 'required': required,
        'additionalProperties': false,
      },
      kind: ToolKind.read,
      run: run,
    ),
  );

  register(
    'list_accounts',
    'List account IDs, names, currencies and archive status.',
    tools.accounts,
  );
  register(
    'list_categories',
    'List category IDs, names, kinds and archive status.',
    tools.categories,
  );
  register(
    'get_balances',
    'Show Wealth totals and the balances behind them: all active accounts and archived accounts with nonzero balances.',
    tools.balances,
  );
  register(
    'get_spending',
    'Show expense totals by category in the main currency for a local month, with counts of entries excluded for missing rates. Transfers are excluded.',
    tools.spending,
    required: ['period'],
    properties: {
      'period': {
        ..._string,
        'description': 'Local month: this_month, last_month or YYYY-MM.',
      },
      'category_id': {..._id, 'description': 'Only expenses in this category.'},
      'account_id': {
        ..._id,
        'description': 'Only expenses paid from this account.',
      },
    },
  );
  register(
    'get_entries',
    'Find newest ledger entries using any of the optional filters.',
    tools.entries,
    properties: {
      'category_id': {..._id, 'description': 'Entry category ID.'},
      'account_id': {
        ..._id,
        'description': 'Entry account ID. Matches either side of a transfer.',
      },
      'kind': {
        ..._string,
        'enum': _kinds.toList(),
        'description': 'Entry kind.',
      },
      'from': {
        ..._string,
        'description': 'First local day, inclusive (YYYY-MM-DD).',
      },
      'to': {
        ..._string,
        'description': 'Last local day, inclusive (YYYY-MM-DD).',
      },
      'note_contains': {
        ..._string,
        'description': 'Case-insensitive text to find in the note.',
      },
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 20,
        'default': 10,
        'description': 'Maximum entries returned.',
      },
    },
  );
  register(
    'get_exchange_rate',
    'Get the latest rate and snapshot day for a currency pair.',
    tools.exchangeRate,
    required: ['from', 'to'],
    properties: {
      'from': {..._string, 'description': 'Source currency code.'},
      'to': {..._string, 'description': 'Destination currency code.'},
    },
  );
  register(
    'get_affordability',
    'Show active account balances in the main currency before and after a hypothetical purchase. Always send the purchase amount as a decimal string, for example "28.50".',
    tools.affordability,
    required: ['amount', 'currency'],
    properties: {
      'amount': {
        ..._string,
        'description': 'Positive purchase amount as a decimal string.',
      },
      'currency': {..._string, 'description': 'Purchase currency code.'},
    },
  );
}

bool _availableAccount(AccountBalance balance) => !balance.account.archived;

Map<String, Object?> _account(Account account) => {
  'id': account.id,
  'name': account.name,
  'currency': account.currency,
  'archived': account.archived,
};

class _ReadTools {
  const _ReadTools(this.db, this.ledger, this.fx, this.clock);

  final AppDatabase db;
  final LedgerService ledger;
  final FxService fx;
  final DateTime Function() clock;

  Future<ToolResult> accounts(Map<String, Object?> _) async => ToolOk({
    'accounts':
        (await (db.select(db.accounts)..orderBy([
                  (a) => OrderingTerm.asc(a.sortOrder),
                  (a) => OrderingTerm.asc(a.id),
                ]))
                .get())
            .map(_account)
            .toList(),
  });

  Future<ToolResult> categories(Map<String, Object?> _) async => ToolOk({
    'categories': [
      for (final c in await (db.select(
        db.categories,
      )..orderBy([(c) => OrderingTerm.asc(c.id)])).get())
        {'id': c.id, 'name': c.name, 'kind': c.kind, 'archived': c.archived},
    ],
  });

  Future<ToolResult> balances(Map<String, Object?> _) =>
      db.transaction(() async {
        final worth = await ledger.worth();
        return ToolOk({
          'accounts': [
            for (final item in await ledger.balances())
              if (!item.account.archived || item.balance.minor != 0)
                {..._account(item.account), 'balance': moneyJson(item.balance)},
          ],
          'by_currency': worth.byCurrency.map(
            (code, amount) => MapEntry(code, moneyJson(amount)),
          ),
          'total': worth.total == null ? null : moneyJson(worth.total!),
          'rates_missing': worth.ratesMissing,
          if (worth.ratesMissing) 'missing_currencies': worth.missingCurrencies,
        });
      });

  Future<ToolError?> _checkIds(int? accountId, int? categoryId) async {
    if (accountId != null &&
        await (db.select(
              db.accounts,
            )..where((a) => a.id.equals(accountId))).getSingleOrNull() ==
            null) {
      return ToolError('not_found', 'Account $accountId was not found.');
    }
    if (categoryId != null &&
        await (db.select(
              db.categories,
            )..where((c) => c.id.equals(categoryId))).getSingleOrNull() ==
            null) {
      return ToolError('not_found', 'Category $categoryId was not found.');
    }
    return null;
  }

  Future<ToolResult> spending(Map<String, Object?> args) async {
    final period = args['period'];
    if (period == null) return missingArgument('period');
    final now = clock().toLocal();
    final month = switch (period) {
      'this_month' => DateTime(now.year, now.month),
      'last_month' => DateTime(now.year, now.month - 1),
      String value when RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$').hasMatch(value) =>
        DateTime.tryParse('$value-01'),
      _ => null,
    };
    if (month == null) {
      return const ToolError(
        'invalid_period',
        'Use this_month, last_month or YYYY-MM.',
      );
    }
    final account = _optionalId(args, 'account_id');
    if (account is ToolError) return account;
    final category = _optionalId(args, 'category_id');
    if (category is ToolError) return category;
    final accountId = account as int?;
    final categoryId = category as int?;
    return db.transaction(() async {
      final error = await _checkIds(accountId, categoryId);
      if (error != null) return error;
      final summary = await ledger.spending(
        month,
        DateTime(month.year, month.month + 1),
        accountId: accountId,
        categoryId: categoryId,
      );
      return ToolOk({
        'total': moneyJson(summary.total),
        'categories': [
          for (final item in summary.categories)
            {
              'name': item.category.name,
              'amount': moneyJson(item.total),
              'count': item.count,
            },
        ],
        'unconverted_count': summary.unconvertedCount,
      });
    });
  }

  Future<ToolResult> entries(Map<String, Object?> args) async {
    final account = _optionalId(args, 'account_id');
    if (account is ToolError) return account;
    final category = _optionalId(args, 'category_id');
    if (category is ToolError) return category;
    final from = optionalDate(args, 'from');
    if (from is ToolError) return from;
    final to = optionalDate(args, 'to');
    if (to is ToolError) return to;
    final start = from == null ? null : _startOfDay(from as DateTime);
    final end = to == null ? null : _startOfDay(to as DateTime, dayOffset: 1);
    if (start != null && end != null && !start.isBefore(end)) {
      return const ToolError('invalid_date', 'From must be on or before to.');
    }
    final kind = args['kind'];
    if (kind != null && !_kinds.contains(kind)) {
      return const ToolError(
        'invalid_kind',
        'Use expense, income or transfer for kind.',
      );
    }
    final note = args['note_contains'];
    if (note != null && note is! String) {
      return const ToolError('invalid_note', 'note_contains must be text.');
    }
    final limit = args['limit'] ?? 10;
    if (limit is! int || limit < 1) {
      return const ToolError(
        'invalid_limit',
        'limit must be a positive integer.',
      );
    }
    final accountId = account as int?;
    final categoryId = category as int?;
    return db.transaction(() async {
      final error = await _checkIds(accountId, categoryId);
      if (error != null) return error;
      final rows = await ledger.entries(
        accountId: accountId,
        categoryId: categoryId,
        kind: kind as String?,
        from: start,
        to: end,
        noteContains: note as String?,
        limit: limit.clamp(1, 20),
      );
      if (rows.isEmpty) return const ToolOk({'entries': []});
      final accounts = {
        for (final a
            in await (db.select(db.accounts)..where(
                  (a) => a.id.isIn({
                    for (final row in rows) ...[
                      row.accountId,
                      ?row.toAccountId,
                    ],
                  }),
                ))
                .get())
          a.id: a.name,
      };
      final categories = {
        for (final c
            in await (db.select(db.categories)..where(
                  (c) => c.id.isIn({for (final row in rows) ?row.categoryId}),
                ))
                .get())
          c.id: c.name,
      };
      return ToolOk({
        'entries': [
          for (final row in rows)
            {
              'id': row.id,
              'kind': row.kind,
              'at': row.occurredAt.toLocal().toIso8601String(),
              'account': accounts[row.accountId],
              if (row.kind == 'transfer')
                'to_account': accounts[row.toAccountId],
              if (row.toAmountMinor case final minor?)
                if (row.toCurrency case final currency?)
                  'received': moneyJson(Money(minor, currency)),
              'category': categories[row.categoryId],
              'amount': moneyJson(Money(row.amountMinor, row.currency)),
              'note': row.note,
            },
        ],
      });
    });
  }

  Future<ToolResult> exchangeRate(Map<String, Object?> args) async {
    final from = currencyArg(args, 'from');
    if (from is ToolError) return from;
    final to = currencyArg(args, 'to');
    if (to is ToolError) return to;
    return db.transaction(() async {
      final day = await fx.latestSnapshotDay();
      final rate = day == null
          ? null
          : await fx.rateForDay(from as String, to as String, day);
      return rate == null
          ? const ToolOk({'rates_missing': true})
          : ToolOk({'rate': rate.toString(), 'day': day});
    });
  }

  Future<ToolResult> affordability(Map<String, Object?> args) async {
    final parsed = money(args, 'amount', 'currency');
    if (parsed is ToolError) return parsed;
    final amount = parsed as Money;
    return db.transaction(() async {
      final accounts = (await ledger.balances())
          .where(_availableAccount)
          .toList();
      final worth = await ledger.worth(
        accountIds: accounts.map((item) => item.account.id).toList(),
      );
      final available = worth.convertedTotal!;
      final main = available.currency;
      final day = worth.snapshotDay;
      final purchaseRate = amount.currency == main || day == null
          ? null
          : await fx.rateForDay(amount.currency, main, day);
      final purchase = amount.currency == main
          ? amount
          : purchaseRate == null
          ? null
          : convert(amount, purchaseRate, main);
      final partial = worth.ratesMissing || purchase == null;
      return ToolOk({
        'available': moneyJson(available),
        'available_after': purchase == null
            ? null
            : moneyJson(available - purchase),
        'partial': partial,
        if (purchase == null) 'purchase_rate_missing': true,
        if (partial)
          'excluded_accounts': [
            for (final item in accounts)
              if (item.balance.minor != 0 &&
                  worth.missingCurrencies.contains(item.balance.currency))
                _account(item.account),
          ],
        'note': 'Budget limits and upcoming expenses are not included yet.',
      });
    });
  }
}

Object? _optionalId(Map<String, Object?> args, String name) =>
    args[name] == null ? null : intId(args, name);

DateTime _startOfDay(DateTime date, {int dayOffset = 0}) =>
    DateTime(date.year, date.month, date.day + dayOffset);
