// Synchronization engine tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:rebs_hrms/data/api_client.dart';
import 'package:rebs_hrms/data/db.dart';
import 'package:rebs_hrms/domain/models.dart';
import 'package:rebs_hrms/sync/sync_engine.dart';

class FakeApiClient extends ApiClient {
  final List<SubmitResult> outcomes;
  final List<String> eventIds = [];

  FakeApiClient(this.outcomes) : super(scenario: 'success');

  @override
  Future<SubmitResult> submitEvent(AttendanceEvent event) async {
    eventIds.add(event.eventId);
    if (outcomes.isEmpty) return const SubmitResult(SubmitOutcome.synced);
    return outcomes.removeAt(0);
  }
}

AttendanceEvent _event(String id, EventType type, int minute) =>
    AttendanceEvent(
      eventId: id,
      type: type,
      timestampUtc: DateTime.utc(2026, 11, 17, 8, minute),
      date: '2026-11-17',
      lat: 10,
      lng: 76,
    );

Future<AppDb> _open(String path) => AppDb.open(path: path);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('timeout retry reuses eventId and produces one synced record', () async {
    final path = '${Directory.systemTemp.path}\\rebs_timeout_test.db';
    final db = await _open(path);
    final event = _event('same-id', EventType.checkIn, 0);
    await db.insertEvent(event);
    final api = FakeApiClient([
      const SubmitResult(SubmitOutcome.transient, 'timeout'),
      const SubmitResult(SubmitOutcome.synced),
    ]);

    final first = await SyncEngine(db: db, api: api).sync();
    final second = await SyncEngine(db: db, api: api).sync();

    expect(first.remaining, 1);
    expect(second.synced, 1);
    expect(api.eventIds, ['same-id', 'same-id']);
    expect((await db.allEvents()).single.status, SyncStatus.synced);
    await db.db.close();
    File(path).deleteSync();
  });

  test('pending events survive reopen and sync in sequence order', () async {
    final path = '${Directory.systemTemp.path}\\rebs_order_test.db';
    var db = await _open(path);
    await db.insertEvent(_event('first', EventType.checkIn, 0));
    await db.insertEvent(_event('second', EventType.checkOut, 1));
    await db.db.close();

    db = await _open(path);
    final api = FakeApiClient([]);
    await SyncEngine(db: db, api: api).sync();

    expect(api.eventIds, ['first', 'second']);
    expect((await db.pendingEvents()), isEmpty);
    await db.db.close();
    File(path).deleteSync();
  });

  test(
    'transient failure stops the queue and keeps later events pending',
    () async {
      final db = await _open(inMemoryDatabasePath);
      await db.insertEvent(_event('first', EventType.checkIn, 0));
      await db.insertEvent(_event('second', EventType.checkOut, 1));
      final api = FakeApiClient([const SubmitResult(SubmitOutcome.transient)]);

      final report = await SyncEngine(db: db, api: api).sync();

      expect(report.interrupted, isTrue);
      expect(api.eventIds, ['first']);
      expect((await db.pendingEvents()).map((e) => e.eventId), [
        'first',
        'second',
      ]);
      await db.db.close();
    },
  );

  test('a 409-style rejected result marks the event rejected', () async {
    final db = await _open(inMemoryDatabasePath);
    await db.insertEvent(_event('duplicate', EventType.checkIn, 0));
    final api = FakeApiClient([
      const SubmitResult(SubmitOutcome.rejected, 'Attendance already exists'),
    ]);

    final report = await SyncEngine(db: db, api: api).sync();

    expect(report.rejected, 1);
    expect((await db.allEvents()).single.status, SyncStatus.rejected);
    expect((await db.allEvents()).single.reason, 'Attendance already exists');
    await db.db.close();
  });
}
