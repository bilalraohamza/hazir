enum ToolKind { read, write, destructive }

typedef ToolCallback = Future<ToolResult> Function(Map<String, Object?>);

class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
    required this.kind,
    this.run,
    this.validate,
    this.execute,
  }) : assert(
         kind == ToolKind.read
             ? run != null && validate == null && execute == null
             : run == null && validate != null && execute != null,
       );

  final String name;
  final String description;
  final Map<String, Object?> parameters;
  final ToolKind kind;
  final ToolCallback? run;
  final ToolCallback? validate;
  final ToolCallback? execute;
}

sealed class ToolResult {
  const ToolResult();

  Map<String, Object?> toJson();
}

class ToolOk extends ToolResult {
  const ToolOk(this.data);

  final Map<String, Object?> data;

  @override
  Map<String, Object?> toJson() => data;
}

class ToolError extends ToolResult {
  const ToolError(this.code, this.message);

  final String code;
  final String message;

  @override
  Map<String, Object?> toJson() => {
    'error': {'code': code, 'message': message},
  };
}
