import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/image_data.dart';
import '../services/http_client.dart';
import '../services/token_service.dart';
import 'editors/spray_wall_editor_page.dart';
import '../models/polygon_data.dart';
import 'editors/route_editor_page.dart';
import '../widgets/authorized_network_image.dart';
import 'package:intl/intl.dart';
import '../models/paginated_response.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../widgets/place_pending_badge.dart';

class ImageListPage extends StatefulWidget {
  const ImageListPage({Key? key}) : super(key: key);

  @override
  State<ImageListPage> createState() => _ImageListPageState();
}

class _ImageListPageState extends State<ImageListPage> {
  final List<ImageData> _images = [];
  String? _nextToken;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  int? _selectedImageIndex;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchNextPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoading &&
        _nextToken != null) {
      _fetchNextPage();
    }
  }

  Future<void> _fetchNextPage() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final queryParams = {
        'sort': 'uploadedAt:desc',
        'limit': '10',
        if (_nextToken != null) 'next': _nextToken!,
      };

      final uri = Uri.parse('/images').replace(queryParameters: queryParams);
      final response = await AuthorizedHttpClient.get(uri.toString());

      if (response.statusCode == 200) {
        final result = PaginatedResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
          (json) => ImageData.fromJson(json),
        );

        setState(() {
          _images.addAll(result.data);
          _nextToken = result.nextToken;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load image data');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadImageData)),
        );
      }
    }
  }

  Widget _buildImageGrid() {
    final groupedImages = <DateTime, List<ImageData>>{};
    for (var image in _images) {
      final date = DateTime(
        image.uploadedAt.year,
        image.uploadedAt.month,
        image.uploadedAt.day,
      );
      groupedImages.putIfAbsent(date, () => []).add(image);
    }

    final sortedDates = groupedImages.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      controller: _scrollController,
      itemCount: sortedDates.length + (_nextToken != null ? 1 : 0),
      itemBuilder: (context, dateIndex) {
        if (dateIndex == sortedDates.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final date = sortedDates[dateIndex];
        final dateImages = groupedImages[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                DateFormat.yMMMEd(AppLocalizations.of(context)!.localeName).format(date),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: dateImages.length,
              itemBuilder: (context, index) {
                final image = dateImages[index];
                final globalIndex = _images.indexOf(image);
                return _buildImageCard(image, globalIndex);
              },
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildImageCard(ImageData image, int index) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_selectedImageIndex == index) {
            _selectedImageIndex = null;
          } else {
            _selectedImageIndex = index;
          }
        });
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<String?>(
              future: TokenService.getAccessToken(),
              builder: (context, tokenSnapshot) {
                if (tokenSnapshot.hasData) {
                  return AuthorizedNetworkImage(
                    imageUrl: image.url,
                    fit: BoxFit.cover,
                  );
                }
                return const Center(
                  child: CircularProgressIndicator(),
                );
              },
            ),
            if (_selectedImageIndex == index)
              Container(
                color: Colors.black45,
              ),
            if (_selectedImageIndex == index)
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 48,
                      icon: Icon(Icons.brush, color: Colors.white),
                      onPressed: () async {
                        try {
                          final response = await AuthorizedHttpClient.get('/hold-polygons/${image.holdPolygonId}');
                          if (response.statusCode == 200) {
                            final polygonData = jsonDecode(response.body);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SprayWallEditorPage(
                                  image: image,
                                  polygonData: PolygonData.fromJson(polygonData),
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
                          );
                        }
                      },
                    ),
                    IconButton(
                      iconSize: 48,
                      icon: Icon(Icons.edit, color: Colors.white),
                      onPressed: () async {
                        try {
                          final response = await AuthorizedHttpClient.get('/hold-polygons/${image.holdPolygonId}');
                          if (response.statusCode == 200) {
                            final polygonData = jsonDecode(response.body);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RouteEditorPage(
                                  image: image,
                                  polygonData: PolygonData.fromJson(polygonData),
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadData)),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black54,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (image.wallName != null && image.wallName!.isNotEmpty)
                      Text(
                        image.wallName!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (image.place != null && image.place!.name.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              image.place!.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (image.place!.isPending) ...[
                            const SizedBox(width: 4),
                            const PlacePendingBadge(),
                          ],
                        ],
                      ),
                    Text(
                      DateFormat.yMd(AppLocalizations.of(context)!.localeName).format(image.uploadedAt),
                      // DateFormat('yyyy.MM.dd').format(image.uploadedAt),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(AppLocalizations.of(context)!.mySprayWall),
      ),
      body: _images.isEmpty && _isLoading ? const Center(child: CircularProgressIndicator()) : _buildImageGrid(),
    );
  }
}
