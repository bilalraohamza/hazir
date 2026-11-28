import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../ledger/ledger_errors.dart';

class CategoryService {
  CategoryService(this._db);
  final AppDatabase _db;

  Future<int> createCategory({
    required String name,
    required String kind,
    String iconKey = 'tag',
  }) => _db.transaction(() async {
    final trimmed = await validateNewCategory(name: name, kind: kind);
    return _db
        .into(_db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: trimmed,
            kind: kind,
            iconKey: iconKey,
          ),
        );
  });

  Future<String> validateNewCategory({
    required String name,
    required String kind,
  }) async {
    if (kind != 'expense' && kind != 'income') {
      throw const LedgerException(
        'wrong_category_kind',
        'Choose expense or income.',
      );
    }
    final trimmed = await _validatedName(name, kind);
    return trimmed;
  }

  Future<Category> validateCategory(int id) async {
    final category = await _category(id).getSingleOrNull();
    if (category == null) throw _unknownCategory;
    return category;
  }

  Future<String> validateRename(int id, String name) async {
    final category = await validateCategory(id);
    return _validatedName(name, category.kind, except: id);
  }

  Future<void> renameCategory(int id, String name) => _db.transaction(() async {
    final trimmed = await validateRename(id, name);
    await _write(id, CategoriesCompanion(name: Value(trimmed)));
  });

  Future<void> archiveCategory(int id) => _db.transaction(() async {
    await validateCategory(id);
    await _write(id, const CategoriesCompanion(archived: Value(true)));
  });

  Future<void> unarchiveCategory(int id) =>
      _write(id, const CategoriesCompanion(archived: Value(false)));

  static const _unknownCategory = LedgerException(
    'unknown_category',
    'This category is no longer available.',
  );

  SimpleSelectStatement<$CategoriesTable, Category> _category(int id) =>
      _db.select(_db.categories)..where((row) => row.id.equals(id));

  Future<void> _write(int id, CategoriesCompanion values) async {
    final changed = await (_db.update(
      _db.categories,
    )..where((row) => row.id.equals(id))).write(values);
    if (changed == 0) throw _unknownCategory;
  }

  Future<String> _validatedName(String name, String kind, {int? except}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const LedgerException('empty_name', 'Enter a category name.');
    }
    final key = trimmed.toLowerCase();
    final categories = await (_db.select(
      _db.categories,
    )..where((row) => row.kind.equals(kind))).get();
    if (categories.any(
      (row) => row.id != except && row.name.trim().toLowerCase() == key,
    )) {
      throw const LedgerException(
        'duplicate_name',
        'A category of this type already has this name.',
      );
    }
    return trimmed;
  }
}
