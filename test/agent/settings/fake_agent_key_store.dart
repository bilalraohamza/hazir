import 'package:budget_app/features/agent/settings/agent_settings.dart';

class FakeAgentKeyStore implements AgentKeyStore {
  final keys = <String, String>{};

  @override
  Future<String?> read(String key) async => keys[key];

  @override
  Future<void> write(String key, String value) async {
    keys[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    keys.remove(key);
  }
}
