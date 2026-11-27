import 'package:budget_app/core/money/money.dart';
import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/fx/fx_service.dart';
import 'package:budget_app/features/ledger/deletion_service.dart';
import 'package:budget_app/features/ledger/ledger_errors.dart';
import 'package:budget_app/features/ledger/ledger_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;

import '../../app/shell_fixture.dart';

void main() {
  late ShellFixture fixture;
  late AppDatabase db;
  late LedgerService ledger;
  late DeletionService deletion;

  setUp(() async {
    fixture = ShellFixture();
    db = fixture.db;
    addTearDown(db.close);
    await db.seedIfEmpty();
    final fx = FxService(db, fixture.api, clock: () => fixture.now);
    ledger = LedgerService(db, fx, clock: () => fixture.now);
    deletion = DeletionService(db);
  });

  Future<List<Transaction>> entries() => (db.select(
    db.transactions,
  )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();

  Future<Map<int, Money>> balances() async => {
    for (final row in await ledger.watchBalances().first)
      row.account.id: row.balance,
  };

  Future<int> expense({int category = 1}) => ledger.addExpense(
    accountId: 1,
    categoryId: category,
    amount: const Money(2800, 'CNY'),
    note: 'Lunch',
  );

  Matcher failure(String code) => throwsA(
    isA<LedgerException>().having((error) => error.code, 'code', code),
  );

  test(
    'transaction deletion restores exact values and is idempotent',
    () async {
      final id = await expense();
      final before = await entries();
      final originalBalances = await balances();
      final receipt = await deletion.deleteTransaction(id);
      expect(await entries(), isEmpty);
      expect((await balances())[1], const Money(0, 'CNY'));
      await Future.wait([receipt.restore(), receipt.restore()]);
      expect(await entries(), before);
      expect(await balances(), originalBalances);
      await receipt.restore();
      expect(await entries(), before);
    },
  );

  test('deleting an account removes incoming and outgoing transfers and restores both sides', () async {
    await expense();
    await ledger.addTransfer(
      fromAccountId: 5,
      toAccountId: 1,
      amount: const Money(500000, 'PKR'),
      received: const Money(12200, 'CNY'),
      note: 'Incoming',
    );
    await ledger.addTransfer(
      fromAccountId: 1,
      toAccountId: 2,
      amount: const Money(1200, 'CNY'),
      note: 'Outgoing',
    );
    await ledger.addExpense(
      accountId: 2,
      categoryId: 3,
      amount: const Money(600, 'CNY'),
    );
    final before = await entries();
    final originalBalances = await balances();
    final accounts = await db.select(db.accounts).get();
    final preview = await deletion.accountDeletionDetails(1);
    expect(preview.entryCount, 3);
    expect(preview.transferCount, 2);
    expect(
      preview.counterpartNames,
      unorderedEquals(['Pakistani bank', 'Alipay']),
    );
    final receipt = await deletion.deleteAccount(1);
    expect((await entries()).single, before.last);
    final removed = await balances();
    expect(removed.containsKey(1), isFalse);
    expect(removed[2], const Money(-600, 'CNY'));
    expect(removed[5], const Money(0, 'PKR'));
    await receipt.restore();
    expect(await entries(), before);
    expect(await db.select(db.accounts).get(), accounts);
    expect(await balances(), originalBalances);
  });

  test(
    'category deletion moves entries atomically and undo moves them back',
    () async {
      await expense();
      final before = await entries();
      final categories = await db.select(db.categories).get();
      await expectLater(
        deletion.deleteCategory(1),
        failure('category_has_entries'),
      );
      await expectLater(
        deletion.deleteCategory(1, moveToCategoryId: 13),
        failure('wrong_category_kind'),
      );
      await expectLater(
        deletion.deleteCategory(1, moveToCategoryId: 1),
        failure('wrong_category_kind'),
      );
      await expectLater(
        deletion.deleteCategory(1, moveToCategoryId: -1),
        failure('wrong_category_kind'),
      );
      await (db.update(db.categories)..where((row) => row.id.equals(4))).write(
        const CategoriesCompanion(archived: Value(true)),
      );
      await expectLater(
        deletion.deleteCategory(1, moveToCategoryId: 4),
        failure('wrong_category_kind'),
      );
      expect(await entries(), before);
      final receipt = await deletion.deleteCategory(1, moveToCategoryId: 2);
      expect((await entries()).single.categoryId, 2);
      expect(
        (await db.select(db.categories).get()).any((row) => row.id == 1),
        isFalse,
      );
      await receipt.restore();
      expect(await entries(), before);
      expect(
        (await db.select(db.categories).get()).singleWhere(
          (row) => row.id == 1,
        ),
        categories.first,
      );
    },
  );

  test(
    'an empty category can be deleted and restored with its original identity',
    () async {
      final categories = await db.select(db.categories).get();
      final receipt = await deletion.deleteCategory(18);
      expect(
        await db.select(db.categories).get(),
        categories.take(17).toList(),
      );
      await receipt.restore();
      expect(await db.select(db.categories).get(), categories);
    },
  );

  test(
    'startup does not recreate accounts after deleting the last one',
    () async {
      final accounts = await db.select(db.accounts).get();
      for (final account in accounts) {
        await deletion.deleteAccount(account.id);
      }
      await db.seedIfEmpty();
      expect(await db.select(db.accounts).get(), isEmpty);
      expect(await db.select(db.categories).get(), hasLength(18));
      expect((await db.select(db.settings).getSingle()).value, 'CNY');
    },
  );
}
