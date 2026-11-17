// Leave rules tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:rebs_hrms/domain/leave_rules.dart';
import 'package:rebs_hrms/domain/models.dart';

LeaveRequest _request(String status, String start, String end) => LeaveRequest(
  id: '$status-$start',
  type: 'casual',
  startDate: start,
  endDate: end,
  reason: 'Existing leave request',
  status: status,
);

Map<String, int> get _balance => {'casual': 10, 'sick': 10};

String? _validate({
  DateTime? start,
  DateTime? end,
  String reason = 'A sufficiently detailed reason',
  List<LeaveRequest> existing = const [],
  Map<String, int>? balance,
}) => LeaveRules.validate(
  type: 'casual',
  start: start ?? DateTime(2026, 11, 18),
  end: end ?? DateTime(2026, 11, 18),
  reason: reason,
  today: DateTime(2026, 11, 17),
  balance: balance ?? _balance,
  existing: existing,
);

void main() {
  test('requires both dates and rejects whitespace-only reasons', () {
    expect(
      LeaveRules.validate(
        type: 'casual',
        start: null,
        end: null,
        reason: 'A sufficiently detailed reason',
        today: DateTime(2026, 11, 17),
        balance: _balance,
        existing: const [],
      ),
      contains('Select start and end'),
    );
    expect(_validate(reason: '     \n\t     '), contains('10 characters'));
  });

  test('pending and approved overlapping requests are rejected', () {
    expect(
      _validate(existing: [_request('pending', '2026-11-18', '2026-11-20')]),
      contains('overlap'),
    );
    expect(
      _validate(existing: [_request('approved', '2026-11-18', '2026-11-20')]),
      contains('overlap'),
    );
  });

  test('rejected requests do not block dates', () {
    expect(
      _validate(existing: [_request('rejected', '2026-11-18', '2026-11-20')]),
      isNull,
    );
  });

  test('validates date, reason, and balance rules', () {
    expect(_validate(start: DateTime(2026, 11, 16)), contains('before today'));
    expect(
      _validate(start: DateTime(2026, 11, 20), end: DateTime(2026, 11, 19)),
      contains('before start'),
    );
    expect(_validate(reason: 'too short'), contains('10 characters'));
    expect(
      _validate(
        start: DateTime(2026, 11, 18),
        end: DateTime(2026, 11, 20),
        balance: {'casual': 2, 'sick': 10},
      ),
      contains('only 2'),
    );
  });

  test('counts both start and end dates as leave days', () {
    expect(
      _validate(
        start: DateTime(2026, 11, 18),
        end: DateTime(2026, 11, 20),
        balance: {'casual': 3, 'sick': 10},
      ),
      isNull,
    );
  });
}
