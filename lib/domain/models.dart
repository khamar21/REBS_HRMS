// Domain models.
enum EventType { checkIn, checkOut }

enum SyncStatus { pending, synced, rejected }

class AttendanceEvent {
  final int? seq;
  final String eventId;
  final EventType type;
  final DateTime timestampUtc;
  final String date; // company-local YYYY-MM-DD
  final double lat;
  final double lng;
  final SyncStatus status;
  final String? reason;

  const AttendanceEvent({
    this.seq,
    required this.eventId,
    required this.type,
    required this.timestampUtc,
    required this.date,
    required this.lat,
    required this.lng,
    this.status = SyncStatus.pending,
    this.reason,
  });

  AttendanceEvent copyWith({SyncStatus? status, String? reason}) =>
      AttendanceEvent(
        seq: seq,
        eventId: eventId,
        type: type,
        timestampUtc: timestampUtc,
        date: date,
        lat: lat,
        lng: lng,
        status: status ?? this.status,
        reason: reason ?? this.reason,
      );

  Map<String, Object?> toMap() => {
    'event_id': eventId,
    'type': type.name,
    'timestamp': timestampUtc.toIso8601String(),
    'date': date,
    'lat': lat,
    'lng': lng,
    'status': status.name,
    'reason': reason,
  };

  factory AttendanceEvent.fromMap(Map<String, Object?> m) => AttendanceEvent(
    seq: m['seq'] as int?,
    eventId: m['event_id'] as String,
    type: EventType.values.byName(m['type'] as String),
    timestampUtc: DateTime.parse(m['timestamp'] as String),
    date: m['date'] as String,
    lat: (m['lat'] as num).toDouble(),
    lng: (m['lng'] as num).toDouble(),
    status: SyncStatus.values.byName(m['status'] as String),
    reason: m['reason'] as String?,
  );

  Map<String, Object?> toApiBody() => {
    'eventId': eventId,
    'type': type == EventType.checkIn ? 'check_in' : 'check_out',
    'timestamp': timestampUtc.toIso8601String(),
    'date': date,
    'lat': lat,
    'lng': lng,
  };
}

class Employee {
  final String id, name, department, timezone;
  final double officeLat, officeLng, radius;
  Employee({
    required this.id,
    required this.name,
    required this.department,
    required this.timezone,
    required this.officeLat,
    required this.officeLng,
    required this.radius,
  });

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
    id: j['id'],
    name: j['name'],
    department: j['department'],
    timezone: j['timezone'],
    officeLat: (j['office']['lat'] as num).toDouble(),
    officeLng: (j['office']['lng'] as num).toDouble(),
    radius: (j['office']['radiusMeters'] as num).toDouble(),
  );
}

class LeaveRequest {
  final String id, type, startDate, endDate, reason, status;
  LeaveRequest({
    required this.id,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
  });
  factory LeaveRequest.fromJson(Map<String, dynamic> j) => LeaveRequest(
    id: j['id'],
    type: j['type'],
    startDate: j['startDate'],
    endDate: j['endDate'],
    reason: j['reason'],
    status: j['status'],
  );
}
