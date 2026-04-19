import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../models/route_data.dart';
import '../../pages/viewers/route_viewer.dart';
import '../../providers/user_provider.dart';
import '../../services/http_client.dart';
import '../common/owner_badge.dart';

class RecentClimbedRouteCard extends ConsumerStatefulWidget {
  final RouteData route;

  const RecentClimbedRouteCard({super.key, required this.route});

  @override
  ConsumerState<RecentClimbedRouteCard> createState() =>
      _RecentClimbedRouteCardState();
}

class _RecentClimbedRouteCardState
    extends ConsumerState<RecentClimbedRouteCard> {
  bool _isLoading = false;

  bool get _isBlocked {
    final route = widget.route;
    if (route.isDeleted) return true;
    final myId = ref.read(userProfileProvider).valueOrNull?.id;
    if (route.visibility == 'private' &&
        route.owner != null &&
        route.owner!.userId != myId) {
      return true;
    }
    return false;
  }

  Future<void> _onTap() async {
    if (_isLoading) return;
    final l10n = AppLocalizations.of(context)!;

    if (widget.route.isDeleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.routeDeletedSnack)),
      );
      return;
    }
    if (_isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.routePrivateSnack)),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response =
          await AuthorizedHttpClient.get('/routes/${widget.route.id}');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final routeData =
            RouteData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RouteViewer(routeData: routeData)),
        );
        return;
      }
      if (response.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.routePrivateSnack)),
        );
        return;
      }
      if (response.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.routeDeletedSnack)),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.routeUnavailableSnack)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedLoadData)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleShare() {
    const baseUrl = 'https://besetter-api-371038003203.asia-northeast3.run.app';
    Share.share('$baseUrl/share/routes/${widget.route.id}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final route = widget.route;
    final imageUrl = route.overlayImageUrl ?? route.imageUrl;
    final gradeColor = route.gradeColor != null
        ? Color(int.parse(route.gradeColor!.replaceFirst('#', ''), radix: 16))
        : const Color(0xFF1E4BD8);

    final typeLabel =
        route.type == RouteType.bouldering ? l10n.bouldering : l10n.endurance;
    final completed = route.myCompletedCount ?? 0;
    final attempts = route.myTotalCount ?? 0;
    final lastAt = route.myLastActivityAt ?? route.createdAt;

    final placeText = [route.place?.name, route.wallName]
        .whereType<String>()
        .join(' · ');

    final showOwner = route.owner != null &&
        route.owner!.userId != ref.read(userProfileProvider).valueOrNull?.id;
    final isBlocked = _isBlocked;
    final blockedIcon = route.isDeleted ? '🗑' : '🔒';
    final blockedText =
        route.isDeleted ? l10n.routeDeletedLabel : l10n.routePrivateLabel;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
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
                                    placeholder: (_, __) =>
                                        Container(color: Colors.grey[200]),
                                    errorWidget: (_, __, ___) => Container(
                                      color: Colors.grey[300],
                                      child: const Icon(
                                        Icons.broken_image,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
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
                                if (isBlocked)
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      child: const SizedBox(),
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
                                  padding: const EdgeInsets.only(right: 40),
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
                                      Icon(
                                        Icons.place_outlined,
                                        size: 13,
                                        color: Colors.grey[500],
                                      ),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          placeText,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (showOwner) ...[
                                  const SizedBox(height: 6),
                                  OwnerBadge(owner: route.owner!),
                                ],
                                if (isBlocked) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        blockedIcon,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        blockedText,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF8A8F94),
                                          fontWeight: FontWeight.w500,
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
                                      color: completed > 0
                                          ? const Color(0xFF1EB980)
                                          : Colors.grey[400],
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      l10n.routeCardCompleted(completed),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: completed > 0
                                            ? const Color(0xFF0F1A2E)
                                            : Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      l10n.routeCardAttempts(attempts),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Spacer(),
                                    Text(
                                      timeago.format(lastAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
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
                  child: InkWell(
                    onTap: _handleShare,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.share_outlined,
                        size: 18,
                        color: Colors.grey[600],
                      ),
                    ),
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
          },
        ),
      ),
    );
  }
}
