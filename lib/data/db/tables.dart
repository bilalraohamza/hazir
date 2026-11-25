import 'package:drift/drift.dart';

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get currency => text()();
  IntColumn get openingMinor => integer().withDefault(const Constant(0))();
  BoolColumn get isCredit => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer()();
}

@DataClassName('Category')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get kind => text()();
  TextColumn get iconKey => text()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('expense', 'income'))",
  ];
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  @ReferenceName('incomingTransfers')
  IntColumn get toAccountId => integer().nullable().references(Accounts, #id)();
  IntColumn get toAmountMinor => integer().nullable()();
  TextColumn get toCurrency => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get fxDay => text().nullable()();

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('expense', 'income', 'transfer'))",
    'CHECK (amount_minor > 0)',
    'CHECK (to_amount_minor > 0)',
    "CHECK (fx_day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')",
  ];
}

class FxSnapshots extends Table {
  TextColumn get day => text()();
  TextColumn get currency => text()();
  TextColumn get perUsd => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {day, currency};

  @override
  List<String> get customConstraints => [
    "CHECK (day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')",
  ];
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
