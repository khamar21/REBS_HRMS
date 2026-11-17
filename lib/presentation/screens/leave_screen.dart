// Leave screen.
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../../domain/records.dart';
import '../providers.dart';

class LeaveScreen extends ConsumerStatefulWidget {
  const LeaveScreen({super.key});

  @override
  ConsumerState<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends ConsumerState<LeaveScreen> {
  final _reasonController = TextEditingController();
  String _type = 'casual';
  DateTime? _start;
  DateTime? _end;
  bool _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  DateTime _today() {
    final repository = ref.read(repositoryProvider);
    return DateTime.parse(repository.clock.today());
  }

  int get _daysRequested {
    if (_start == null || _end == null || _end!.isBefore(_start!)) return 0;
    return _end!.difference(_start!).inDays + 1;
  }

  Future<void> _pickDate({required bool start}) async {
    final today = _today();
    final initial = start ? (_start ?? today) : (_end ?? _start ?? today);
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 2, 12, 31),
      initialDate: initial.isBefore(today) ? today : initial,
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit(LeaveData data, bool connected) async {
    if (!connected) {
      _showMessage(
        'Connect to the internet before submitting leave.',
        error: true,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(leaveProvider.notifier)
          .submit(
            type: _type,
            start: _start!,
            end: _end!,
            reason: _reasonController.text,
          );
      if (!mounted) return;
      _reasonController.clear();
      setState(() {
        _start = null;
        _end = null;
      });
      _showMessage('Leave request submitted.');
    } on RuleViolation catch (e) {
      _showMessage(e.message, error: true);
    } on ApiException catch (e) {
      _showMessage(e.message, error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? AppColors.danger : AppColors.ink,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(leaveProvider);
    return StreamBuilder<List<ConnectivityResult>>(
      stream: ref.watch(connectivityStreamProvider),
      builder: (context, snapshot) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Leave workspace'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => ref.read(leaveProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorView(
              message: error.toString(),
              onRetry: () => ref.invalidate(leaveProvider),
            ),
            data: (data) {
              final connected =
                  snapshot.data?.any(
                    (result) => result != ConnectivityResult.none,
                  ) ??
                  !data.offline;
              return _content(data, connected);
            },
          ),
        );
      },
    );
  }

  Widget _content(LeaveData data, bool connected) {
    final offline = !connected;
    return RefreshIndicator(
      onRefresh: () => ref.read(leaveProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _LeaveHeader(requestCount: data.requests.length, offline: offline),
          const SizedBox(height: 16),
          if (offline) const _OfflineBanner(),
          _form(data, offline, connected),
          const SizedBox(height: 24),
          const Text(
            'Your requests',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          Text(
            'Track your time-off history',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          if (data.requests.isEmpty)
            const AppCard(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No leave requests yet',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              ),
            )
          else
            ...data.requests.map(_requestTile),
        ],
      ),
    );
  }

  Widget _form(LeaveData data, bool offline, bool connected) {
    final available = data.balance[_type] ?? 0;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Apply for leave',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tell us when you need time away.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.edit_calendar_rounded,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Leave type',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .3,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
               ButtonSegment(
                value: 'casual',
                icon: Icon(Icons.beach_access_outlined),
                label: Text('Casual'),
              ),
              ButtonSegment(
                value: 'sick',
                icon: Icon(Icons.health_and_safety_outlined),
                label: Text('Sick'),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (value) => setState(() => _type = value.first),
          ),
          const SizedBox(height: 20),
          const Text(
            'When do you need leave?',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DateButton(
                  label: 'Start date',
                  value: _start,
                  onPressed: () => _pickDate(start: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateButton(
                  label: 'End date',
                  value: _end,
                  onPressed: () => _pickDate(start: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, height: 1.45),
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => Text(
                  '$currentLength characters',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: currentLength >= 10
                        ? AppColors.success
                        : AppColors.muted,
                  ),
                ),
            decoration: const InputDecoration(
              labelText: 'Reason for leave',
              hintText: 'Share a little context with your manager...',
              prefixIcon: Padding(
                padding: EdgeInsets.only(left: 14, right: 10, top: 14),
                child: Icon(Icons.notes_rounded, color: AppColors.primary),
              ),
              prefixIconConstraints: BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: .1),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '$_daysRequested day${_daysRequested == 1 ? '' : 's'} requested',
                ),
                const Spacer(),
                Text(
                  '$available $_type days left',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitting || offline || _start == null || _end == null
                ? null
                : () => _submit(data, connected),
            icon: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              _submitting
                  ? 'Submitting...'
                  : offline
                  ? 'Connect to submit'
                  : 'Submit request',
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestTile(LeaveRequest request) {
    final dates =
        '${_formatDate(request.startDate)} - ${_formatDate(request.endDate)}';
    final status = request.status.toLowerCase();
    final color = switch (status) {
      'approved' => AppColors.success,
      'rejected' => AppColors.danger,
      _ => AppColors.warning,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: color.withValues(alpha: .12),
                  child: Icon(Icons.beach_access_rounded, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${_title(request.type)} leave',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(label: _title(status), color: color),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              dates,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              request.reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String value) {
    final date = DateTime.parse(value);
    return DateFormat('d MMM yyyy').format(date);
  }

  String _title(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}

class _DateButton extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onPressed;

  const _DateButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Select'
        : DateFormat('d MMM yyyy').format(value!);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              size: 21,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: value == null ? AppColors.muted : AppColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}

class _LeaveHeader extends StatelessWidget {
  final int requestCount;
  final bool offline;

  const _LeaveHeader({required this.requestCount, required this.offline});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: .18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.beach_access_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Plan your time off',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  offline
                      ? 'Saved requests are available offline'
                      : '$requestCount request${requestCount == 1 ? '' : 's'} on record',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.warning.withValues(alpha: .22)),
    ),
    child: const Row(
      children: [
        Icon(Icons.cloud_off_rounded, color: AppColors.warning),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Offline: saved requests are viewable, but submission is disabled.',
          ),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: AppColors.danger,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
