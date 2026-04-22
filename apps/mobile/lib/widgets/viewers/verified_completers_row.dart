import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../models/verified_completer.dart';
import '../../services/verified_completers_service.dart';
import '../../models/route_data.dart';
import '../common/user_avatar.dart';
import '../sheets/verified_completers_sheet.dart';
import 'section_header.dart';

class VerifiedCompletersRow extends StatefulWidget {
  final String routeId;
  final int totalCount;

  const VerifiedCompletersRow({
    super.key,
    required this.routeId,
    required this.totalCount,
  });

  @override
  State<VerifiedCompletersRow> createState() => _VerifiedCompletersRowState();
}

class _VerifiedCompletersRowState extends State<VerifiedCompletersRow> {
  static const double _avatarSize = 48;
  static const double _itemWidth = 64;
  static const double _itemHeight = 96;
  static const double _gap = 12;
  static const double _chipReserve = 96;
  static const int _previewLimit = 10;

  List<VerifiedCompleter> _preview = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.totalCount > 0) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final page = await VerifiedCompletersService.fetch(
        routeId: widget.routeId,
        limit: _previewLimit,
      );
      if (!mounted) return;
      setState(() {
        _preview = page.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _openSheet() {
    VerifiedCompletersSheet.show(
      context,
      routeId: widget.routeId,
      totalCount: widget.totalCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEmpty = widget.totalCount <= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.verifiedCompletersTitle,
          meta: l10n.verifiedCompletersCount(widget.totalCount),
        ),
        if (isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: SizedBox(
              height: _itemHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.verifiedCompletersEmpty,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.verifiedCompletersEmptyCta,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (_loading)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: SizedBox(
              height: _itemHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: SizedBox(
              height: _itemHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.failedToLoadData,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: LayoutBuilder(builder: (ctx, constraints) {
              final width = constraints.maxWidth;
              final needsChip = widget.totalCount > _preview.length;
              final usable = needsChip ? (width - _chipReserve) : width;
              final maxFit = ((usable + _gap) / (_itemWidth + _gap)).floor();
              final showCount = maxFit.clamp(0, _preview.length);
              final overflow = widget.totalCount - showCount;
              return SizedBox(
                height: _itemHeight,
                child: Row(
                  children: [
                    for (var i = 0; i < showCount; i++) ...[
                      _AvatarWithHandle(
                        user: _preview[i].user,
                        count: _preview[i].verifiedCompletedCount,
                        onTap: _openSheet,
                        deletedLabel: l10n.deletedUser,
                      ),
                      if (i != showCount - 1) const SizedBox(width: _gap),
                    ],
                    if (overflow > 0) ...[
                      const SizedBox(width: _gap),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: InkWell(
                            onTap: _openSheet,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F5),
                                border:
                                    Border.all(color: const Color(0xFFE0E0E0)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                l10n.verifiedCompletersMore(overflow),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ),
      ],
    );
  }
}

class _AvatarWithHandle extends StatelessWidget {
  final OwnerInfo user;
  final int count;
  final VoidCallback onTap;
  final String deletedLabel;

  const _AvatarWithHandle({
    required this.user,
    required this.count,
    required this.onTap,
    required this.deletedLabel,
  });

  @override
  Widget build(BuildContext context) {
    final label = user.isDeleted
        ? deletedLabel
        : (user.profileId ?? '');
    const avatarSize = _VerifiedCompletersRowState._avatarSize;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: _VerifiedCompletersRowState._itemWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: avatarSize,
              height: avatarSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(owner: user, size: avatarSize),
                  Positioned(
                    top: -4,
                    right: -6,
                    child: _CountBadge(count: count),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w500,
                color: user.isDeleted ? Colors.grey[500] : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFF97316),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 10,
          height: 1.1,
        ),
      ),
    );
  }
}
