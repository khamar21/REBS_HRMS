// Attendance rules tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:rebs_hrms/domain/attendance_rules.dart';
import 'package:rebs_hrms/domain/models.dart';

AttendanceEvent _event(EventType type) => AttendanceEvent(
  eventId: '${type.name}-1',
  type: type,
  timestampUtc: DateTime.utc(2026, 11, 17, 8),
  date: '2026-11-17',
  lat: 10,
  lng: 76,
);

void main() {
  test('check-out without check-in is rejected', () {
    final result = AttendanceRules.canCheckOut([]);
    expect(result.ok, isFalse);
    expect(result.message, contains('Check in first'));
  });

  test('a second check-in is rejected', () {
    final result = AttendanceRules.canCheckIn([_event(EventType.checkIn)]);
    expect(result.ok, isFalse);
    expect(result.message, contains('already checked in'));
  });

  test('check-in is rejected outside the configured geofence', () {
    final result = AttendanceRules.withinOffice(
      lat: 10.02,
      lng: 76,
      officeLat: 10,
      officeLng: 76,
      radius: 200,
    );
    expect(result.ok, isFalse);
    expect(result.message, contains('within 200 m'));
  });

  test('a location at the office is accepted', () {
    final result = AttendanceRules.withinOffice(
      lat: 10,
      lng: 76,
      officeLat: 10,
      officeLng: 76,
      radius: 200,
    );
    expect(result.ok, isTrue);
  });
}
