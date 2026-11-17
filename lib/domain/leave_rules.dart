// Leave business rules.
import 'models.dart';

class LeaveRules {
  /// Returns an error message, or null if the form is valid.
  /// Dates are 'YYYY-MM-DD' strings in company time.
  static String? validate({
    required String type,
    required DateTime? start,
    required DateTime? end,
    required String reason,
    required DateTime today, // company date, time part ignored
    required Map<String, int> balance,
    required List<LeaveRequest> existing,
  }) {
    if (start == null || end == null) return 'Select start and end dates.';
    final t = DateTime(today.year, today.month, today.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);

    if (s.isBefore(t)) return 'Start date cannot be before today.';
    if (e.isBefore(s)) return 'End date cannot be before start date.';

    final nonSpace = reason.replaceAll(RegExp(r'\s'), '').length;
    if (nonSpace < 10) return 'Reason must have at least 10 characters.';

    final days = e.difference(s).inDays + 1;
    final available = balance[type] ?? 0;
    if (days > available) {
      return 'You requested $days days but only $available are available.';
    }

    for (final r in existing) {
      if (r.status != 'pending' && r.status != 'approved') continue;
      final rs = DateTime.parse(r.startDate);
      final re = DateTime.parse(r.endDate);
      final overlaps = !s.isAfter(re) && !e.isBefore(rs);
      if (overlaps) {
        return 'Dates overlap an existing ${r.status} request '
            '(${r.startDate} to ${r.endDate}).';
      }
    }
    return null;
  }
}
 