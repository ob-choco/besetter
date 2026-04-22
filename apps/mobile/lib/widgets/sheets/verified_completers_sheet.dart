import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../models/verified_completer.dart';
import '../../services/verified_completers_service.dart';
import '../common/user_avatar.dart';

class VerifiedCompletersSheet extends StatefulWidget {
  final String routeId;
  final int totalCount;

  const VerifiedCompletersSheet({
    super.key,
    required this.routeId,
    required this.totalCount,
  });

  static Future<void> show(
    BuildContext context, {
    required String routeId,
    required int totalCount,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => VerifiedCompletersSheet(
        routeId: routeId,
        totalCount: totalCount,
      ),
    );
  }

  @override
  State<VerifiedCompletersSheet> createState() =>
      _VerifiedCompletersSheetState();
}

class _VerifiedCompletersSheetState extends State<VerifiedCompletersSheet> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  final List<VerifiedCompleter> _items = [];

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _cursor;
  Object? _initialError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    try {
      final page = await VerifiedCompletersService.fetch(
        routeId: widget.routeId,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.nextToken;
        _hasMore = page.nextToken != null;
        _initialLoading = false;
      });
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
    setState(() => _loadingMore = true);
    try {
      final page = await VerifiedCompletersService.fetch(
        routeId: widget.routeId,
        limit: _pageSize,
        cursor: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextToken;
        _hasMore = page.nextToken != null;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mediaHeight = MediaQuery.of(context).size.height;

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.verifiedCompletersTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  l10n.verifiedCompletersCount(widget.totalCount),
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(child: _buildBody(l10n, mediaHeight)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, double _) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_initialError != null) {
      return Center(child: Text(l10n.failedToLoadData));
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      itemBuilder: (ctx, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final item = _items[index];
        return _Row(item: item);
      },
    );
  }
}

class _Row extends StatelessWidget {
  final VerifiedCompleter item;
  const _Row({required this.item});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final handle = item.user.isDeleted
        ? l10n.deletedUser
        : (item.user.profileId != null ? '@${item.user.profileId}' : '');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          UserAvatar(owner: item.user, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              handle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: item.user.isDeleted ? Colors.grey[500] : Colors.black87,
                fontStyle:
                    item.user.isDeleted ? FontStyle.italic : FontStyle.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x33F97316)),
            ),
            child: Text(
              '${item.verifiedCompletedCount}',
              style: const TextStyle(
                color: Color(0xFFF97316),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
