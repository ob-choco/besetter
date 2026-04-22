import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../models/verified_completer.dart';
import '../../services/verified_completers_service.dart';
import '../common/user_avatar.dart';
import '../sheets/verified_completers_sheet.dart';

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
  static const double _avatarSize = 40;
  static const double _gap = 8;
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
    if (widget.totalCount <= 0) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${l10n.verifiedCompletersTitle} 🏅',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '· ${l10n.verifiedCompletersCount(widget.totalCount)}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const SizedBox(
              height: _avatarSize,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error != null)
            SizedBox(
              height: _avatarSize,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(l10n.failedToLoadData,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ),
            )
          else
            LayoutBuilder(builder: (ctx, constraints) {
              final width = constraints.maxWidth;
              final remainder = (widget.totalCount - _preview.length).clamp(0, 1 << 30);
              final needsChip = widget.totalCount > _preview.length || remainder > 0;
              final usable = needsChip ? (width - _chipReserve) : width;
              final maxFit = ((usable + _gap) / (_avatarSize + _gap)).floor();
              final showCount = maxFit.clamp(0, _preview.length);
              final overflow = widget.totalCount - showCount;
              return SizedBox(
                height: _avatarSize,
                child: Row(
                  children: [
                    for (var i = 0; i < showCount; i++) ...[
                      GestureDetector(
                        onTap: _openSheet,
                        child: UserAvatar(
                          owner: _preview[i].user,
                          size: _avatarSize,
                        ),
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
        ],
      ),
    );
  }
}
