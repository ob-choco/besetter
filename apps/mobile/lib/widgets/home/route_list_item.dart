import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/route_data.dart';
import '../../providers/routes_provider.dart';
import '../../services/http_client.dart';
import '../../pages/viewers/route_viewer.dart';
import '../../pages/editors/route_editor_page.dart';

class RouteListItem extends ConsumerStatefulWidget {
  final RouteData route;

  const RouteListItem({super.key, required this.route});

  @override
  ConsumerState<RouteListItem> createState() => _RouteListItemState();
}

class _RouteListItemState extends ConsumerState<RouteListItem> {
  bool _isLoading = false;

  Future<void> _openViewer() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final response = await AuthorizedHttpClient.get('/routes/${widget.route.id}');
      if (response.statusCode == 200) {
        final routeData = RouteData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RouteViewer(routeData: routeData)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleShare() {
    const baseUrl = 'https://besetter-api-371038003203.asia-northeast3.run.app';
    Share.share('$baseUrl/share/routes/${widget.route.id}');
  }

  Future<void> _handleEdit() async {
    setState(() => _isLoading = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RouteEditorPage(
            routeId: widget.route.id,
            editType: EditType.edit,
            initialMode: widget.route.type == RouteType.bouldering
                ? RouteEditModeType.bouldering
                : RouteEditModeType.endurance,
          ),
        ),
      );
      ref.invalidate(routesProvider());
      ref.invalidate(routesTotalCountProvider);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteRoute),
        content: Text(l10n.confirmDeleteRoute),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      final success = await ref.read(routesProvider().notifier).deleteRoute(widget.route.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? l10n.routeDeleted : l10n.failedDeleteRoute)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final route = widget.route;
    final imageUrl = route.overlayImageUrl ?? route.imageUrl;
    final gradeColor = route.gradeColor != null
        ? Color(int.parse(route.gradeColor!.replaceFirst('#', ''), radix: 16))
        : const Color(0xFF1E4BD8);

    final typeLabel = route.type == RouteType.bouldering ? l10n.bouldering : l10n.endurance;
    final completed = route.completedCount ?? 0;
    final attempts = route.attemptedCount ?? 0;
    final lastAt = route.lastActivityAt ?? route.createdAt;

    final placeText = [route.place?.name, route.wallName].whereType<String>().join(' · ');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
      onTap: _openViewer,
      child: LayoutBuilder(builder: (context, constraints) {
        final thumbSize = constraints.maxWidth / 2.618;
        return Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            child: IntrinsicHeight(
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: thumbSize,
                    height: thumbSize,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: Colors.grey[200]),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.broken_image, size: 28),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: gradeColor,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              route.grade,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 56),
                          child: Text(
                            '${typeLabel.toUpperCase()} · ${route.gradeType}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: Colors.grey[500],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          route.title ?? route.grade,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            height: 1.2,
                            color: Color(0xFF0F1A2E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (placeText.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.place_outlined, size: 13, color: Colors.grey[500]),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  placeText,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Spacer(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 16,
                              color: completed > 0 ? const Color(0xFF1EB980) : Colors.grey[400],
                            ),
                            const SizedBox(width: 5),
                            Text(
                              l10n.routeCardCompleted(completed),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: completed > 0 ? const Color(0xFF0F1A2E) : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              l10n.routeCardAttempts(attempts),
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Spacer(),
                            Text(
                              timeago.format(lastAt),
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _handleShare,
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.share_outlined, size: 18, color: Colors.grey[600]),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[600]),
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  splashRadius: 18,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        const Icon(Icons.edit_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(l10n.doEdit),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(l10n.delete, style: const TextStyle(color: Colors.red)),
                      ]),
                    ),
                  ],
                  onSelected: (v) {
                    if (v == 'edit') _handleEdit();
                    if (v == 'delete') _handleDelete();
                  },
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      );
      }),
      ),
    );
  }
}
