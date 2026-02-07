import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/image_data.dart';
import '../../models/polygon_data.dart';
import '../../services/http_client.dart';
import '../../pages/editors/route_editor_page.dart';
import '../../pages/editors/spray_wall_editor_page.dart';

class EditModeDialog extends ConsumerStatefulWidget {
  final ImageData image;

  const EditModeDialog({
    super.key,
    required this.image,
  });

  @override
  ConsumerState<EditModeDialog> createState() => _EditModeDialogState();
}

class _EditModeDialogState extends ConsumerState<EditModeDialog> {
  bool _isLoading = false;

  Future<void> _handleModeSelection(
    BuildContext context,
    Future<void> Function(PolygonData polygonData) onSuccess,
  ) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final response = await AuthorizedHttpClient.get(
        '/hold-polygons/${widget.image.holdPolygonId}',
      );
      if (response.statusCode == 200) {
        final polygonData = PolygonData.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
        if (!mounted) return;
        Navigator.pop(context);
        await onSuccess(polygonData);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = (screenWidth * 0.2).clamp(60.0, 100.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: screenWidth * 0.9,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildIconButton(
                      icon: 'assets/icons/wall_edit_button.svg',
                      label: 'WALL EDIT',
                      size: iconSize,
                      onTap: () => _handleModeSelection(
                        context,
                        (polygonData) async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SprayWallEditorPage(
                                image: widget.image,
                                polygonData: polygonData,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _buildIconButton(
                      icon: 'assets/icons/bouldering_button.svg',
                      label: 'BOULDERING',
                      size: iconSize,
                      onTap: () => _handleModeSelection(
                        context,
                        (polygonData) async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RouteEditorPage(
                                image: widget.image,
                                polygonData: polygonData,
                                initialMode: RouteEditModeType.bouldering,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _buildIconButton(
                      icon: 'assets/icons/endurance_button.svg',
                      label: 'ENDURANCE',
                      size: iconSize,
                      onTap: () => _handleModeSelection(
                        context,
                        (polygonData) async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RouteEditorPage(
                                image: widget.image,
                                polygonData: polygonData,
                                initialMode: RouteEditModeType.endurance,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required String icon,
    required String label,
    required VoidCallback onTap,
    required double size,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
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
        ],
      ),
    );
  }
}
