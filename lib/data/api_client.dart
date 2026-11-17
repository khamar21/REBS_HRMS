// Remote API client.
import 'package:dio/dio.dart';

import '../core/config.dart';
import '../domain/models.dart';

enum SubmitOutcome { synced, rejected, transient }

class SubmitResult {
  final SubmitOutcome outcome;
  final String? message;
  const SubmitResult(this.outcome, [this.message]);
}

class ApiException implements Exception {
  final String message;
  final bool isOffline;
  const ApiException(this.message, {this.isOffline = false});
  @override
  String toString() => message;
}

class ApiClient {
  final Dio dio;
  String scenario;

  ApiClient({Dio? dio, String? scenario})
    : scenario = scenario ?? Config.scenario,
      dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: Config.baseUrl,
              connectTimeout: const Duration(seconds: 4),
              sendTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 4),
              validateStatus: (_) => true, // we handle status codes ourselves
            ),
          ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          o.headers['x-scenario'] = this.scenario;
          h.next(o);
        },
      ),
    );
  }

  Future<dynamic> _get(String path, {Map<String, dynamic>? query}) async {
    try {
      final r = await dio.get(path, queryParameters: query);
      final s = r.statusCode ?? 0;
      if (s >= 400) throw ApiException(_msg(r, 'Server error ($s)'));
      return r.data;
    } on DioException {
      throw const ApiException('You are offline', isOffline: true);
    }
  }

  String _msg(Response r, String fallback) =>
      (r.data is Map && r.data['message'] != null)
      ? r.data['message'].toString()
      : fallback;

  Future<dynamic> employee() => _get('/employee/me');
  Future<dynamic> attendance(String month) =>
      _get('/attendance', query: {'month': month});
  Future<dynamic> leaveBalance() => _get('/leave/balance');
  Future<dynamic> leaveRequests() => _get('/leave/requests');

  /// Leave submission needs connectivity. Server errors are shown to the user.
  Future<LeaveRequest> submitLeave({
    required String type,
    required String startDate,
    required String endDate,
    required String reason,
  }) async {
    try {
      final r = await dio.post(
        '/leave/requests',
        data: {
          'type': type,
          'startDate': startDate,
          'endDate': endDate,
          'reason': reason,
        },
      );
      final s = r.statusCode ?? 0;
      if (s == 201 || s == 200) return LeaveRequest.fromJson(r.data);
      throw ApiException(_msg(r, 'Could not submit leave ($s)'));
    } on DioException {
      throw const ApiException(
        'No connection. Leave needs internet to submit.',
        isOffline: true,
      );
    }
  }

  /// Attendance event submission.
  /// - 200/201  -> synced (200 = server already had this eventId: idempotent)
  /// - 4xx      -> rejected (permanent, do not retry)
  /// - 5xx / timeout / no network -> transient (outcome unknown, retry later
  ///   with the SAME eventId)
  Future<SubmitResult> submitEvent(AttendanceEvent e) async {
    try {
      final r = await dio.post('/attendance/events', data: e.toApiBody());
      final s = r.statusCode ?? 0;
      if (s == 200 || s == 201) return const SubmitResult(SubmitOutcome.synced);
      if (s >= 500) {
        return SubmitResult(SubmitOutcome.transient, 'Server error ($s)');
      }
      return SubmitResult(SubmitOutcome.rejected, _msg(r, 'Rejected ($s)'));
    } on DioException {
      return const SubmitResult(SubmitOutcome.transient, 'No response');
    }
  }
}
