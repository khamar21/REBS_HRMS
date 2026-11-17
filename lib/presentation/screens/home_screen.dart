// Home screen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../domain/attendance_rules.dart';
import '../../domain/models.dart';
import '../../domain/records.dart';
import '../providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _busy = false;
  bool _syncing = false;

  void _snack(String msg, {bool error = false, bool settings = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? AppColors.danger : AppColors.ink,
          action: settings
              ? SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: () =>
                      ref.read(locationServiceProvider).openSettings(),
                )
              : null,
        ),
      );
  }

  Future<void> _act(EventType t) async {
    setState(() => _busy = true);
    final r = await ref.read(dashboardProvider.notifier).act(t);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(r.message, error: r.isError, settings: r.needsSettings);
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final r = await ref.read(dashboardProvider.notifier).syncNow();
    if (!mounted) return;
    setState(() => _syncing = false);
    if (r.remaining > 0) {
      _snack('Could not sync yet. ${r.remaining} still pending.', error: true);
    } else if (r.synced + r.rejected == 0) {
      _snack('Nothing to sync.');
    } else {
      _snack('Synced ${r.synced}, rejected ${r.rejected}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dashboardProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(dashboardProvider),
          ),
          data: _content,
        ),
      ),
    );
  }

  Widget _content(DashboardData d) {
    final clock = ref.read(repositoryProvider).clock;
    String t(DateTime? x) => x == null ? '--:--' : clock.timeOf(x);
    final dateLabel = DateFormat('EEEE, d MMMM')
        .format(DateTime.parse(clock.today()));

    return RefreshIndicator(
      onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _Header(
            employee: d.employee,
            dateLabel: dateLabel,
            syncing: _syncing,
            onSync: _syncNow,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.offline)
                  const _Banner(
                    icon: Icons.cloud_off_rounded,
                    text: "You're offline. Showing saved data.",
                    color: AppColors.warning,
                  ),
                if (d.pendingCount > 0)
                  _Banner(
                    icon: Icons.sync_problem_rounded,
                    text:
                        '${d.pendingCount} action${d.pendingCount == 1 ? '' : 's'} waiting to sync',
                    color: AppColors.primary,
                    actionLabel: 'Sync Now',
                    onAction: _syncing ? null : _syncNow,
                  ),
                _todayCard(d, t),
                const SizedBox(height: 16),
                _balanceCard(d),
                const SizedBox(height: 24),
                const Text(
                  'Recent attendance',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _recentCard(d, t),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _todayCard(DashboardData d, String Function(DateTime?) t) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.access_time_filled_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Today',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2,
                ),
              ),
              const Spacer(),
              StatusChip(
                label: _dayLabel(d.status),
                color: _dayColor(d.status),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _Stat(label: 'Check-in', value: t(d.checkIn)),
              _Stat(label: 'Check-out', value: t(d.checkOut)),
              _Elapsed(start: d.checkIn, end: d.checkOut),
            ],
          ),
          const SizedBox(height: 20),
          _actionButton(d.status),
        ],
      ),
    );
  }

  Widget _actionButton(DayStatus s) {
    if (_busy) {
      return const FilledButton(
        onPressed: null,
        child: SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    switch (s) {
      case DayStatus.notCheckedIn:
        return FilledButton.icon(
          onPressed: () => _act(EventType.checkIn),
          icon: const Icon(Icons.login_rounded),
          label: const Text('Check In'),
        );
      case DayStatus.checkedIn:
        return FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => _act(EventType.checkOut),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Check Out'),
        );
      case DayStatus.checkedOut:
        return const FilledButton(
          onPressed: null,
          child: Text('Done for today'),
        );
    }
  }

  Widget _balanceCard(DashboardData d) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Leave balance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _BalanceTile(
                label: 'Casual',
                days: d.balance['casual'] ?? 0,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              _BalanceTile(
                label: 'Sick',
                days: d.balance['sick'] ?? 0,
                color: AppColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recentCard(DashboardData d, String Function(DateTime?) t) {
    final items = d.recent;
    if (items.isEmpty) {
      return const AppCard(
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(
                  Icons.event_busy_rounded,
                  size: 40,
                  color: AppColors.muted,
                ),
                SizedBox(height: 8),
                Text(
                  'No attendance records yet',
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _RecordTile(
              record: items[i],
              inText: t(items[i].checkIn),
              outText: t(items[i].checkOut),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- small helpers
String _dayLabel(DayStatus s) {
  switch (s) {
    case DayStatus.notCheckedIn:
      return 'Not Checked In';
    case DayStatus.checkedIn:
      return 'Checked In';
    case DayStatus.checkedOut:
      return 'Checked Out';
  }
}

Color _dayColor(DayStatus s) {
  switch (s) {
    case DayStatus.notCheckedIn:
      return AppColors.muted;
    case DayStatus.checkedIn:
      return AppColors.success;
    case DayStatus.checkedOut:
      return AppColors.primary;
  }
}

String _syncLabel(SyncStatus s) {
  switch (s) {
    case SyncStatus.pending:
      return 'Pending Sync';
    case SyncStatus.synced:
      return 'Synced';
    case SyncStatus.rejected:
      return 'Rejected';
  }
}

Color _syncColor(SyncStatus s) {
  switch (s) {
    case SyncStatus.pending:
      return AppColors.warning;
    case SyncStatus.synced:
      return AppColors.success;
    case SyncStatus.rejected:
      return AppColors.danger;
  }
}

// ------------------------------------------------------------------ widgets
class _Header extends StatelessWidget {
  final Employee employee;
  final String dateLabel;
  final bool syncing;
  final VoidCallback onSync;
  const _Header({
    required this.employee,
    required this.dateLabel,
    required this.syncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 12,
        12,
        28,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white24,
                child: Text(
                  employee.name.isEmpty ? '?' : employee.name[0],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, ${employee.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${employee.id}  •  ${employee.department}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sync Now',
                onPressed: syncing ? null : onSync,
                icon: syncing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            dateLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _Banner({
    required this.icon,
    required this.text,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Working duration; refreshes every 30 s while checked in.
class _Elapsed extends StatefulWidget {
  final DateTime? start, end;
  const _Elapsed({required this.start, required this.end});
  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.start;
    String text = '--';
    if (s != null) {
      final d = (widget.end ?? DateTime.now().toUtc()).difference(s);
      text = '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
    }
    return _Stat(label: 'Duration', value: text);
  }
}

class _BalanceTile extends StatelessWidget {
  final String label;
  final int days;
  final Color color;
  const _BalanceTile({
    required this.label,
    required this.days,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$days',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text('$label days', style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final DayRecord record;
  final String inText, outText;
  const _RecordTile({
    required this.record,
    required this.inText,
    required this.outText,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('EEE, d MMM').format(DateTime.parse(record.date));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'In $inText   •   Out $outText',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: _syncLabel(record.status),
                color: _syncColor(record.status),
              ),
            ],
          ),
          if (record.status == SyncStatus.rejected && record.reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                record.reason!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: AppColors.muted,
            ),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
