// Riverpod application state providers.
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/db.dart';
import '../data/location_service.dart';
import '../data/repository.dart';
import '../domain/models.dart';
import '../domain/records.dart';
import '../sync/sync_engine.dart';

// Overridden in main() once the database is open (and in tests).
final dbProvider = Provider<AppDb>((ref) => throw UnimplementedError());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);

final repositoryProvider = Provider<Repository>(
  (ref) => Repository(
    api: ref.watch(apiClientProvider),
    db: ref.watch(dbProvider),
    location: ref.watch(locationServiceProvider),
  ),
);

final syncEngineProvider = Provider<SyncEngine>(
  (ref) =>
      SyncEngine(db: ref.watch(dbProvider), api: ref.watch(apiClientProvider)),
);

// Wrapped in a provider so widget tests can replace it with a fake stream.
final connectivityStreamProvider = Provider<Stream<List<ConnectivityResult>>>(
  (ref) => Connectivity().onConnectivityChanged,
);

// What the UI shows after a check-in/out tap.
class ActionResult {
  final String message;
  final bool isError;
  final bool needsSettings;
  const ActionResult(
    this.message, {
    this.isError = false,
    this.needsSettings = false,
  });
}

class DashboardNotifier extends AsyncNotifier<DashboardData> {
  @override
  Future<DashboardData> build() async {
    _watchConnectivity();
    final data = await ref.read(repositoryProvider).loadDashboard();
    // Events left over from a previous session: try to send them now.
    if (data.pendingCount > 0) Future.microtask(syncNow);
    return data;
  }

  void _watchConnectivity() {
    final sub = ref.read(connectivityStreamProvider).listen((results) async {
      if (results.every((r) => r == ConnectivityResult.none)) return;
      await Future.delayed(const Duration(seconds: 1)); // let network settle
      await syncNow();
    });
    ref.onDispose(sub.cancel);
  }

  /// Reload without flipping the screen back to a spinner.
  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(repositoryProvider).loadDashboard(),
    );
  }

  Future<SyncReport> syncNow() async {
    final report = await ref.read(syncEngineProvider).sync();
    await refresh();
    return report;
  }

  Future<ActionResult> act(EventType type) async {
    final repo = ref.read(repositoryProvider);
    try {
      await repo.record(type); // validate + GPS + save locally as Pending
    } on RuleViolation catch (e) {
      return ActionResult(e.message, isError: true);
    } on LocationException catch (e) {
      return ActionResult(
        e.message,
        isError: true,
        needsSettings: e.kind == LocationFailure.deniedForever,
      );
    }
    await refresh(); // show the Pending state immediately
    final report = await ref.read(syncEngineProvider).sync();
    await refresh();

    final label = type == EventType.checkIn ? 'Check-in' : 'Check-out';
    if (report.remaining > 0) {
      return ActionResult(
        '$label saved offline. It will sync when you are back online.',
      );
    }
    if (report.rejected > 0) {
      return ActionResult('$label was rejected by the server.', isError: true);
    }
    return ActionResult('$label successful.');
  }
}

final dashboardProvider =
    AsyncNotifierProvider<DashboardNotifier, DashboardData>(
      DashboardNotifier.new,
    );

class LeaveNotifier extends AsyncNotifier<LeaveData> {
  @override
  Future<LeaveData> build() => ref.read(repositoryProvider).loadLeave();

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(repositoryProvider).loadLeave(),
    );
  }

  Future<void> submit({
    required String type,
    required DateTime start,
    required DateTime end,
    required String reason,
  }) async {
    await ref
        .read(repositoryProvider)
        .submitLeave(type: type, start: start, end: end, reason: reason);
    await refresh();
  }
}

final leaveProvider = AsyncNotifierProvider<LeaveNotifier, LeaveData>(
  LeaveNotifier.new,
);
