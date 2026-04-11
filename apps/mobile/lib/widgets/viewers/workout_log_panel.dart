import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/activity_refresh_provider.dart';
import '../../services/activity_service.dart';

class WorkoutLogPanel extends StatefulWidget {
  final String routeId;

  const WorkoutLogPanel({
    required this.routeId,
    Key? key,
  }) : super(key: key);

  @override
  State<WorkoutLogPanel> createState() => _WorkoutLogPanelState();
}

class _WorkoutLogPanelState extends State<WorkoutLogPanel> {
  // Stats (loaded once)
  Map<String, dynamic>? _stats;
  bool _statsLoading = true;

  // Activities list
  List<Map<String, dynamic>> _activities = [];
  bool _activitiesLoading = true;
  String? _nextCursor;
  bool _loadingMore = false;

  // Filter
  bool _completedOnly = true;

  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadStats();
    _loadActivities();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 50 &&
        !_loadingMore &&
        _nextCursor != null) {
      _loadMoreActivities();
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await ActivityService.getMyStats(routeId: widget.routeId);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _statsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statsLoading = false;
      });
    }
  }

  Future<void> _loadActivities() async {
    setState(() {
      _activitiesLoading = true;
      _activities = [];
      _nextCursor = null;
    });

    try {
      final result = await ActivityService.getMyActivities(
        routeId: widget.routeId,
        status: _completedOnly ? 'completed' : null,
      );
      if (!mounted) return;
      setState(() {
        _activities = List<Map<String, dynamic>>.from(result['activities']);
        _nextCursor = result['nextCursor'] as String?;
        _activitiesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activitiesLoading = false;
      });
    }
  }

  Future<void> _loadMoreActivities() async {
    if (_loadingMore || _nextCursor == null) return;

    setState(() {
      _loadingMore = true;
    });

    try {
      final result = await ActivityService.getMyActivities(
        routeId: widget.routeId,
        status: _completedOnly ? 'completed' : null,
        cursor: _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        _activities.addAll(
          List<Map<String, dynamic>>.from(result['activities']),
        );
        _nextCursor = result['nextCursor'] as String?;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
      });
    }
  }

  void _toggleFilter() {
    setState(() {
      _completedOnly = !_completedOnly;
    });
    _loadActivities();
  }

  Future<void> _deleteActivity(String activityId) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.deleteActivityConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Find the activity before deleting so we can update stats locally
    final activity = _activities.firstWhere(
      (a) => a['id'] == activityId,
      orElse: () => <String, dynamic>{},
    );

    try {
      await ActivityService.deleteActivity(
        routeId: widget.routeId,
        activityId: activityId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.activityDeleted)),
      );

      final status = activity['status'] as String?;
      final duration = activity.containsKey('duration') ? (activity['duration'] as num).toDouble() : 0.0;
      final locationVerified = activity['locationVerified'] == true;

      setState(() {
        _activities.removeWhere((a) => a['id'] == activityId);

        if (_stats != null && status != null) {
          _stats!['totalCount'] = (_stats!['totalCount'] as num).toInt() - 1;
          _stats!['totalDuration'] = (_stats!['totalDuration'] as num).toDouble() - duration;
          if (status == 'completed') {
            _stats!['completedCount'] = (_stats!['completedCount'] as num).toInt() - 1;
            _stats!['completedDuration'] = (_stats!['completedDuration'] as num).toDouble() - duration;
            if (locationVerified) {
              _stats!['verifiedCompletedCount'] = (_stats!['verifiedCompletedCount'] as num).toInt() - 1;
              _stats!['verifiedCompletedDuration'] = (_stats!['verifiedCompletedDuration'] as num).toDouble() - duration;
            }
          }
        }
      });

      ProviderScope.containerOf(context).read(activityDirtyProvider.notifier).state = true;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedDeleteActivity)),
      );
    }
  }

  String _formatDuration(double durationSeconds) {
    final minutes = (durationSeconds / 60).floor().toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).floor().toString().padLeft(2, '0');
    final centiseconds = ((durationSeconds * 100) % 100).floor().toString().padLeft(2, '0');
    return '$minutes:$seconds.$centiseconds';
  }

  /// Group activities by date, returning a list of (dateLabel, activities) pairs.
  List<MapEntry<String, List<Map<String, dynamic>>>> _groupByDate() {
    final locale = AppLocalizations.of(context)!.localeName;
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final activity in _activities) {
      final startedAt = DateTime.parse(activity['startedAt'] as String);
      final dateKey = DateFormat.yMMMMd(locale).format(startedAt.toLocal()).toUpperCase();
      grouped.putIfAbsent(dateKey, () => []).add(activity);
    }

    return grouped.entries.toList();
  }

  /// Add a newly created activity to the local state without re-fetching.
  void addActivity(Map<String, dynamic> activityData) {
    if (!mounted) return;

    // Build list item from API response (ActivityResponse → ActivityListItem format)
    final listItem = {
      'id': activityData['_id'] as String,
      'status': activityData['status'] as String,
      'locationVerified': activityData['locationVerified'] as bool,
      'startedAt': activityData['startedAt'] as String,
      'endedAt': activityData['endedAt'] as String,
      'duration': activityData['duration'],
      'createdAt': activityData['createdAt'] as String,
    };

    final status = activityData['status'] as String;
    final locationVerified = activityData['locationVerified'] as bool;
    final duration = (activityData['duration'] as num).toDouble();

    setState(() {
      // Insert at the beginning (newest first) if it matches the filter
      if (!_completedOnly || status == 'completed') {
        _activities.insert(0, listItem);
      }

      // Update stats locally
      if (_stats != null) {
        _stats!['totalCount'] = (_stats!['totalCount'] as num).toInt() + 1;
        _stats!['totalDuration'] = (_stats!['totalDuration'] as num).toDouble() + duration;
        if (status == 'completed') {
          _stats!['completedCount'] = (_stats!['completedCount'] as num).toInt() + 1;
          _stats!['completedDuration'] = (_stats!['completedDuration'] as num).toDouble() + duration;
          if (locationVerified) {
            _stats!['verifiedCompletedCount'] = (_stats!['verifiedCompletedCount'] as num).toInt() + 1;
            _stats!['verifiedCompletedDuration'] = (_stats!['verifiedCompletedDuration'] as num).toDouble() + duration;
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_statsLoading) return const SizedBox.shrink();
    if (_stats != null && (_stats!['totalCount'] as int) == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6E8EA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(l10n),
            if (_activitiesLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_activities.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    l10n.noWorkoutRecords,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF595C5D),
                    ),
                  ),
                ),
              )
            else
              _buildActivityList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    // Select stats based on filter
    int count = 0;
    double duration = 0;
    if (_stats != null) {
      if (_completedOnly) {
        count = (_stats!['completedCount'] as num).toInt();
        duration = (_stats!['completedDuration'] as num).toDouble();
      } else {
        count = (_stats!['totalCount'] as num).toInt();
        duration = (_stats!['totalDuration'] as num).toDouble();
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.workoutLog,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF595C5D),
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _toggleFilter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _completedOnly
                        ? const Color(0xFF0066FF)
                        : const Color(0xFFE6E8EA),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.completedOnly,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _completedOnly ? Colors.white : const Color(0xFF595C5D),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.totalSessionsCount(count)} | ${l10n.avgDurationLabel(_formatDuration(count > 0 ? duration / count : 0))}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF595C5D),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityList() {
    final groups = _groupByDate();

    // Build flat list of widgets for the scrollable area
    final List<Widget> items = [];
    for (final group in groups) {
      // Date header
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            group.key,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF22C55E),
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
      // Activity rows
      for (final activity in group.value) {
        items.add(_buildActivityRow(activity));
      }
    }

    // Loading indicator at bottom
    if (_loadingMore) {
      items.add(
        const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    // 1-3 items: no fixed height (fit content), 4+: 3.5 items visible with scroll
    const itemHeight = 44.0; // single-line row (~12 vertical padding + content)
    const dateHeaderHeight = 28.0;

    if (_activities.length <= 3) {
      return Column(children: items);
    }

    // Calculate height for 3.5 items visible
    final scrollHeight = (itemHeight * 3.5) + dateHeaderHeight;
    return SizedBox(
      height: scrollHeight,
      child: ListView(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        children: items,
      ),
    );
  }

  Widget _buildActivityRow(Map<String, dynamic> activity) {
    final startedAt = DateTime.parse(activity['startedAt'] as String).toLocal();
    final timeStr = DateFormat.Hm().format(startedAt);
    final duration = (activity['duration'] as num).toDouble();
    final isCompleted = activity['status'] == 'completed';
    final isVerified = activity['locationVerified'] == true;
    final activityId = activity['id'] as String;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time + duration
          Expanded(
            child: Row(
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2C2F30),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(duration),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF595C5D),
                  ),
                ),
                if (isVerified && isCompleted) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 12,
                          color: Color(0xFF22C55E),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          l10n.onSite,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Completed label
          if (isCompleted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0066FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l10n.completed,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0066FF),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Delete button
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: GestureDetector(
              onTap: () => _deleteActivity(activityId),
              child: const Icon(
                Icons.delete_outline,
                size: 20,
                color: Color(0xFF595C5D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
