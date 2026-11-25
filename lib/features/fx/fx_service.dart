import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../core/money/convert.dart';
import '../../data/db/app_database.dart';
import 'rates_api.dart';

class FxService {
  FxService(this._db, this._api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final RatesApi _api;
  final DateTime Function() _clock;
  final _refreshes = <String, Future<void>>{};

  static String _localDay(DateTime at) =>
      at.toLocal().toIso8601String().split('T').first;

  Future<String?> snapshotDayFor(DateTime date) async {
    final latest =
        await (_db.select(_db.fxSnapshots)
              ..where((s) => s.day.isSmallerOrEqualValue(_localDay(date)))
              ..orderBy([(s) => OrderingTerm.desc(s.day)])
              ..limit(1))
            .getSingleOrNull();
    return latest?.day;
  }

  Future<bool> isStale() async {
    final now = _clock();
    return await snapshotDayFor(now) != _localDay(now);
  }

  Future<Decimal?> rate(String from, String to, {DateTime? on}) async {
    if (from == to) return Decimal.one;
    final day = await snapshotDayFor(on ?? _clock());
    if (day == null) return null;
    return rateForDay(from, to, day);
  }

  Future<Decimal?> rateForDay(String from, String to, String day) async {
    if (from == to) return Decimal.one;
    final rows = await (_db.select(
      _db.fxSnapshots,
    )..where((s) => s.day.equals(day) & s.currency.isIn([from, to]))).get();
    final rates = {
      for (final row in rows) row.currency: Decimal.parse(row.perUsd),
    };
    final fromRate = rates[from];
    final toRate = rates[to];
    if (fromRate == null || toRate == null) return null;
    return crossRate(fromRate, toRate);
  }

  Future<void> refreshIfNeeded() {
    final now = _clock();
    final day = _localDay(now);
    return _refreshes.putIfAbsent(
      day,
      () => _refresh(now, day).whenComplete(() {
        _refreshes.remove(day);
      }),
    );
  }

  Future<void> _refresh(DateTime now, String day) async {
    if (await snapshotDayFor(now) == day) return;
    final Map<String, Decimal> rates;
    try {
      rates = await _api.latestPerUsd();
    } catch (_) {
      return;
    }
    final rows = [
      for (final entry in rates.entries)
        if (entry.value > Decimal.zero)
          FxSnapshotsCompanion.insert(
            day: day,
            currency: entry.key,
            perUsd: entry.value.toString(),
            fetchedAt: now,
          ),
    ];
    if (rows.isEmpty) return;
    await _db.transaction(() async {
      // Another service can finish a fetch while this one is awaiting the API.
      if (await snapshotDayFor(now) == day) return;
      await _db.batch((batch) => batch.insertAll(_db.fxSnapshots, rows));
      await backfillFxDays();
    });
  }

  Future<void> backfillFxDays() async {
    // Drift stores DateTime as Unix seconds. Compare local calendar days.
    await _db.customUpdate(
      '''
      UPDATE transactions
      SET fx_day = (
        SELECT MIN(day) FROM fx_snapshots
        WHERE day >= date(transactions.occurred_at, 'unixepoch', 'localtime')
      )
      WHERE fx_day IS NULL
        AND date(occurred_at, 'unixepoch', 'localtime') <= (SELECT MAX(day) FROM fx_snapshots)
    ''',
      updates: {_db.transactions},
    );
  }
}
