// Data repositories.
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/company_clock.dart';
import '../core/config.dart';
import '../domain/attendance_rules.dart';
import '../domain/leave_rules.dart';
import '../domain/models.dart';
import '../domain/records.dart';
import 'api_client.dart';
import 'db.dart';
import 'location_service.dart';

/// A business-rule failure with a user-friendly message.
class RuleViolation implements Exception {
  final String message;
  const RuleViolation(this.message);
  @override
  String toString() => message;
}

class _Day {
  final String date;
  DateTime? checkIn, checkOut;
  bool pending = false, rejected = false;
  String? reason;
  _Day(this.date);
}

class Repository {
  final ApiClient api;
  final AppDb db;
  final LocationService location;
  CompanyClock clock;
  bool _busy = false; // blocks double taps while an action is in progress
  static const _uuid = Uuid();

  Repository({
    required this.api,
    required this.db,
    required this.location,
    CompanyClock? clock,
  }) : clock = clock ?? CompanyClock('Asia/Kolkata');

  // ---------------------------------------------------------------- helpers
  DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toUtc();

  List<String> _months() {
    final d = DateTime.parse(clock.today());
    final p = DateTime(d.year, d.month - 1);
    String f(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}';
    return [f(d), f(p)];
  }

  Future<Map<String, int>> _balance() async {
    final b = await db.getCache('balance');
    if (b == null) return {'casual': 0, 'sick': 0};
    return Map<String, dynamic>.from(b)
        .map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<Map<String, dynamic>?> _serverRecord(String date) async {
    final list = await db.getCache('attendance:${date.substring(0, 7)}');
    if (list == null) return null;
    for (final r in (list as List)) {
      if (r['date'] == date) return Map<String, dynamic>.from(r);
    }
    return null;
  }

  /// Today's non-rejected events (pending + synced) plus anything the server
  /// already has for today (e.g. checked in from another device).
  Future<List<AttendanceEvent>> _todayEvents() async {
    final today = clock.today();
    final out = [...await db.eventsForDate(today)];
    final rec = await _serverRecord(today);
    if (rec != null) {
      AttendanceEvent fake(EventType t, DateTime at) => AttendanceEvent(
        eventId: 'server-${t.name}-$today',
        type: t,
        timestampUtc: at,
        date: today,
        lat: 0,
        lng: 0,
        status: SyncStatus.synced,
      );
      final i = _dt(rec['checkIn']);
      final o = _dt(rec['checkOut']);
      if (i != null && !out.any((e) => e.type == EventType.checkIn)) {
        out.add(fake(EventType.checkIn, i));
      }
      if (o != null && !out.any((e) => e.type == EventType.checkOut)) {
        out.add(fake(EventType.checkOut, o));
      }
    }
    return out;
  }

  Future<List<DayRecord>> _records() async {
    final byDate = <String, _Day>{};
    for (final m in _months()) {
      final list = await db.getCache('attendance:$m');
      if (list == null) continue;
      for (final r in (list as List)) {
        final d = _Day(r['date'] as String)
          ..checkIn = _dt(r['checkIn'])
          ..checkOut = _dt(r['checkOut']);
        byDate[d.date] = d;
      }
    }
    for (final e in await db.allEvents()) {
      final d = byDate.putIfAbsent(e.date, () => _Day(e.date));
      final isIn = e.type == EventType.checkIn;
      if (e.status == SyncStatus.pending) {
        d.pending = true;
        if (isIn) {
          d.checkIn = e.timestampUtc;
        } else {
          d.checkOut = e.timestampUtc;
        }
      } else if (e.status == SyncStatus.rejected) {
        d.rejected = true;
        d.reason = e.reason ?? 'Rejected by server';
        if (isIn) {
          d.checkIn ??= e.timestampUtc;
        } else {
          d.checkOut ??= e.timestampUtc;
        }
      } else {
        if (isIn) {
          d.checkIn ??= e.timestampUtc;
        } else {
          d.checkOut ??= e.timestampUtc;
        }
      }
    }
    final days = byDate.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return days
        .map(
          (d) => DayRecord(
            date: d.date,
            checkIn: d.checkIn,
            checkOut: d.checkOut,
            status: d.pending
                ? SyncStatus.pending
                : d.rejected
                ? SyncStatus.rejected
                : SyncStatus.synced,
            reason: d.reason,
          ),
        )
        .toList();
  }

  // -------------------------------------------------------------- dashboard
  /// Tries the server first, caches the result, and falls back to the cache
  /// when the server cannot be reached. Throws only if there is no cache.
  Future<DashboardData> loadDashboard() async {
    var offline = false;
    Map<String, dynamic> empJson;
    try {
      empJson = Map<String, dynamic>.from(await api.employee());
      await db.putCache('employee', empJson);
      clock = CompanyClock(empJson['timezone'] as String);
      for (final m in _months()) {
        await db.putCache('attendance:$m', await api.attendance(m));
      }
      await db.putCache('balance', await api.leaveBalance());
    } on ApiException {
      offline = true;
      final cached = await db.getCache('employee');
      if (cached == null) rethrow; // nothing to show -> error state
      empJson = Map<String, dynamic>.from(cached);
      clock = CompanyClock(empJson['timezone'] as String);
    }

    final events = await _todayEvents();
    DateTime? at(EventType t) {
      for (final e in events) {
        if (e.type == t) return e.timestampUtc;
      }
      return null;
    }

    return DashboardData(
      employee: Employee.fromJson(empJson),
      balance: await _balance(),
      records: await _records(),
      status: AttendanceRules.statusFor(events),
      checkIn: at(EventType.checkIn),
      checkOut: at(EventType.checkOut),
      pendingCount: (await db.pendingEvents()).length,
      offline: offline,
    );
  }

  // ------------------------------------------------------------- attendance
  /// Validates, captures GPS, and saves the event locally as Pending.
  /// The caller then triggers SyncEngine.sync().
  Future<AttendanceEvent> record(EventType type) async {
    if (_busy) throw const RuleViolation('Please wait, action in progress.');
    _busy = true;
    try {
      final cached = await db.getCache('employee');
      if (cached == null) {
        throw const RuleViolation(
          'Open the app online once to load your profile.',
        );
      }
      final emp = Employee.fromJson(Map<String, dynamic>.from(cached));
      clock = CompanyClock(emp.timezone);

      final events = await _todayEvents();
      final check = type == EventType.checkIn
          ? AttendanceRules.canCheckIn(events)
          : AttendanceRules.canCheckOut(events);
      if (!check.ok) throw RuleViolation(check.message!);

      final pos = await location.current(); // may throw LocationException
      final inside = AttendanceRules.withinOffice(
        lat: pos.latitude,
        lng: pos.longitude,
        officeLat: Config.officeLat ?? emp.officeLat,
        officeLng: Config.officeLng ?? emp.officeLng,
        radius: emp.radius,
      );
      if (!inside.ok) throw RuleViolation(inside.message!);

      final now = clock.nowUtc();
      final event = AttendanceEvent(
        eventId: _uuid.v4(), // identity + idempotency key, reused on retries
        type: type,
        timestampUtc: now,
        date: clock.dateOf(now),
        lat: pos.latitude,
        lng: pos.longitude,
      );
      await db.insertEvent(event);
      return event;
    } finally {
      _busy = false;
    }
  }

  // ------------------------------------------------------------------ leave
  Future<List<LeaveRequest>> _cachedLeave() async {
    final l = await db.getCache('leave');
    if (l == null) return [];
    return (l as List)
        .map((j) => LeaveRequest.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  Future<LeaveData> loadLeave() async {
    var offline = false;
    try {
      await db.putCache('leave', await api.leaveRequests());
      await db.putCache('balance', await api.leaveBalance());
    } on ApiException {
      offline = true;
      if (await db.getCache('leave') == null) rethrow;
    }
    return LeaveData(
      requests: await _cachedLeave(),
      balance: await _balance(),
      offline: offline,
    );
  }

  /// Local validation first, then the server (which validates again).
  /// Server messages come back as ApiException and are shown to the user.
  Future<void> submitLeave({
    required String type,
    required DateTime start,
    required DateTime end,
    required String reason,
  }) async {
    final error = LeaveRules.validate(
      type: type,
      start: start,
      end: end,
      reason: reason,
      today: DateTime.parse(clock.today()),
      balance: await _balance(),
      existing: await _cachedLeave(),
    );
    if (error != null) throw RuleViolation(error);

    final f = DateFormat('yyyy-MM-dd');
    await api.submitLeave(
      type: type,
      startDate: f.format(start),
      endDate: f.format(end),
      reason: reason.trim(),
    );
  }
}
