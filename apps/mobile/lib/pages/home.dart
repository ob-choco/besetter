import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/image_data.dart';
import '../services/http_client.dart';
import '../widgets/hold_editor_button.dart';
import '../widgets/authorized_network_image.dart';
import 'package:dots_indicator/dots_indicator.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../pages/editors/route_editor_page.dart';
import '../models/polygon_data.dart';
import '../pages/editors/spray_wall_editor_page.dart';
import '../models/route_data.dart';
import '../pages/viewers/route_viewer.dart';
import 'package:intl/intl.dart';
import '../models/paginated_response.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import './setting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/confetti.dart';
import '../services/token_service.dart';
import '../widgets/guide_bubble.dart';
import 'package:provider/provider.dart';
import '../providers/image_state.dart' as image_provider;

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  double _currentPage = 0;
  final List<RouteData> _routes = [];
  String? _routesNextToken;
  bool _isLoadingMore = false;
  final ScrollController _routeScrollController = ScrollController();
  OverlayEntry? _overlayEntry;
  int? _totalCount;
  static const String _hasShownConfettiKey = 'has_shown_confetti_';
  bool _hasShownConfetti = false;
  static const String _hasShownGuideKey = 'has_shown_guide';
  final GlobalKey _editorButtonKey = GlobalKey();
  late GuideBubble? _guideBubble;
  bool _isGlobalLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _routeScrollController.addListener(_onRouteScroll);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _guideBubble = GuideBubble(
            context: context,
            targetKey: _editorButtonKey,
            message: AppLocalizations.of(context)!.uploadPhoto,
            autoDismissSeconds: 60,
            prefKey: _hasShownGuideKey,
          );
          _guideBubble?.initialize(this);
          _checkAndShowGuide();
        });
      }
    });
    
    _loadRouteData();
    _checkAndShowConfetti().then((_) {
      if (!_hasShownConfetti && mounted) {
        showDialog(
          context: context,
          builder: (context) => const ConfettiDialogWidget(),
        );
      }
    });

    _pageController.addListener(() {
      if (mounted) {
        setState(() {
          _currentPage = _pageController.page ?? 0;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _routeScrollController.dispose();
    if (this.mounted && _guideBubble != null) {
      _guideBubble?.dispose();
    }
    super.dispose();
  }

  void _onRouteScroll() {
    _handleInteraction();
    if (_routeScrollController.position.pixels >= _routeScrollController.position.maxScrollExtent * 0.8 &&
        !_isLoadingMore &&
        _routesNextToken != null) {
      _fetchNextRoutes();
    }
  }

  void _loadRouteData() {
    if(mounted) {
      setState(() {
        _routes.clear();
        _routesNextToken = null;
        _fetchNextRoutes();
        _fetchTotalCount();
      });
    }
  }

  Future<void> _fetchNextRoutes() async {
    if (_isLoadingMore) return;

    if(mounted) {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final queryParams = {
        'sort': 'createdAt:desc',
        'limit': '4',
        if (_routesNextToken != null) 'next': _routesNextToken!,
      };

      final uri = Uri.parse('/routes').replace(queryParameters: queryParams);
      final response = await AuthorizedHttpClient.get(uri.toString());

      if (response.statusCode == 200) {
        final result = PaginatedResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
          (json) => RouteData.fromJson(json),
        );

        if (mounted) {
          setState(() {
            _routes.addAll(result.data);
            _routesNextToken = result.nextToken;
            _isLoadingMore = false;
          });
        }
      } else {
        if (mounted) {
           setState(() { _isLoadingMore = false; });
        }
        throw Exception('Failed to load routes');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
        if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadRouteData)),
            );
        }
      }
    }
  }

  Future<void> _fetchTotalCount() async {
    try {
      final response = await AuthorizedHttpClient.get('/routes/count');
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _totalCount = data['totalCount'];
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch total count: $e');
    }
  }

  Future<void> navigateAndRefresh(
    Future<dynamic> Function() navigationAction,
    {dynamic refreshIfResultIs, bool refreshImages = false, bool refreshRoutes = false}
  ) async {
    _guideBubble?.removeOverlay();
    final result = await navigationAction();

    bool shouldPerformRefresh = false;
    if (refreshIfResultIs != null) {
      if (result == refreshIfResultIs) {
        shouldPerformRefresh = true;
      }
    } else if (result == true) {
      shouldPerformRefresh = true;
    }
    
    if (shouldPerformRefresh) {
      if (refreshImages && mounted) {
        await Provider.of<image_provider.ImageProvider>(context, listen: false).fetchImages(forceRefresh: true);
      }
      if (refreshRoutes && mounted) {
        _routes.clear();
        _routesNextToken = null;
        await _fetchNextRoutes();
        await _fetchTotalCount();
      }
    }
  }

  Future<void> _checkAndShowConfetti() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = await TokenService.getRefreshToken();
    
    if (refreshToken != null) {
      _hasShownConfetti = prefs.getBool('${_hasShownConfettiKey}$refreshToken') ?? false;
      
      if (!_hasShownConfetti && mounted) {
        
        // Confetti를 표시했음을 저장
        prefs.setBool('${_hasShownConfettiKey}$refreshToken', true);
      }
    }
  }

  Future<void> _checkAndShowGuide() async {
    if (_guideBubble != null) {
      await _guideBubble?.checkAndShow();
    }
  }

  Future<void> _handleInteraction() async {
    if (_guideBubble != null) {
      _guideBubble?.removeOverlay();
      await _guideBubble?.markAsShown();
    }
  }

  Future<void> _handleButtonTap() async {
    await _handleInteraction();
  }

  Widget _buildWelcomeSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context)!.setProblemAtGymNow,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(
          height: MediaQuery.of(context).size.width * 0.4,
        ),
      ],
    );
  }

  Widget _buildImageCarousel(List<ImageData> images) {
    final int totalPages = (images.length / 3).ceil();

    Widget _buildEmptyCard() {
      return const Expanded(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.0),
          child: AspectRatio(
            aspectRatio: 1,
            child: SizedBox(), // 투명한 placeholder
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context)!.setRouteWithRecentPhoto,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: MediaQuery.of(context).size.width * 0.4,
          child: PageView.builder(
            controller: _pageController,
            itemCount: totalPages.clamp(0, 3),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, pageIndex) {
              final startIndex = pageIndex * 3;
              final endIndex = (startIndex + 3).clamp(0, images.length);
              final pageImages = images.sublist(startIndex, endIndex);

              if (pageIndex == 2) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    children: [
                      ...pageImages.take(2).map((image) => Expanded(
                            child: _buildImageCard(image, context),
                          )),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/images'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Card(
                                child: Container(
                                  color: Colors.grey[200],
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_circle_outline, size: 32),
                                        SizedBox(height: 4),
                                        Text(AppLocalizations.of(context)!.viewMore, style: TextStyle(fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    ...pageImages.map((image) => Expanded(
                          child: _buildImageCard(image, context),
                        )),
                    // 남은 공간을 빈 카드로 채움
                    ...List.generate(3 - pageImages.length, (_) => _buildEmptyCard()),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        DotsIndicator(
          dotsCount: totalPages.clamp(0, 3),
          position: _currentPage.toInt(),
          decorator: DotsDecorator(
            activeColor: Theme.of(context).primaryColor,
            size: const Size.square(6.0),
            activeSize: const Size.square(6.0),
            spacing: const EdgeInsets.all(4.0),
          ),
        ),
      ],
    );
  }

  Widget _buildImageCard(ImageData image, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: () {
            _handleInteraction();
            showDialog(
              context: context,
              barrierDismissible: true,
              builder: (BuildContext context) {
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildIconButton(
                              context: context,
                              icon: 'assets/icons/wall_edit_button.svg',
                              label: 'WALL EDIT',
                              size: iconSize,
                              onTap: () async {
                                _showLoadingOverlay();
                                try {
                                  final response = await AuthorizedHttpClient.get(
                                    '/hold-polygons/${image.holdPolygonId}',
                                  );
                                  if (response.statusCode == 200) {
                                    final polygonData = jsonDecode(utf8.decode(response.bodyBytes));
                                    if (!mounted) return;
                                    _hideLoadingOverlay();
                                    Navigator.pop(context);
                                    await navigateAndRefresh(() async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => SprayWallEditorPage(
                                            image: image,
                                            polygonData: PolygonData.fromJson(polygonData),
                                          ),
                                        ),
                                      );
                                    });
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  _hideLoadingOverlay();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
                                  );
                                }
                              },
                            ),
                            _buildIconButton(
                              context: context,
                              icon: 'assets/icons/bouldering_button.svg',
                              label: 'BOULDERING',
                              size: iconSize,
                              onTap: () async {
                                _showLoadingOverlay();
                                try {
                                  final response = await AuthorizedHttpClient.get(
                                    '/hold-polygons/${image.holdPolygonId}',
                                  );
                                  if (response.statusCode == 200) {
                                    final polygonData = jsonDecode(response.body);
                                    if (!mounted) return;
                                    _hideLoadingOverlay();
                                    Navigator.pop(context);
                                    await navigateAndRefresh(() async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => RouteEditorPage(
                                            image: image,
                                            polygonData: PolygonData.fromJson(polygonData),
                                            initialMode: RouteEditModeType.bouldering,
                                          ),
                                        ),
                                      );
                                    });
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  _hideLoadingOverlay();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
                                  );
                                }
                              },
                            ),
                            _buildIconButton(
                              context: context,
                              icon: 'assets/icons/endurance_button.svg',
                              label: 'ENDURANCE',
                              size: iconSize,
                              onTap: () async {
                                _showLoadingOverlay();
                                try {
                                  final response = await AuthorizedHttpClient.get(
                                    '/hold-polygons/${image.holdPolygonId}',
                                  );
                                  if (response.statusCode == 200) {
                                    final polygonData = jsonDecode(response.body);
                                    if (!mounted) return;
                                    _hideLoadingOverlay();
                                    Navigator.pop(context);
                                    await navigateAndRefresh(() async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => RouteEditorPage(
                                            image: image,
                                            polygonData: PolygonData.fromJson(polygonData),
                                            initialMode: RouteEditModeType.endurance,
                                          ),
                                        ),
                                      );
                                    });
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  _hideLoadingOverlay();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AuthorizedNetworkImage(
                  imageUrl: image.url,
                  fit: BoxFit.cover,
                ),
                if (image.wallName != null &&
                    image.wallName!.isNotEmpty &&
                    image.gymName != null &&
                    image.gymName!.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      color: Colors.black54,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            image.wallName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            image.gymName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required BuildContext context,
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

  void _showLoadingOverlay() {
    if (_isGlobalLoading) return;
    _isGlobalLoading = true;
    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black54,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
    if(mounted && _overlayEntry != null) {
        Overlay.of(context).insert(_overlayEntry!);
    }
  }

  void _hideLoadingOverlay() {
    if (!_isGlobalLoading) return;
    _isGlobalLoading = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildImageSection() {
    final imageProvider = context.watch<image_provider.ImageProvider>();

    if (imageProvider.isLoading && (imageProvider.images == null || imageProvider.images!.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (imageProvider.error != null && (imageProvider.images == null || imageProvider.images!.isEmpty)) {
      return Center(
        child: Text(AppLocalizations.of(context)!.errorOccurred),
      );
    }
    
    if (imageProvider.images == null || imageProvider.images!.isEmpty) {
      return _buildWelcomeSection();
    }
    
    return _buildImageCarousel(imageProvider.images!);
  }

  Widget _buildRouteList() {
    return ListView.builder(
      controller: _routeScrollController,
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _routes.length + (_routesNextToken != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _routes.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: _buildRouteCard(_routes[index]),
        );
      },
    );
  }

  Widget _buildRouteCard(RouteData route) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () async {
          _handleInteraction();
          _showLoadingOverlay();
          try {
            final response = await AuthorizedHttpClient.get('/routes/${route.id}');
            if (response.statusCode == 200) {
              final routeData = RouteData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
              if (!mounted) return;
              Navigator.push(
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
            _hideLoadingOverlay();
          }
        },
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
                  // 오른쪽 상단 버튼들
                  Row(
                    children: [
                      // todo 공유 기능
                      // SizedBox(
                      //   width: 24,
                      //   height: 24,
                      //   child: IconButton(
                      //     padding: EdgeInsets.zero,
                      //     constraints: const BoxConstraints(),
                      //     icon: const Icon(Icons.ios_share, size: 20),
                      //     onPressed: () {
                      //       // 공유 기능
                      //     },
                      //   ),
                      // ),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.menu, size: 20),
                          itemBuilder: (BuildContext context) => [
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
                          onSelected: (String value) async {
                            if (value == 'edit') {
                              _showLoadingOverlay();
                              try {
                                if (!mounted) return;
                                _hideLoadingOverlay();
                                await navigateAndRefresh(() async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => RouteEditorPage(
                                        routeId: route.id,
                                        editType: EditType.edit,
                                        initialMode: route.type == RouteType.bouldering
                                            ? RouteEditModeType.bouldering
                                            : RouteEditModeType.endurance,
                                      ),
                                    ),
                                  );
                                });
                              } catch (e) {
                                if (!mounted) return;
                                _hideLoadingOverlay();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
                                );
                              }
                            } else if (value == 'delete') {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: Text(AppLocalizations.of(context)!.deleteRoute),
                                    content: Text(AppLocalizations.of(context)!.confirmDeleteRoute),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: Text(AppLocalizations.of(context)!.cancel),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          Navigator.of(context).pop();
                                          _showLoadingOverlay();
                                          try {
                                            final response = await AuthorizedHttpClient.delete('/routes/${route.id}');
                                            if (response.statusCode == 204) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text(AppLocalizations.of(context)!.routeDeleted)),
                                              );
                                              _loadRouteData();
                                            } else {
                                              throw Exception('Failed to delete route');
                                            }
                                          } catch (e) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text(AppLocalizations.of(context)!.failedDeleteRoute)),
                                            );
                                          } finally {
                                            _hideLoadingOverlay();
                                          }
                                        },
                                        child: Text(AppLocalizations.of(context)!.delete),
                                      ),
                                    ],
                                  );
                                },
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 하단 정보 영역 (회색 배경)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[200],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 위치 정보가 있을 때만 Expanded 위젯으로 감싸기
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
                  // 위치 정보가 없을 때는 Spacer로 왼쪽 공간을 채우고 날짜를 우측 정렬
                  if (route.gymName == null || route.wallName == null) const Spacer(),
                  // 날짜/시간
                  Text(
                    DateFormat.yMd(AppLocalizations.of(context)!.localeName).add_jm().format(route.createdAt),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    icon: const Icon(Icons.menu),
                    iconSize: 32,
                    onPressed: () {
                      _handleInteraction();
                      _guideBubble?.removeOverlayImmediately();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsPage(),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: CustomScrollView(
              controller: _routeScrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16.0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Center(child: HoldEditorButton(
                        buttonKey: _editorButtonKey,
                        onTapDown: _handleButtonTap,
                      )),
                      const SizedBox(height: 32),
                      _buildImageSection(),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Text(
                            AppLocalizations.of(context)!.routeCard,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_totalCount != null)
                            Text(
                              ' $_totalCount',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ]),
                  ),
                ),
                if (_routes.isEmpty && _isLoadingMore)
                  const SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index == _routes.length) {
                            return (_routesNextToken != null && _isLoadingMore)
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: _buildRouteCard(_routes[index]),
                          );
                        },
                        childCount: _routes.length + ((_routesNextToken != null && _isLoadingMore) ? 1 : 0),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_isGlobalLoading)
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
