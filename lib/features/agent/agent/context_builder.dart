import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../data/db/app_database.dart';
import '../settings/agent_settings.dart';

class AgentContext {
  const AgentContext({
    required this.now,
    required this.mainCurrency,
    required this.threshold,
    required this.accounts,
    required this.categories,
  });

  final DateTime now;
  final String mainCurrency;
  final Money threshold;
  final List<Account> accounts;
  final List<Category> categories;

  String toPromptBlock() {
    final local = now.toLocal();
    final date = DateFormat('EEEE yyyy-MM-dd HH:mm', 'en_US').format(local);
    final offset = local.timeZoneOffset.inMinutes;
    final sign = offset.isNegative ? '-' : '+';
    final hours = (offset.abs() ~/ 60).toString().padLeft(2, '0');
    final minutes = (offset.abs() % 60).toString().padLeft(2, '0');
    return [
      'Today: $date (UTC$sign$hours:$minutes)',
      'Main currency: $mainCurrency',
      'Large-amount threshold: ${formatMoney(threshold)}',
      'Active accounts:',
      for (final account in accounts)
        '${account.id}, ${_oneLine(account.name)}, ${account.currency}',
      'Active categories:',
      for (final category in categories)
        '${category.id}, ${_oneLine(category.name)}, ${category.kind}',
    ].join('\n');
  }

  static String _oneLine(String value) =>
      value.replaceAll(RegExp(r'[\r\n]+'), ' ');
}

class AgentContextBuilder {
  AgentContextBuilder(this._db, this._settings, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final AgentSettingsRepository _settings;
  final DateTime Function() _clock;

  Future<AgentContext> build() => _db.transaction(() async {
    final now = _clock();
    final currency = await (_db.select(
      _db.settings,
    )..where((row) => row.key.equals('mainCurrency'))).getSingle();
    final accounts =
        await (_db.select(_db.accounts)
              ..where((row) => row.archived.equals(false))
              ..orderBy([
                (row) => OrderingTerm.asc(row.sortOrder),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final categories =
        await (_db.select(_db.categories)
              ..where((row) => row.archived.equals(false))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    return AgentContext(
      now: now,
      mainCurrency: currency.value,
      threshold: await _settings.readLargeAmountThreshold(),
      accounts: accounts,
      categories: categories,
    );
  });
}
