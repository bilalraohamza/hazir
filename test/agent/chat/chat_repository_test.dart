import 'dart:async';

import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/agent/chat/chat_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ChatRepository repository;
  late DateTime now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    now = DateTime(2026, 11, 28, 12);
    repository = ChatRepository(db, clock: () => now);
  });

  test(
    'groups replies and actions by turn and orders each group by time then ID',
    () async {
      final first = await repository.addUser('first');
      final second = await repository.addUser('second');
      now = now.add(const Duration(seconds: 5));
      final lateReply = await repository.addAssistant(first, 'later');
      final lateAction = await repository.addAction(
        turnId: first,
        kind: 'saved',
        status: 'saved',
      );
      now = now.subtract(const Duration(seconds: 2));
      final earlyReply = await repository.addAssistant(first, 'earlier');
      final tiedReply = await repository.addAssistant(first, 'same time');
      final earlyAction = await repository.addAction(
        turnId: first,
        kind: 'proposed',
        status: 'pending',
      );
      final tiedAction = await repository.addAction(
        turnId: first,
        kind: 'proposed',
        status: 'pending',
      );
      await repository.addAssistant(second, 'separate');

      final turns = await repository.watchTurns().first;
      expect(turns.map((turn) => turn.user.id), [first, second]);
      expect(turns.first.user.role, 'user');
      expect(turns.first.user.turnId, isNull);
      expect(turns.first.replies.map((reply) => reply.id), [
        earlyReply,
        tiedReply,
        lateReply,
      ]);
      expect(
        turns.first.replies.map((reply) => (reply.role, reply.turnId)),
        everyElement(('assistant', first)),
      );
      expect(turns.first.actions.map((action) => action.id), [
        earlyAction,
        tiedAction,
        lateAction,
      ]);
      expect(
        (await repository.actionsForTurn(first)).map((action) => action.id),
        [earlyAction, tiedAction, lateAction],
      );
      expect(turns.last.replies.single.text, 'separate');
      expect(turns.last.actions, isEmpty);
    },
  );

  test(
    'the turn stream emits an error action before any reply exists',
    () async {
      final stream = StreamIterator(repository.watchTurns());
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current, isEmpty);
      final turn = await repository.addUser('hello');
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.single.user.id, turn);
      final id = await repository.addAction(
        turnId: turn,
        kind: 'error',
        status: 'failed',
        resultJson: '{"kind":"network"}',
      );
      expect(await stream.moveNext(), isTrue);
      final updated = stream.current.single;
      expect(updated.replies, isEmpty);
      expect(updated.actions.single.id, id);
      expect(updated.actions.single.toolName, isNull);
      expect(updated.actions.single.argumentsJson, isNull);
      expect(updated.actions.single.resultJson, '{"kind":"network"}');
      await repository.addAssistant(turn, 'recovered');
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.single.replies.single.text, 'recovered');
    },
  );

  test(
    'updates action status and retains optional metadata when omitted',
    () async {
      final turn = await repository.addUser('log lunch');
      final id = await repository.addAction(
        turnId: turn,
        kind: 'proposed',
        status: 'pending',
        toolName: 'add_expense',
        argumentsJson: '{"amount":"28.00"}',
      );
      expect((await repository.action(id))!.status, 'pending');
      await repository.setActionStatus(
        id,
        'confirmed',
        transactionId: 42,
        resultJson: '{"saved":true}',
      );
      await repository.setActionStatus(id, 'undone');
      final updated = (await repository.action(id))!;
      expect(updated.status, 'undone');
      expect(updated.transactionId, 42);
      expect(updated.argumentsJson, '{"amount":"28.00"}');
      expect(updated.resultJson, '{"saved":true}');
      expect(await repository.action(id + 1), isNull);
    },
  );

  test(
    'historyBefore limits both roles by message ID and returns oldest first',
    () async {
      final earlier = await repository.addUser('earlier');
      final reply = await repository.addAssistant(earlier, 'prior reply');
      final current = await repository.addUser('current');
      await repository.addAssistant(earlier, 'late reply to an earlier turn');
      await repository.addUser('next');
      expect(
        (await repository.historyBefore(current, 8)).map((row) => row.id),
        [earlier, reply],
      );
      expect((await repository.historyBefore(current, 1)).single.id, reply);
      expect(await repository.historyBefore(current, 0), isEmpty);
    },
  );

  test(
    'watchTurns limits user turns and includes their full replies',
    () async {
      final first = await repository.addUser('first');
      final second = await repository.addUser('second');
      final third = await repository.addUser('third');
      await repository.addAssistant(first, 'out of window');
      await repository.addAssistant(second, 'one');
      await repository.addAssistant(second, 'two');
      final turns = await repository.watchTurns(limit: 2).first;
      expect(turns.map((turn) => turn.user.id), [second, third]);
      expect(turns.first.replies.map((reply) => reply.text), ['one', 'two']);
      expect(await repository.watchTurns(limit: 0).first, isEmpty);
    },
  );

  test(
    'rejects invalid roles, kinds, statuses, and assistant turn targets',
    () async {
      final turn = await repository.addUser('hello');
      final reply = await repository.addAssistant(turn, 'reply');
      await expectLater(
        Future.sync(
          () => db
              .into(db.chatMessages)
              .insert(
                ChatMessagesCompanion.insert(
                  role: 'system',
                  messageText: 'invalid',
                  createdAt: now,
                ),
              ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.addAction(turnId: turn, kind: 'answer', status: 'saved'),
        throwsArgumentError,
      );
      await expectLater(
        repository.addAction(turnId: turn, kind: 'saved', status: 'unknown'),
        throwsArgumentError,
      );
      final action = await repository.addAction(
        turnId: turn,
        kind: 'saved',
        status: 'saved',
      );
      await expectLater(
        repository.setActionStatus(action, 'unknown'),
        throwsArgumentError,
      );
      expect((await repository.action(action))!.status, 'saved');
      await expectLater(
        repository.addAssistant(reply, 'invalid'),
        throwsArgumentError,
      );
      await expectLater(
        repository.addAction(turnId: reply, kind: 'error', status: 'failed'),
        throwsArgumentError,
      );
    },
  );
}
