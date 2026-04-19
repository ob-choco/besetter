import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../models/image_data.dart';
import '../models/paginated_response.dart';
import '../services/http_client.dart';
import '../widgets/home/wall_mini_card.dart';

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

  Widget _buildBody() {
    final groupedImages = <DateTime, List<ImageData>>{};
    for (final image in _images) {
      final date = DateTime(
        image.uploadedAt.year,
        image.uploadedAt.month,
        image.uploadedAt.day,
      );
      groupedImages.putIfAbsent(date, () => []).add(image);
    }

    final sortedDates = groupedImages.keys.toList()..sort((a, b) => b.compareTo(a));
    final l10n = AppLocalizations.of(context)!;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        for (final date in sortedDates) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Text(
                DateFormat.yMMMEd(l10n.localeName).format(date),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: Color(0xFF0F1A2E),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 240 / 280,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => WallMiniCard(
                  image: groupedImages[date]![index],
                  compact: true,
                ),
                childCount: groupedImages[date]!.length,
              ),
            ),
          ),
        ],
        if (_nextToken != null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F6F7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(AppLocalizations.of(context)!.mySprayWall),
      ),
      body: _images.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }
}
