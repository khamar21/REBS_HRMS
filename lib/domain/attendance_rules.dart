// Attendance business rules.
import 'dart:math';

import 'models.dart';

enum DayStatus { notCheckedIn, checkedIn, checkedOut }

class RuleResult {
  final bool ok;
  final String? message;
  const RuleResult.ok() : ok = true, message = null;
  const RuleResult.fail(this.message) : ok = false;
}

class AttendanceRules {
  /// [todayEvents] = non-rejected events (synced + pending) for the company date.
  static DayStatus statusFor(List<AttendanceEvent> todayEvents) {
    final hasIn = todayEvents.any((e) => e.type == EventType.checkIn);
    final hasOut = todayEvents.any((e) => e.type == EventType.checkOut);
    if (hasIn && hasOut) return DayStatus.checkedOut;
    if (hasIn) return DayStatus.checkedIn;
    return DayStatus.notCheckedIn;
  }

  static RuleResult canCheckIn(List<AttendanceEvent> todayEvents) {
    return statusFor(todayEvents) == DayStatus.notCheckedIn
        ? const RuleResult.ok()
        : const RuleResult.fail('You have already checked in today.');
  }

  static RuleResult canCheckOut(List<AttendanceEvent> todayEvents) {
    switch (statusFor(todayEvents)) {
      case DayStatus.notCheckedIn:
        return const RuleResult.fail('Check in first before checking out.');
      case DayStatus.checkedOut:
        return const RuleResult.fail('You have already checked out today.');
      case DayStatus.checkedIn:
        return const RuleResult.ok();
    }
  }

  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371000.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a =
        pow(sin(dLat / 2), 2) +
        cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLng / 2), 2);
    return 2 * r * asin(sqrt(a));
  }

  static RuleResult withinOffice({
    required double lat,
    required double lng,
    required double officeLat,
    required double officeLng,
    required double radius,
  }) {
    final d = distanceMeters(lat, lng, officeLat, officeLng);
    if (d <= radius) return const RuleResult.ok();
    return RuleResult.fail(
      'You are ${d.round()} m from the office. You must be within ${radius.round()} m.',
    );
  }
}
