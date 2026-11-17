// Data synchronization engine.
import '../data/api_client.dart';
import '../data/db.dart';
import '../domain/models.dart';

class SyncReport {
  final int synced;
  final int rejected;
  final int remaining; // still pending (e.g. offline or timeout)
  final bool interrupted;
  const SyncReport({
    this.synced = 0,
    this.rejected = 0,
    this.remaining = 0,
    this.interrupted = false,
  });
}

/// Sends pending events to the server strictly in order (by local seq).
///
/// Identity / idempotency: every event has a client-generated UUID (eventId)
/// created at tap time and reused on every retry. The server stores the id
/// and returns the original result for a repeated id, so a retry after a
/// timeout can never create a second record.
///
/// Outcomes:
///  - synced    -> mark Synced, continue with the next event
///  - rejected  -> mark Rejected with the reason, continue (never retried)
///  - transient -> (timeout / 5xx / offline) STOP. The event stays Pending,
///                 so later events are never sent before earlier ones.
class SyncEngine {
  final AppDb db;
  final ApiClient api;
  bool _running = false;

  SyncEngine({required this.db, required this.api});

  bool get isRunning => _running;

  Future<SyncReport> sync() async {
    if (_running) return const SyncReport(); // no overlapping runs
    _running = true;
    var synced = 0, rejected = 0, interrupted = false;
    try {
      while (!interrupted) {
        final pending = await db.pendingEvents(); // ordered by seq
        if (pending.isEmpty) break;
        for (final e in pending) {
          final r = await api.submitEvent(e);
          if (r.outcome == SubmitOutcome.synced) {
            await db.setStatus(e.eventId, SyncStatus.synced);
            synced++;
          } else if (r.outcome == SubmitOutcome.rejected) {
            await db.setStatus(
              e.eventId,
              SyncStatus.rejected,
              reason: r.message,
            );
            rejected++;
          } else {
            interrupted = true; // keep order: do not skip ahead
            break;
          }
        }
      }
      final remaining = (await db.pendingEvents()).length;
      return SyncReport(
        synced: synced,
        rejected: rejected,
        remaining: remaining,
        interrupted: interrupted,
      );
    } finally {
      _running = false;
    }
  }
}
