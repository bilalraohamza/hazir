import 'dart:async';

import 'package:budget_app/core/money/money.dart';
import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/fx/fx_service.dart';
import 'package:budget_app/features/fx/rates_api.dart';
import 'package:budget_app/features/ledger/ledger_errors.dart';
import 'package:budget_app/features/ledger/ledger_service.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _Rates implements RatesApi {
  Map<String, Decimal> rates = {'CNY': Decimal.one, 'PKR': Decimal.fromInt(2)};
  @override
  Future<Map<String, Decimal>> latestPerUsd() async => rates;
}

void main() {
  late AppDatabase db;
  late LedgerService ledger;
  late FxService fx;
  late _Rates api;
  late DateTime now;
  late int wechat, alipay, bank, food, gift;
  const yuan = Money(2800, 'CNY');
  const rupees = Money(500000, 'PKR');
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedIfEmpty();
    final accounts = {
      for (final a in await db.select(db.accounts).get()) a.name: a.id,
    };
    final categories = {
      for (final c in await db.select(db.categories).get()) c.name: c.id,
    };
    wechat = accounts['WeChat']!;
    alipay = accounts['Alipay']!;
    bank = accounts['Pakistani bank']!;
    food = categories['Food']!;
    gift = categories['Gift']!;
    now = DateTime(2026, 11, 25, 13);
    api = _Rates();
    fx = FxService(db, api, clock: () => now);
    ledger = LedgerService(db, fx, clock: () => now);
  });
  Future<Money> balance(int id) async => (await ledger.watchBalances().first)
      .singleWhere((b) => b.account.id == id)
      .balance;
  Future<int> expense({
    int? account,
    Money amount = yuan,
    int? category,
    DateTime? at,
  }) => ledger.addExpense(
    accountId: account ?? wechat,
    amount: amount,
    categoryId: category ?? food,
    at: at,
  );
  Future<int> transfer({
    int? from,
    int? to,
    Money amount = rupees,
    Money? received,
    Decimal? customRate,
    DateTime? at,
  }) => ledger.addTransfer(
    fromAccountId: from ?? bank,
    toAccountId: to ?? alipay,
    amount: amount,
    received: received,
    customRate: customRate,
    at: at,
  );
  Matcher code(String value) =>
      throwsA(isA<LedgerException>().having((e) => e.code, 'code', value));

  test('expense updates balance and Food spending', () async {
    await fx.refreshIfNeeded();
    await expense();
    expect(await balance(wechat), Money(-2800, 'CNY'));
    final spend = (await ledger.watchSpending(now).first).single;
    expect(
      (spend.category.id, spend.total, spend.count, spend.unconvertedCount),
      (food, yuan, 1, 0),
    );
    final row = (await ledger.watchEntries().first).single;
    expect(
      (row.createdAt, row.occurredAt, row.fxDay),
      (now, now, '2026-11-25'),
    );
  });
  test('invalid writes return ledger errors and leave no entries', () async {
    await expectLater(
      expense(amount: Money(0, 'CNY')),
      code('non_positive_amount'),
    );
    await expectLater(expense(amount: rupees), code('currency_mismatch'));
    await expectLater(expense(category: gift), code('wrong_category_kind'));
    await expectLater(expense(account: -1), code('unknown_account'));
    await expectLater(expense(category: -1), code('unknown_category'));
    await expectLater(transfer(to: bank), code('same_account'));
    await expectLater(transfer(), code('missing_to_amount'));
    await expectLater(transfer(received: rupees), code('currency_mismatch'));
    await expectLater(
      transfer(received: Money(0, 'CNY')),
      code('non_positive_amount'),
    );
    await expectLater(
      transfer(customRate: Decimal.zero),
      code('non_positive_amount'),
    );
    await (db.update(db.categories)..where((c) => c.id.equals(food))).write(
      CategoriesCompanion(archived: Value(true)),
    );
    await expectLater(expense(), code('unknown_category'));
    await (db.update(db.accounts)..where((a) => a.id.equals(bank))).write(
      AccountsCompanion(archived: Value(true)),
    );
    await expectLater(transfer(), code('archived_account'));
    await expectLater(
      transfer(from: alipay, to: bank, amount: yuan),
      code('archived_account'),
    );
    expect(await ledger.watchEntries().first, isEmpty);
  });
  test('received amount wins and transfers never count as spending', () async {
    await transfer(received: Money(12200, 'CNY'), customRate: Decimal.one);
    expect(await balance(bank), Money(-500000, 'PKR'));
    expect(await balance(alipay), Money(12200, 'CNY'));
    expect(await ledger.watchSpending(now).first, isEmpty);
  });
  test('transfer uses custom rate or dated snapshot and ignores same-currency overrides', () async {
    await transfer(customRate: Decimal.parse('0.0245'));
    expect(await balance(alipay), Money(12250, 'CNY'));
    final yesterday = now;
    await fx.refreshIfNeeded();
    now = now.add(Duration(days: 1));
    api.rates['PKR'] = Decimal.fromInt(4);
    await fx.refreshIfNeeded();
    await transfer(at: yesterday);
    expect(await balance(alipay), Money(262250, 'CNY'));
    await transfer(
      from: wechat,
      amount: yuan,
      received: rupees,
      customRate: Decimal.zero,
    );
    expect(await balance(alipay), Money(265050, 'CNY'));
  });
  test(
    'replace then delete updates balances and removes Food spending',
    () async {
      final id = await expense();
      await ledger.replaceTransaction(
        id,
        TransactionDraft(
          kind: 'expense',
          accountId: wechat,
          amount: Money(3000, 'CNY'),
          categoryId: food,
          at: now,
        ),
      );
      expect(await balance(wechat), Money(-3000, 'CNY'));
      expect(
        (await ledger.watchSpending(now).first).single.total,
        Money(3000, 'CNY'),
      );
      await ledger.deleteTransaction(id);
      expect(await balance(wechat), Money(0, 'CNY'));
      expect(await ledger.watchSpending(now).first, isEmpty);
    },
  );
  test(
    'replace transfer moves its destination and validates atomically',
    () async {
      final id = await transfer(received: yuan);
      TransactionDraft draft({int? category}) => TransactionDraft(
        kind: 'transfer',
        accountId: bank,
        amount: rupees,
        received: yuan,
        toAccountId: wechat,
        categoryId: category,
        at: now,
      );
      await expectLater(
        ledger.replaceTransaction(id, draft(category: food)),
        code('wrong_category_kind'),
      );
      expect(await balance(alipay), yuan);
      await ledger.replaceTransaction(id, draft());
      expect(await balance(alipay), Money(0, 'CNY'));
      expect(await balance(wechat), yuan);
    },
  );
  test('spending rounds each entry using its frozen day and replacement uses the new date', () async {
    await fx.refreshIfNeeded();
    final id = await expense(account: bank, amount: Money(1, 'PKR'));
    await expense(account: bank, amount: Money(1, 'PKR'));
    now = now.add(Duration(days: 1));
    api.rates['PKR'] = Decimal.one;
    api.rates['CNY'] = Decimal.fromInt(3);
    await fx.refreshIfNeeded();
    expect(
      (await ledger.watchSpending(now).first).single.total,
      Money(2, 'CNY'),
    );
    await ledger.replaceTransaction(
      id,
      TransactionDraft(
        kind: 'expense',
        accountId: bank,
        amount: Money(1, 'PKR'),
        categoryId: food,
        at: now,
      ),
    );
    expect(
      (await ledger.watchSpending(now).first).single.total,
      Money(4, 'CNY'),
    );
  });
  test('spending counts missing days and missing rates without guessing', () async {
    await expense(account: bank, amount: rupees);
    // Insert a partial snapshot directly so the first entry keeps its null day.
    await db
        .into(db.fxSnapshots)
        .insert(
          FxSnapshotsCompanion.insert(
            day: '2026-11-25',
            currency: 'CNY',
            perUsd: '1',
            fetchedAt: now,
          ),
        );
    await expense(account: bank, amount: rupees);
    await expense();
    final spend = (await ledger.watchSpending(now).first).single;
    expect((spend.total, spend.count, spend.unconvertedCount), (yuan, 3, 2));
  });
  test(
    'November includes the last local minute and excludes December',
    () async {
      await expense(at: DateTime(2026, 11, 30, 23, 59));
      expect((await ledger.watchSpending(now).first).single.total, yuan);
      expect(await ledger.watchSpending(DateTime(2026, 12)).first, isEmpty);
      expect(
        await ledger.watchEntries(month: now, categoryId: food).first,
        hasLength(1),
      );
      expect(
        await ledger.watchEntries(month: now, categoryId: gift).first,
        isEmpty,
      );
    },
  );
  test('worth emits after a snapshot and main currency change', () async {
    await expense();
    expect((await ledger.watchWorth().first).total, Money(-2800, 'CNY'));
    await expense(account: bank, amount: Money(100, 'PKR'));
    final stream = StreamIterator(ledger.watchWorth());
    addTearDown(stream.cancel);
    expect(await stream.moveNext(), isTrue);
    expect(
      (
        stream.current.total,
        stream.current.ratesMissing,
        stream.current.ratesStale,
      ),
      (null, true, true),
    );
    expect(stream.current.byCurrency['CNY'], Money(-2800, 'CNY'));
    await fx.refreshIfNeeded();
    expect(await stream.moveNext(), isTrue);
    expect(
      (
        stream.current.total,
        stream.current.ratesMissing,
        stream.current.ratesStale,
      ),
      (Money(-2850, 'CNY'), false, false),
    );
    await db.update(db.settings).write(SettingsCompanion(value: Value('PKR')));
    expect(await stream.moveNext(), isTrue);
    expect(stream.current.total, Money(-5700, 'PKR'));
  });
  test('opening balance and income survive account archival', () async {
    await ledger.addIncome(
      accountId: wechat,
      amount: yuan,
      categoryId: gift,
      note: 'gift',
    );
    await (db.update(db.accounts)..where((a) => a.id.equals(wechat))).write(
      AccountsCompanion(openingMinor: Value(100), archived: Value(true)),
    );
    expect(await balance(wechat), Money(2900, 'CNY'));
    expect(await ledger.watchSpending(now).first, isEmpty);
  });
}
