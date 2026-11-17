// Local database access.
import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

class AppDb {
  final Database db;
  AppDb(this.db);

  static Future<AppDb> open({String? path}) async {
    final p = path ?? join(await getDatabasesPath(), 'rebs.db');
    final db = await openDatabase(
      p,
      version: 1,
      onCreate: (d, _) async {
        await d.execute('''
        CREATE TABLE attendance_events(
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          event_id TEXT UNIQUE NOT NULL,
          type TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          date TEXT NOT NULL,
          lat REAL, lng REAL,
          status TEXT NOT NULL,
          reason TEXT)''');
        await d.execute(
          'CREATE TABLE cache(key TEXT PRIMARY KEY, json TEXT NOT NULL)',
        );
      },
    );
    return AppDb(db);
  }

  // ---- JSON cache (dashboard, history, balance, leave requests) ----
  Future<void> putCache(String key, Object value) => db.insert('cache', {
    'key': key,
    'json': jsonEncode(value),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<dynamic> getCache(String key) async {
    final r = await db.query('cache', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : jsonDecode(r.first['json'] as String);
  }

  // ---- Event queue ----
  Future<void> insertEvent(AttendanceEvent e) => db.insert(
    'attendance_events',
    e.toMap(),
    conflictAlgorithm: ConflictAlgorithm.ignore,
  ); // UNIQUE event_id

  Future<List<AttendanceEvent>> allEvents() async => (await db.query(
    'attendance_events',
    orderBy: 'seq ASC',
  )).map(AttendanceEvent.fromMap).toList();

  Future<List<AttendanceEvent>> pendingEvents() async => (await db.query(
    'attendance_events',
    where: 'status = ?',
    whereArgs: ['pending'],
    orderBy: 'seq ASC',
  )).map(AttendanceEvent.fromMap).toList();

  Future<List<AttendanceEvent>> eventsForDate(String date) async =>
      (await db.query(
        'attendance_events',
        where: 'date = ? AND status != ?',
        whereArgs: [date, 'rejected'],
        orderBy: 'seq ASC',
      )).map(AttendanceEvent.fromMap).toList();

  Future<void> setStatus(String eventId, SyncStatus s, {String? reason}) =>
      db.update(
        'attendance_events',
        {'status': s.name, 'reason': reason},
        where: 'event_id = ?',
        whereArgs: [eventId],
      );
}
