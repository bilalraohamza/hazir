import '../../core/money/currency.dart';
import '../../data/db/app_database.dart';

const mainCurrencySettingKey = 'mainCurrency';

Future<void> saveMainCurrency(AppDatabase db, String currency) async {
  currencyOf(currency);
  await db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: mainCurrencySettingKey, value: currency),
      );
}
