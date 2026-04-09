import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/image_data.dart';
import '../../models/polygon_data.dart';
import '../../services/http_client.dart';
import '../../pages/editors/route_editor_page.dart';
import '../../pages/editors/spray_wall_editor_page.dart';

class WallCard extends ConsumerStatefulWidget {
  final ImageData image;

  const WallCard({super.key, required this.image});

  @override
  ConsumerState<WallCard> createState() => _WallCardState();
}

class _WallCardState extends ConsumerState<WallCard> {
  bool _isLoading = false;

  Future<PolygonData?> _fetchPolygonData() async {
    if (_isLoading) return null;
    setState(() => _isLoading = true);
    try {
      final response = await AuthorizedHttpClient.get(
        '/hold-polygons/${widget.image.holdPolygonId}',
      );
      if (response.statusCode == 200) {
        return PolygonData.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.failedToLoadData)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    return null;
  }

  Future<void> _onCreateRoute() async {
    final polygonData = await _fetchPolygonData();
    if (polygonData == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _CreateRouteDialog(
        image: widget.image,
        polygonData: polygonData,
      ),
    );
  }

  Future<void> _onEditWall() async {
    final polygonData = await _fetchPolygonData();
    if (polygonData == null || !mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SprayWallEditorPage(
          image: widget.image,
          polygonData: polygonData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy').format(widget.image.uploadedAt);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // 배경 이미지 (디스크 캐시)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: widget.image.url,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey[300],
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image, size: 48),
              ),
            ),
          ),
          // 하단 그라데이션 오버레이
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
          ),
          // 하단 정보 + 버튼
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.image.place?.name ?? AppLocalizations.of(context)!.enterGymInfoGuide,
                  style: TextStyle(
                    color: widget.image.place?.name != null ? Colors.white : Colors.white70,
                    fontSize: 18,
                    fontWeight: widget.image.place?.name != null ? FontWeight.bold : FontWeight.normal,
                    fontStyle: widget.image.place?.name != null ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 4),
                if (widget.image.wallName != null)
                  Text(
                    widget.image.wallName!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                Text(
                  dateStr,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _ActionButton(
                      label: AppLocalizations.of(context)!.editWall,
                      onTap: _onEditWall,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      label: AppLocalizations.of(context)!.createRoute,
                      icon: Icons.arrow_outward,
                      onTap: _onCreateRoute,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 로딩 오버레이
          if (_isLoading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(icon, color: Colors.white, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateRouteDialog extends StatelessWidget {
  final ImageData image;
  final PolygonData polygonData;

  const _CreateRouteDialog({
    required this.image,
    required this.polygonData,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = (screenWidth * 0.2).clamp(60.0, 100.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context)!.createRoute,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildModeButton(
                  context: context,
                  icon: 'assets/icons/bouldering_button.svg',
                  size: iconSize,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RouteEditorPage(
                          image: image,
                          polygonData: polygonData,
                          initialMode: RouteEditModeType.bouldering,
                        ),
                      ),
                    );
                  },
                ),
                _buildModeButton(
                  context: context,
                  icon: 'assets/icons/endurance_button.svg',
                  size: iconSize,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RouteEditorPage(
                          image: image,
                          polygonData: polygonData,
                          initialMode: RouteEditModeType.endurance,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required BuildContext context,
    required String icon,
    required double size,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SvgPicture.asset(
          icon,
          width: size * 0.6,
          height: size * 0.6,
        ),
      ),
    );
  }
}
