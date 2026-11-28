import 'package:budget_app/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'seeding twice preserves the ordered starter data and main currency',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.seedIfEmpty();
      final originalAccounts = await (db.select(
        db.accounts,
      )..orderBy([(a) => OrderingTerm.asc(a.sortOrder)])).get();
      final originalCategories = await (db.select(
        db.categories,
      )..orderBy([(c) => OrderingTerm.asc(c.id)])).get();
      await db.seedIfEmpty();

      final accounts = await (db.select(
        db.accounts,
      )..orderBy([(a) => OrderingTerm.asc(a.sortOrder)])).get();
      expect(accounts, originalAccounts);
      expect(accounts.map((a) => (a.name, a.currency)), [
        ('WeChat', 'CNY'),
        ('Alipay', 'CNY'),
        ('Bank card', 'CNY'),
        ('Cash (CNY)', 'CNY'),
        ('Pakistani bank', 'PKR'),
        ('Cash (PKR)', 'PKR'),
        ('JazzCash', 'PKR'),
        ('Easypaisa', 'PKR'),
        ('USD account', 'USD'),
      ]);
      expect(
        accounts.every(
          (a) => a.openingMinor == 0 && !a.isCredit && !a.archived,
        ),
        isTrue,
      );

      final categories = await (db.select(
        db.categories,
      )..orderBy([(c) => OrderingTerm.asc(c.id)])).get();
      expect(categories, originalCategories);
      expect(categories.length, 18);
      expect(
        categories.every((c) => !c.archived && c.iconKey.isNotEmpty),
        isTrue,
      );
      expect(categories.where((c) => c.kind == 'expense').map((c) => c.name), [
        'Food',
        'Groceries',
        'Transport',
        'Rent',
        'Bills',
        'Shopping',
        'Education',
        'Health',
        'Entertainment',
        'Gifts',
        'Sending home',
        'Other',
      ]);
      expect(categories.where((c) => c.kind == 'income').map((c) => c.name), [
        'Scholarship/Stipend',
        'From family',
        'Part-time work',
        'Gift',
        'Refund',
        'Other',
      ]);
      final setting = await db.select(db.settings).getSingle();
      expect((setting.key, setting.value), ('mainCurrency', 'CNY'));
    },
  );

  test(
    'startup upgrades only legacy Other icons without a schema change',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final schemaBefore = await db
          .customSelect('PRAGMA user_version')
          .getSingle();
      await db.seedIfEmpty();
      final others = db.select(db.categories)
        ..where((row) => row.name.equals('Other'));
      expect((await others.get()).map((row) => row.iconKey), ['tag', 'tag']);
      await (db.update(db.categories)..where(
            (row) => row.name.equals('Other') & row.kind.equals('expense'),
          ))
          .write(const CategoriesCompanion(iconKey: Value('dotsThree')));
      await (db.update(db.categories)..where(
            (row) => row.name.equals('Other') & row.kind.equals('income'),
          ))
          .write(const CategoriesCompanion(iconKey: Value('heart')));
      final renamed = await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: 'Misc',
              kind: 'expense',
              iconKey: 'dotsThree',
            ),
          );
      await db.seedIfEmpty();
      final first = await db.select(db.categories).get();
      await db.seedIfEmpty();
      expect(await db.select(db.categories).get(), first);
      expect((await others.get()).map((row) => row.iconKey), ['tag', 'heart']);
      expect(
        first.singleWhere((row) => row.id == renamed).iconKey,
        'dotsThree',
      );
      final schemaAfter = await db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(
        schemaAfter.read<int>('user_version'),
        schemaBefore.read<int>('user_version'),
      );
    },
  );
}
