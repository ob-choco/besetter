import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/route_data.dart';
import '../../services/http_client.dart';
import '../../providers/routes_provider.dart';
import '../../pages/viewers/route_viewer.dart';
import '../../pages/editors/route_editor_page.dart';

class RouteCard extends ConsumerStatefulWidget {
  final RouteData route;
  final VoidCallback? onInteraction;

  const RouteCard({
    super.key,
    required this.route,
    this.onInteraction,
  });

  @override
  ConsumerState<RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends ConsumerState<RouteCard> {
  bool _isLoading = false;

  void _setLoading(bool value) {
    if (mounted) setState(() => _isLoading = value);
  }

  Future<void> _navigateToViewer() async {
    widget.onInteraction?.call();
    _setLoading(true);
    try {
      final response = await AuthorizedHttpClient.get('/routes/${widget.route.id}');
      if (response.statusCode == 200) {
        final routeData = RouteData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => RouteViewer(routeData: routeData)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _handleEdit() async {
    _setLoading(true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RouteEditorPage(
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteRoute),
        content: Text(AppLocalizations.of(context)!.confirmDeleteRoute),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _setLoading(true);
    try {
      final success = await ref.read(routesProvider().notifier).deleteRoute(widget.route.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success
            ? AppLocalizations.of(context)!.routeDeleted
            : AppLocalizations.of(context)!.failedDeleteRoute)),
      );
    } finally {
      _setLoading(false);
    }
  }

  void _handleShare() {
    const baseUrl = 'https://api.besetter.olivebagel.com';
    final shareUrl = '$baseUrl/share/routes/${widget.route.id}';
    Share.share(shareUrl);
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final imageUrl = route.overlayImageUrl ?? route.imageUrl;
    final gradeColor = route.gradeColor != null
        ? Color(int.parse(route.gradeColor!.replaceFirst('#', ''), radix: 16))
        : Colors.blue;

    return GestureDetector(
      onTap: _navigateToViewer,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 오버레이 이미지
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 342 / 427.5,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: Colors.grey[300]),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.broken_image, size: 48),
                          ),
                        ),
                      ),
                      // 난이도 뱃지
                      Positioned(
                        top: 18,
                        left: 24,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5.5),
                          decoration: BoxDecoration(
                            color: gradeColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            route.grade,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      // 오버레이 처리 중 라벨
                      if (route.overlayProcessing)
                        Positioned(
                          top: 18,
                          right: 24,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '이미지 생성 중',
                                  style: TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // 하단 정보
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 0, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 제목
                          Text(
                            route.title ?? route.grade,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // 위치 정보
                          if (route.place?.name != null || route.wallName != null)
                            Text(
                              [route.place?.name, route.wallName].whereType<String>().join(' \u2022 '),
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 2),
                          // 상대 시간
                          Text(
                            timeago.format(route.createdAt),
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                    // 공유 + 더보기 버튼
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.share_outlined, size: 20),
                          onPressed: _handleShare,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz, size: 20),
                          padding: EdgeInsets.zero,
                          itemBuilder: (context) => [
                            PopupMenuItem<String>(
                              value: 'edit',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit, size: 18),
                                  const SizedBox(width: 8),
                                  Text(AppLocalizations.of(context)!.doEdit),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete, size: 18),
                                  const SizedBox(width: 8),
                                  Text(AppLocalizations.of(context)!.doDelete),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'edit') _handleEdit();
                            if (value == 'delete') _handleDelete();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 로딩 오버레이
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black38,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
