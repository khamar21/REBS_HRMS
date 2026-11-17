import 'attendance_rules.dart';
import 'models.dart';

// One row in the attendance history (one per company date).
class DayRecord {
  final String date;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final SyncStatus status; // pending > rejected > synced
  final String? reason;
  const DayRecord({
    required this.date,
    this.checkIn,
    this.checkOut,
    required this.status,
    this.reason,
  });
}

class DashboardData {
  final Employee employee;
  final Map<String, int> balance;
  final List<DayRecord> records; // newest first
  final DayStatus status;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int pendingCount;
  final bool offline; // true = showing cached data

  const DashboardData({
    required this.employee,
    required this.balance,
    required this.records,
    required this.status,
    this.checkIn,
    this.checkOut,
    required this.pendingCount,
    required this.offline,
  });

  List<DayRecord> get recent => records.take(5).toList();
}

class LeaveData {
  final List<LeaveRequest> requests;
  final Map<String, int> balance;
  final bool offline;
  const LeaveData({
    required this.requests,
    required this.balance,
    required this.offline,
  });
}
