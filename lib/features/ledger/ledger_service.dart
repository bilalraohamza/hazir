import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../core/money/convert.dart';
import '../../core/money/money.dart';
import '../../data/db/app_database.dart';
import '../fx/fx_service.dart';
import 'ledger_errors.dart';

class TransactionDraft {
  const TransactionDraft({
    required this.kind,
    required this.accountId,
    required this.amount,
    this.categoryId,
    this.toAccountId,
    this.received,
    this.customRate,
    this.note,
    required this.at,
  });
  final String kind;
  final int accountId;
  final Money amount;
  final int? categoryId;
  final int? toAccountId;
  final Money? received;
  final Decimal? customRate;
  final String? note;
  final DateTime at;
}

class AccountBalance {
  const AccountBalance(this.account, this.balance);
  final Account account;
  final Money balance;
}

class WorthSummary {
  const WorthSummary(
    this.total,
    this.byCurrency,
    this.ratesMissing,
    this.ratesStale, {
    this.convertedByCurrency = const {},
    this.snapshotDay,
  });
  final Money? total;
  final Map<String, Money> byCurrency;
  final bool ratesMissing;
  final bool ratesStale;
  final Map<String, Money> convertedByCurrency;
  final String? snapshotDay;
}

class CategorySpend {
  const CategorySpend(
    this.category,
    this.total,
    this.count,
    this.unconvertedCount,
  );
  final Category category;
  final Money total;
  final int count;
  final int unconvertedCount;
}

class LedgerService {
  LedgerService(this._db, this._fx, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final AppDatabase _db;
  final FxService _fx;
  final DateTime Function() _clock;

  Future<int> addExpense({
    required int accountId,
    required Money amount,
    required int categoryId,
    String? note,
    DateTime? at,
  }) => _save(
    TransactionDraft(
      kind: 'expense',
      accountId: accountId,
      amount: amount,
      categoryId: categoryId,
      note: note,
      at: at ?? _clock(),
    ),
  );

  Future<int> addIncome({
    required int accountId,
    required Money amount,
    required int categoryId,
    String? note,
    DateTime? at,
  }) => _save(
    TransactionDraft(
      kind: 'income',
      accountId: accountId,
      amount: amount,
      categoryId: categoryId,
      note: note,
      at: at ?? _clock(),
    ),
  );

  Future<int> addTransfer({
    required int fromAccountId,
    required int toAccountId,
    required Money amount,
    Money? received,
    Decimal? customRate,
    String? note,
    DateTime? at,
  }) => _save(
    TransactionDraft(
      kind: 'transfer',
      accountId: fromAccountId,
      amount: amount,
      toAccountId: toAccountId,
      received: received,
      customRate: customRate,
      note: note,
      at: at ?? _clock(),
    ),
  );

  Future<void> replaceTransaction(int id, TransactionDraft draft) async {
    await _save(draft, id: id);
  }

  Future<void> deleteTransaction(int id) async {
    await (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
  }

  Future<Account> _activeAccount(int? id) async {
    final account = id == null
        ? null
        : await (_db.select(
            _db.accounts,
          )..where((a) => a.id.equals(id))).getSingleOrNull();
    if (account == null) {
      throw const LedgerException(
        'unknown_account',
        'Choose an existing account.',
      );
    }
    if (account.archived) {
      throw const LedgerException(
        'archived_account',
        'Choose an active account.',
      );
    }
    return account;
  }

  void _validateAmount(Money amount, String currency) {
    if (amount.currency != currency) {
      throw const LedgerException(
        'currency_mismatch',
        'The amount must use the account currency.',
      );
    }
    if (amount.minor <= 0) {
      throw const LedgerException(
        'non_positive_amount',
        'The amount must be greater than zero.',
      );
    }
  }

  Future<Money> _transferAmount(TransactionDraft draft) async {
    if (draft.categoryId != null) {
      throw const LedgerException(
        'wrong_category_kind',
        'Transfers cannot have a category.',
      );
    }
    if (draft.toAccountId == draft.accountId) {
      throw const LedgerException(
        'same_account',
        'Choose a different destination account.',
      );
    }
    final to = await _activeAccount(draft.toAccountId);
    if (draft.amount.currency == to.currency) return draft.amount;
    final received = draft.received;
    if (received != null) {
      _validateAmount(received, to.currency);
      return received;
    }
    final rate =
        draft.customRate ??
        await _fx.rate(draft.amount.currency, to.currency, on: draft.at);
    if (rate == null) {
      throw const LedgerException(
        'missing_to_amount',
        'Enter the received amount or an exchange rate.',
      );
    }
    if (rate <= Decimal.zero) {
      throw const LedgerException(
        'non_positive_amount',
        'The exchange rate must be greater than zero.',
      );
    }
    final converted = convert(draft.amount, rate, to.currency);
    _validateAmount(converted, to.currency);
    return converted;
  }

  Future<void> _validateCategory(TransactionDraft draft) async {
    if (draft.kind != 'expense' && draft.kind != 'income') {
      throw ArgumentError.value(draft.kind, 'kind', 'Unknown transaction kind');
    }
    final id = draft.categoryId;
    final category = id == null
        ? null
        : await (_db.select(
            _db.categories,
          )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (category == null || category.archived) {
      throw const LedgerException(
        'unknown_category',
        'Choose an active category.',
      );
    }
    if (category.kind != draft.kind) {
      throw const LedgerException(
        'wrong_category_kind',
        'Choose a category for this transaction kind.',
      );
    }
  }

  Future<int> _save(TransactionDraft draft, {int? id}) =>
      _db.transaction(() async {
        final account = await _activeAccount(draft.accountId);
        _validateAmount(draft.amount, account.currency);
        Money? received;
        if (draft.kind == 'transfer') {
          received = await _transferAmount(draft);
        } else {
          await _validateCategory(draft);
        }
        final row = TransactionsCompanion(
          kind: Value(draft.kind),
          accountId: Value(account.id),
          currency: Value(account.currency),
          amountMinor: Value(draft.amount.minor),
          categoryId: Value(draft.categoryId),
          toAccountId: Value(received == null ? null : draft.toAccountId),
          toCurrency: Value(received?.currency),
          toAmountMinor: Value(received?.minor),
          note: Value(draft.note),
          occurredAt: Value(draft.at),
          createdAt: id == null ? Value(_clock()) : const Value.absent(),
          fxDay: Value(await _fx.snapshotDayFor(draft.at)),
        );
        if (id == null) return _db.into(_db.transactions).insert(row);
        final changed = await (_db.update(
          _db.transactions,
        )..where((t) => t.id.equals(id))).write(row);
        if (changed == 0) {
          throw ArgumentError.value(id, 'id', 'Unknown transaction');
        }
        return id;
      });

  // Rerun all dependent reads in one SQLite snapshot after a committed change.
  Stream<T> _watch<T>(Future<T> Function() read) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.transactions,
          _db.accounts,
          _db.settings,
          _db.fxSnapshots,
          _db.categories,
        },
      )
      .watch()
      .asyncMap((_) => _db.transaction(read));

  static const _movements = '''
    WITH movements(account_id, currency, minor) AS (
      SELECT id, currency, opening_minor FROM accounts
      UNION ALL
      SELECT account_id, currency, CASE kind WHEN 'income' THEN amount_minor ELSE -amount_minor END
      FROM transactions
      UNION ALL
      SELECT to_account_id, to_currency, to_amount_minor FROM transactions WHERE kind = 'transfer'
    )
  ''';

  Stream<List<AccountBalance>> watchBalances() => _watch(() async {
    final rows = await _db.customSelect('''
      $_movements
      SELECT a.*, SUM(m.minor) AS balance FROM accounts a
      JOIN movements m ON m.account_id = a.id AND m.currency = a.currency
      GROUP BY a.id, a.currency ORDER BY a.sort_order, a.id
    ''').get();
    return [
      for (final row in rows)
        AccountBalance(
          _db.accounts.map(row.data),
          Money(row.read<int>('balance'), row.read<String>('currency')),
        ),
    ];
  });

  Future<String> _mainCurrency() async => (await (_db.select(
    _db.settings,
  )..where((s) => s.key.equals('mainCurrency'))).getSingle()).value;

  Stream<WorthSummary> watchWorth() => _watch(() async {
    final main = await _mainCurrency();
    final rows = await _db.customSelect('''
      $_movements
      SELECT currency, SUM(minor) AS balance FROM movements GROUP BY currency
    ''').get();
    final byCurrency = <String, Money>{};
    final converted = <String, Money>{};
    final snapshotDay = await _fx.latestSnapshotDay();
    var total = Money(0, main);
    var missing = false;
    for (final row in rows) {
      final currency = row.read<String>('currency');
      final amount = Money(row.read<int>('balance'), currency);
      byCurrency[currency] = amount;
      if (currency == main || amount.minor == 0) {
        final subtotal = Money(amount.minor, main);
        converted[currency] = subtotal;
        total += subtotal;
        continue;
      }
      final rate = snapshotDay == null
          ? null
          : await _fx.rateForDay(currency, main, snapshotDay);
      if (rate == null) {
        missing = true;
      } else {
        final subtotal = convert(amount, rate, main);
        converted[currency] = subtotal;
        total += subtotal;
      }
    }
    return WorthSummary(
      missing ? null : total,
      byCurrency,
      missing,
      await _fx.isStale(),
      convertedByCurrency: converted,
      snapshotDay: snapshotDay,
    );
  });

  (DateTime, DateTime) _monthBounds(DateTime month) {
    final local = month.toLocal();
    return (
      DateTime(local.year, local.month),
      DateTime(local.year, local.month + 1),
    );
  }

  Stream<List<Transaction>> watchEntries({int? categoryId, DateTime? month}) =>
      _watch(() {
        final query = _db.select(_db.transactions);
        if (categoryId != null) {
          query.where((t) => t.categoryId.equals(categoryId));
        }
        if (month != null) {
          final (start, end) = _monthBounds(month);
          query.where(
            (t) =>
                t.occurredAt.isBiggerOrEqualValue(start) &
                t.occurredAt.isSmallerThanValue(end),
          );
        }
        return (query..orderBy([
              (t) => OrderingTerm.desc(t.occurredAt),
              (t) => OrderingTerm.desc(t.id),
            ]))
            .get();
      });

  Stream<List<CategorySpend>> watchSpending(DateTime month) => _watch(() async {
    final main = await _mainCurrency();
    final (start, end) = _monthBounds(month);
    const expenses =
        "kind = 'expense' AND occurred_at >= ? AND occurred_at < ?";
    final dates = [Variable.withDateTime(start), Variable.withDateTime(end)];
    // Equal amounts with the same currency and day round identically. Convert
    // each distinct foreign amount once, then let SQL sum individual entries.
    final foreign = await _db
        .customSelect(
          '''
      SELECT DISTINCT currency, fx_day, amount_minor FROM transactions
      WHERE $expenses AND currency <> ? AND fx_day IS NOT NULL
    ''',
          variables: [...dates, Variable.withString(main)],
        )
        .get();
    final rates = <(String, String), Decimal?>{};
    final conversions = <List<Object>>[];
    for (final row in foreign) {
      final currency = row.read<String>('currency');
      final day = row.read<String>('fx_day');
      final key = (currency, day);
      if (!rates.containsKey(key)) {
        rates[key] = await _fx.rateForDay(currency, main, day);
      }
      final rate = rates[key];
      if (rate == null) continue;
      final amount = Money(row.read<int>('amount_minor'), currency);
      conversions.add([
        currency,
        day,
        amount.minor,
        convert(amount, rate, main).minor,
      ]);
    }
    final rows = await _db
        .customSelect(
          '''
      WITH conversions AS MATERIALIZED (
        SELECT value ->> 0 AS currency, value ->> 1 AS day,
               value ->> 2 AS original_minor, value ->> 3 AS converted_minor
        FROM json_each(?)
      ), expenses AS (
        SELECT t.category_id,
          CASE WHEN t.currency = ? THEN t.amount_minor ELSE x.converted_minor END AS main_minor
        FROM transactions t LEFT JOIN conversions x
          ON t.currency = x.currency AND t.fx_day = x.day AND t.amount_minor = x.original_minor
        WHERE $expenses
      )
      SELECT c.*, COALESCE(SUM(e.main_minor), 0) AS total_minor,
             COUNT(*) AS entries, COUNT(*) - COUNT(e.main_minor) AS unconverted
      FROM expenses e JOIN categories c ON c.id = e.category_id
      GROUP BY c.id ORDER BY total_minor DESC, c.id
    ''',
          variables: [
            Variable.withString(jsonEncode(conversions)),
            Variable.withString(main),
            ...dates,
          ],
        )
        .get();
    return [
      for (final row in rows)
        CategorySpend(
          _db.categories.map(row.data),
          Money(row.read<int>('total_minor'), main),
          row.read<int>('entries'),
          row.read<int>('unconverted'),
        ),
    ];
  });
}
