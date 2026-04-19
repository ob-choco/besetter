import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/image_data.dart';
import '../../models/polygon_data.dart';
import '../../services/http_client.dart';
import '../../pages/editors/route_editor_page.dart';
import '../../pages/editors/spray_wall_editor_page.dart';

class WallMiniCard extends ConsumerStatefulWidget {
  final ImageData image;
  final bool compact;

  const WallMiniCard({super.key, required this.image, this.compact = false});

  @override
  ConsumerState<WallMiniCard> createState() => _WallMiniCardState();
}

class _WallMiniCardState extends ConsumerState<WallMiniCard> {
  bool _isLoading = false;

  Future<PolygonData?> _fetchPolygonData() async {
    if (_isLoading) return null;
    setState(() => _isLoading = true);
    try {
      final response = await AuthorizedHttpClient.get(
        '/hold-polygons/${widget.image.holdPolygonId}',
      );
      if (response.statusCode == 200) {
        return PolygonData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (_) {
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
      builder: (_) => _CreateRouteDialog(image: widget.image, polygonData: polygonData),
    );
  }

  Future<void> _onEditWall() async {
    final polygonData = await _fetchPolygonData();
    if (polygonData == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SprayWallEditorPage(image: widget.image, polygonData: polygonData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final image = widget.image;
    final placeName = image.place?.name ?? '';
    final wallName = image.wallName ?? '';
    final topLine = wallName.isNotEmpty ? wallName : placeName;
    final subLine = wallName.isNotEmpty ? placeName : '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: image.url,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.grey[300]),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.broken_image, size: 40),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.78)],
                    stops: const [0.35, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l10n.routeCountLabel(image.routeCount).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            Positioned(
              left: widget.compact ? 10 : 14,
              right: widget.compact ? 10 : 14,
              bottom: widget.compact ? 10 : 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (topLine.isNotEmpty)
                    Text(
                      topLine,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (subLine.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subLine,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 1000,
                        child: _ActionButton(
                          label: l10n.doEdit,
                          onTap: _onEditWall,
                          compact: widget.compact,
                        ),
                      ),
                      SizedBox(width: widget.compact ? 4 : 6),
                      Expanded(
                        flex: 1618,
                        child: _ActionButton(
                          label: l10n.createRoute,
                          icon: Icons.arrow_outward,
                          onTap: _onCreateRoute,
                          compact: widget.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black38,
                  child: Center(child: CircularProgressIndicator()),
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
  final bool compact;

  const _ActionButton({
    required this.label,
    this.icon,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.22),
          borderRadius: BorderRadius.circular(compact ? 7 : 8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (icon != null) ...[
              SizedBox(width: compact ? 2 : 3),
              Icon(icon, color: Colors.white, size: compact ? 12 : 14),
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

  const _CreateRouteDialog({required this.image, required this.polygonData});

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
                _modeButton(context, 'assets/icons/bouldering_button.svg', iconSize,
                    RouteEditModeType.bouldering),
                _modeButton(context, 'assets/icons/endurance_button.svg', iconSize,
                    RouteEditModeType.endurance),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButton(BuildContext context, String icon, double size, RouteEditModeType mode) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RouteEditorPage(
              image: image,
              polygonData: polygonData,
              initialMode: mode,
            ),
          ),
        );
      },
      child: SvgPicture.asset(icon, width: size * 0.6, height: size * 0.6),
    );
  }
}
