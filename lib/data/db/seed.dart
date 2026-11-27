part of 'app_database.dart';

const _accounts = [
  ('WeChat', 'CNY'),
  ('Alipay', 'CNY'),
  ('Bank card', 'CNY'),
  ('Cash (CNY)', 'CNY'),
  ('Pakistani bank', 'PKR'),
  ('Cash (PKR)', 'PKR'),
  ('JazzCash', 'PKR'),
  ('Easypaisa', 'PKR'),
  ('USD account', 'USD'),
];

const _categories = {
  'expense': {
    'Food': 'forkKnife',
    'Groceries': 'shoppingCart',
    'Transport': 'bus',
    'Rent': 'house',
    'Bills': 'receipt',
    'Shopping': 'shoppingBag',
    'Education': 'bookOpen',
    'Health': 'firstAidKit',
    'Entertainment': 'filmStrip',
    'Gifts': 'gift',
    'Sending home': 'paperPlaneTilt',
    'Other': 'tag',
  },
  'income': {
    'Scholarship/Stipend': 'graduationCap',
    'From family': 'users',
    'Part-time work': 'briefcase',
    'Gift': 'gift',
    'Refund': 'arrowUUpLeft',
    'Other': 'tag',
  },
};

Future<void> _seedIfEmpty(AppDatabase db) async {
  final initialized = await (db.select(
    db.settings,
  )..where((row) => row.key.equals('mainCurrency'))).getSingleOrNull();
  if (initialized != null) return;

  final existing = await (db.select(db.accounts)..limit(1)).getSingleOrNull();
  if (existing != null) return;

  await db.batch((batch) {
    for (final (index, (name, currency)) in _accounts.indexed) {
      batch.insert(
        db.accounts,
        AccountsCompanion.insert(
          name: name,
          currency: currency,
          sortOrder: index,
        ),
      );
    }
    for (final group in _categories.entries) {
      for (final category in group.value.entries) {
        batch.insert(
          db.categories,
          CategoriesCompanion.insert(
            name: category.key,
            kind: group.key,
            iconKey: category.value,
          ),
        );
      }
    }
    batch.insert(
      db.settings,
      SettingsCompanion.insert(key: 'mainCurrency', value: 'CNY'),
    );
  });
}
