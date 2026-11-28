import 'package:drift/drift.dart';

import '../../../data/db/app_database.dart';

export '../../../data/db/app_database.dart'
    show ChatAction, ChatMessage, ChatMessageText;

class ChatTurn {
  const ChatTurn({
    required this.user,
    required this.actions,
    required this.replies,
  });

  final ChatMessage user;
  final List<ChatAction> actions;
  final List<ChatMessage> replies;
}

class ChatRepository {
  ChatRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Stream<List<ChatTurn>> watchTurns({int limit = 100}) {
    RangeError.checkNotNegative(limit, 'limit');
    final messages = _db.chatMessages;
    final actions = _db.chatActions;
    return _db
        .customSelect('SELECT 1', readsFrom: {messages, actions})
        .watch()
        .asyncMap(
          (_) => _db.transaction(() async {
            final recentIds = _db.selectOnly(messages)
              ..addColumns([messages.id])
              ..where(messages.role.equals('user'))
              ..orderBy([
                OrderingTerm.desc(messages.createdAt),
                OrderingTerm.desc(messages.id),
              ])
              ..limit(limit);
            final users =
                await (_db.select(messages)
                      ..where((row) => row.id.isInQuery(recentIds))
                      ..orderBy([
                        (row) => OrderingTerm.asc(row.createdAt),
                        (row) => OrderingTerm.asc(row.id),
                      ]))
                    .get();
            final replies =
                await (_db.select(messages)
                      ..where((row) => row.turnId.isInQuery(recentIds))
                      ..orderBy([
                        (row) => OrderingTerm.asc(row.createdAt),
                        (row) => OrderingTerm.asc(row.id),
                      ]))
                    .get();
            final rows =
                await (_db.select(actions)
                      ..where((row) => row.turnId.isInQuery(recentIds))
                      ..orderBy([
                        (row) => OrderingTerm.asc(row.createdAt),
                        (row) => OrderingTerm.asc(row.id),
                      ]))
                    .get();
            final repliesByTurn = <int, List<ChatMessage>>{};
            final actionsByTurn = <int, List<ChatAction>>{};
            for (final reply in replies) {
              repliesByTurn.putIfAbsent(reply.turnId!, () => []).add(reply);
            }
            for (final action in rows) {
              actionsByTurn.putIfAbsent(action.turnId, () => []).add(action);
            }
            return [
              for (final user in users)
                ChatTurn(
                  user: user,
                  actions: actionsByTurn[user.id] ?? const [],
                  replies: repliesByTurn[user.id] ?? const [],
                ),
            ];
          }),
        );
  }

  Future<int> addUser(String text) => _db
      .into(_db.chatMessages)
      .insert(
        ChatMessagesCompanion.insert(
          role: 'user',
          messageText: text,
          createdAt: _clock(),
        ),
      );

  Future<int> addAssistant(int turnId, String text) =>
      _db.transaction(() async {
        await _requireUserTurn(turnId);
        return _db
            .into(_db.chatMessages)
            .insert(
              ChatMessagesCompanion.insert(
                role: 'assistant',
                messageText: text,
                turnId: Value(turnId),
                createdAt: _clock(),
              ),
            );
      });

  Future<int> addAction({
    required int turnId,
    required String kind,
    required String status,
    String? toolName,
    String? argumentsJson,
    int? transactionId,
    String? resultJson,
  }) => _db.transaction(() async {
    await _requireUserTurn(turnId);
    return _db
        .into(_db.chatActions)
        .insert(
          ChatActionsCompanion.insert(
            turnId: turnId,
            kind: kind,
            status: status,
            toolName: Value(toolName),
            argumentsJson: Value(argumentsJson),
            transactionId: Value(transactionId),
            resultJson: Value(resultJson),
            createdAt: _clock(),
          ),
        );
  });

  Future<void> setActionStatus(
    int id,
    String status, {
    int? transactionId,
    String? resultJson,
  }) async {
    final count =
        await (_db.update(
          _db.chatActions,
        )..where((row) => row.id.equals(id))).write(
          ChatActionsCompanion(
            status: Value(status),
            transactionId: transactionId == null
                ? const Value.absent()
                : Value(transactionId),
            resultJson: resultJson == null
                ? const Value.absent()
                : Value(resultJson),
          ),
        );
    if (count == 0) throw ArgumentError.value(id, 'id', 'Unknown chat action');
  }

  Future<ChatAction?> action(int id) => (_db.select(
    _db.chatActions,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<List<ChatAction>> actionsForTurn(int turnId) =>
      (_db.select(_db.chatActions)
            ..where((row) => row.turnId.equals(turnId))
            ..orderBy([
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.id),
            ]))
          .get();

  Future<List<ChatMessage>> historyBefore(int turnId, int n) async {
    RangeError.checkNotNegative(n, 'n');
    final rows =
        await (_db.select(_db.chatMessages)
              ..where((row) => row.id.isSmallerThanValue(turnId))
              ..orderBy([(row) => OrderingTerm.desc(row.id)])
              ..limit(n))
            .get();
    return rows.reversed.toList();
  }

  Future<void> _requireUserTurn(int turnId) async {
    final turn =
        await (_db.select(_db.chatMessages)
              ..where((row) => row.id.equals(turnId) & row.role.equals('user')))
            .getSingleOrNull();
    if (turn == null) {
      throw ArgumentError.value(turnId, 'turnId', 'Expected a user message');
    }
  }
}
