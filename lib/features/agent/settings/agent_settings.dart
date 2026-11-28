import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../app/providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../data/db/app_database.dart';
import '../../../data/db/tables.dart' show Settings;

enum AgentProvider {
  zhipu('Zhipu', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4.7-flash'),
  openRouter(
    'OpenRouter',
    'https://openrouter.ai/api/v1',
    'z-ai/glm-5.3-flash:free',
  ),
  custom('Custom', '', '');

  const AgentProvider(this.label, this.presetBaseUrl, this.presetModel);

  final String label;
  final String presetBaseUrl;
  final String presetModel;
}

class AgentSettings {
  const AgentSettings({
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.hasApiKey,
    required this.largeAmountThreshold,
  });

  final AgentProvider provider;
  final String baseUrl;
  final String model;
  final bool hasApiKey;
  final Money largeAmountThreshold;

  AgentSettings copyWith({
    AgentProvider? provider,
    String? baseUrl,
    String? model,
    Money? largeAmountThreshold,
  }) => AgentSettings(
    provider: provider ?? this.provider,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    hasApiKey: hasApiKey,
    largeAmountThreshold: largeAmountThreshold ?? this.largeAmountThreshold,
  );
}

abstract interface class AgentKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _SecureAgentKeyStore implements AgentKeyStore {
  const _SecureAgentKeyStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

final agentSettingsRepositoryProvider = Provider<AgentSettingsRepository>(
  (ref) => AgentSettingsRepository(
    ref.watch(databaseProvider),
    const _SecureAgentKeyStore(),
  ),
);

final agentSettingsProvider = StreamProvider.autoDispose<AgentSettings>(
  (ref) => ref.watch(agentSettingsRepositoryProvider).watch(),
);

class AgentSettingsRepository {
  AgentSettingsRepository(this._db, this._keyStore);

  final AppDatabase _db;
  final AgentKeyStore _keyStore;

  static const _providerKey = 'agentProvider';
  static const _urlKey = 'agentBaseUrl';
  static const _modelKey = 'agentModel';
  static const _thresholdKey = 'largeAmountThreshold';
  static const _customUrlKey = 'agentCustomBaseUrl';
  static const _customModelKey = 'agentCustomModel';
  static const _defaultThreshold = Money(50000, 'CNY');

  SimpleSelectStatement<Settings, Setting> _query() =>
      _db.select(_db.settings)..where(
        (row) => row.key.isIn(const [
          _providerKey,
          _urlKey,
          _modelKey,
          _thresholdKey,
          _customUrlKey,
          _customModelKey,
        ]),
      );

  Map<String, String> _values(List<Setting> rows) => {
    for (final row in rows) row.key: row.value,
  };

  AgentProvider _provider(Map<String, String> values) =>
      AgentProvider.values.asNameMap()[values[_providerKey]] ??
      AgentProvider.zhipu;

  Money _threshold(String? raw) {
    final parsed = RegExp(r'^([0-9]+):([A-Z]{3})$').firstMatch(raw ?? '');
    if (parsed == null) return _defaultThreshold;
    final minor = int.tryParse(parsed[1]!);
    if (minor == null) return _defaultThreshold;
    final code = parsed[2]!;
    try {
      currencyOf(code);
      return Money(minor, code);
    } on ArgumentError {
      return _defaultThreshold;
    }
  }

  Stream<AgentSettings> watch() => _query().watch().asyncMap((rows) async {
    final values = _values(rows);
    final provider = _provider(values);
    return AgentSettings(
      provider: provider,
      baseUrl: provider == AgentProvider.custom
          ? values[_customUrlKey] ?? ''
          : provider.presetBaseUrl,
      model: values[_modelKey] ?? provider.presetModel,
      hasApiKey: (await apiKey(provider))?.isNotEmpty ?? false,
      largeAmountThreshold: _threshold(values[_thresholdKey]),
    );
  });

  Future<void> save(AgentSettings settings) => _db.transaction(() async {
    final values = _values(await _query().get());
    final provider = settings.provider;
    final switched = provider != _provider(values);
    final threshold = settings.largeAmountThreshold;
    currencyOf(threshold.currency);
    if (threshold.minor < 0) {
      throw const FormatException('Enter a threshold of zero or more.');
    }
    var baseUrl = provider.presetBaseUrl;
    var model = switched ? provider.presetModel : settings.model.trim();
    if (provider == AgentProvider.custom) {
      final previous = values[_customUrlKey] ?? '';
      baseUrl = switched ? previous : settings.baseUrl.trim();
      model = switched ? values[_customModelKey] ?? '' : model;
      if (baseUrl.isNotEmpty || previous.isNotEmpty) {
        final url = Uri.tryParse(baseUrl);
        if (url == null ||
            url.scheme != 'https' ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty) {
          throw const FormatException(
            'Enter an HTTPS URL without credentials.',
          );
        }
        if (Uri.tryParse(previous)?.host != url.host) {
          // Clear before publishing the new host so the old key cannot be reused.
          await _keyStore.delete(_keyName(provider));
        }
      }
    }
    final updates = {
      _providerKey: provider.name,
      _urlKey: baseUrl,
      _modelKey: model,
      _thresholdKey: '${threshold.minor}:${threshold.currency}',
      if (provider == AgentProvider.custom) _customUrlKey: baseUrl,
      if (provider == AgentProvider.custom) _customModelKey: model,
    };
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.settings, [
        for (final entry in updates.entries)
          SettingsCompanion.insert(key: entry.key, value: entry.value),
      ]);
    });
  });

  String _keyName(AgentProvider provider) => 'apiKey.${provider.name}';

  Future<void> setApiKey(AgentProvider provider, String key) async {
    final value = key.trim();
    if (value.isEmpty) throw const FormatException('Enter an API key.');
    await _changeKey(() => _keyStore.write(_keyName(provider), value));
  }

  Future<String?> apiKey(AgentProvider provider) =>
      _keyStore.read(_keyName(provider));

  Future<void> clearApiKey(AgentProvider provider) =>
      _changeKey(() => _keyStore.delete(_keyName(provider)));

  Future<void> _changeKey(Future<void> Function() change) async {
    await _db.transaction(change);
    // Key values stay in secure storage. Refresh the watched Settings snapshot.
    _db.notifyUpdates({
      TableUpdate.onTable(_db.settings, kind: UpdateKind.update),
    });
  }
}
