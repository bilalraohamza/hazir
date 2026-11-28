import 'tool_spec.dart';

class ToolRegistry {
  final _tools = <String, ToolSpec>{};

  void register(ToolSpec s) {
    if (_tools.containsKey(s.name)) {
      throw ArgumentError.value(s.name, 'name', 'Duplicate tool name');
    }
    _tools[s.name] = s;
  }

  List<Map<String, Object?>> schemas() => [
    for (final tool in _tools.values)
      {
        'type': 'function',
        'function': {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.parameters,
        },
      },
  ];

  ToolSpec? byName(String n) => _tools[n];
}
