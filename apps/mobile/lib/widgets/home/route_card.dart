import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/route_data.dart';
import '../../services/http_client.dart';
import '../../providers/routes_provider.dart';
import '../../pages/viewers/route_viewer.dart';
import '../../pages/editors/route_editor_page.dart';
import '../authorized_network_image.dart';

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
    if (mounted) {
      setState(() => _isLoading = value);
    }
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
          MaterialPageRoute(
            builder: (context) => RouteViewer(routeData: routeData),
          ),
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
      ref.invalidate(routesProvider);
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
      final success = await ref.read(routesProvider.notifier).deleteRoute(widget.route.id);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.routeDeleted)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.failedDeleteRoute)),
        );
      }
    } finally {
      _setLoading(false);
    }
  }

  void _handleShare() {
    const baseUrl = 'https://besetter-api-371038003203.asia-northeast3.run.app';
    final shareUrl = '$baseUrl/share/routes/${widget.route.id}';
    Share.share(shareUrl);
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;

    return Stack(
      children: [
        Card(
          elevation: 2,
          child: InkWell(
            onTap: _navigateToViewer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 60,
                          height: 60,
                          child: AuthorizedNetworkImage(
                            imageUrl: route.imageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 60,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${route.grade} ${route.type == RouteType.bouldering ? AppLocalizations.of(context)!.bouldering : AppLocalizations.of(context)!.endurance}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.share, size: 20),
                              onPressed: _handleShare,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.more_vert, size: 20),
                              itemBuilder: (context) => [
                                PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit),
                                      const SizedBox(width: 8),
                                      Text(AppLocalizations.of(context)!.doEdit),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete),
                                      const SizedBox(width: 8),
                                      Text(AppLocalizations.of(context)!.doDelete),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _handleEdit();
                                } else if (value == 'delete') {
                                  _handleDelete();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.grey[200],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (route.gymName != null && route.wallName != null)
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: Colors.grey[700],
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${route.gymName} - ${route.wallName}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (route.gymName == null || route.wallName == null)
                        const Spacer(),
                      Text(
                        DateFormat.yMd(AppLocalizations.of(context)!.localeName)
                            .add_jm()
                            .format(route.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }
}
