import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/notification_data.dart';
import '../providers/user_provider.dart';
import '../services/notification_service.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  final List<NotificationData> _items = [];
  late final DateTime _enteredAt;

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  DateTime? _cursor;
  Object? _initialError;
  Object? _loadMoreError;

  @override
  void initState() {
    super.initState();
    _enteredAt = DateTime.now().toUtc();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _initialError = null;
    });
    try {
      final result = await NotificationService.list(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _cursor = result.nextCursor;
        _hasMore = result.nextCursor != null;
        _initialLoading = false;
      });
      _markReadAfterLoad();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _initialError = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final result = await NotificationService.list(
        before: _cursor,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _cursor = result.nextCursor;
        _hasMore = result.nextCursor != null;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = e;
      });
    }
  }

  Future<void> _markReadAfterLoad() async {
    // Only call mark-read if the newest notification is still unread.
    if (_items.isEmpty || _items.first.readAt != null) return;
    try {
      await NotificationService.markRead(_enteredAt);
      if (!mounted) return;
      // Refresh /users/me so GNB badge and MY header badge clear immediately.
      ref.invalidate(userProfileProvider);
    } catch (_) {
      // silent — next entry will retry
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  String _relativeTime(DateTime createdAt) {
    final now = DateTime.now();
    final diff = now.difference(createdAt.toLocal());
    if (diff.inSeconds < 60) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    final local = createdAt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y.$m.$d';
  }

  bool _isUnreadAfterEntry(NotificationData n) {
    // Items that arrived after we entered the page stay visually "unread".
    return n.readAt == null && n.createdAt.toUtc().isAfter(_enteredAt);
  }

  Widget _buildItem(NotificationData n) {
    final unread = _isUnreadAfterEntry(n);
    return Container(
      color: unread
          ? Theme.of(context).colorScheme.primary.withOpacity(0.06)
          : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.edit_note_outlined, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (unread)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        n.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  n.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _relativeTime(n.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_initialError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('알림을 불러오지 못했어요.'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadInitial,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('아직 받은 알림이 없어요'));
    }
    return ListView.separated(
      controller: _scrollController,
      itemCount: _items.length + (_hasMore || _loadMoreError != null ? 1 : 0),
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: Theme.of(context).dividerColor.withOpacity(0.5),
      ),
      itemBuilder: (context, index) {
        if (index < _items.length) {
          return _buildItem(_items[index]);
        }
        if (_loadMoreError != null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: TextButton(
                onPressed: _loadMore,
                child: const Text('다시 시도'),
              ),
            ),
          );
        }
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('알림')),
      body: _buildBody(),
    );
  }
}
