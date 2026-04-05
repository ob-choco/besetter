import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/place_data.dart';
import '../../services/place_service.dart';
import 'place_registration_sheet.dart';
import 'place_suggestion_sheet.dart';

class PlaceSelectionSheet extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final PlaceData? currentPlace;

  const PlaceSelectionSheet({
    Key? key,
    this.latitude,
    this.longitude,
    this.currentPlace,
  }) : super(key: key);

  static Future<PlaceData?> show(
    BuildContext context, {
    double? latitude,
    double? longitude,
    PlaceData? currentPlace,
  }) {
    return showModalBottomSheet<PlaceData>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => PlaceSelectionSheet(
        latitude: latitude,
        longitude: longitude,
        currentPlace: currentPlace,
      ),
    );
  }

  @override
  State<PlaceSelectionSheet> createState() => _PlaceSelectionSheetState();
}

class _PlaceSelectionSheetState extends State<PlaceSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<PlaceData> _places = [];
  bool _isLoading = false;
  bool _isSearchMode = false;

  @override
  void initState() {
    super.initState();
    _loadNearbyPlaces();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadNearbyPlaces() async {
    if (widget.latitude == null || widget.longitude == null) return;
    setState(() => _isLoading = true);
    try {
      final places = await PlaceService.getNearbyPlaces(
        latitude: widget.latitude!,
        longitude: widget.longitude!,
        radius: 5000,
      );
      if (mounted) {
        setState(() {
          _places = places;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() => _isSearchMode = false);
      _loadNearbyPlaces();
      return;
    }
    _debounce = Timer(const Duration(seconds: 1), () async {
      setState(() {
        _isSearchMode = true;
        _isLoading = true;
      });
      try {
        final results = await PlaceService.instantSearch(query);
        if (mounted) {
          setState(() {
            _places = results;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    });
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '';
    if (distance < 1000) {
      return '${distance.round()}m';
    }
    return '${(distance / 1000).toStringAsFixed(1)}km';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '암장 선택',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: '암장 이름으로 검색',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            // List section
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _places.isEmpty
                      ? Center(
                          child: Text(
                            _isSearchMode ? '검색 결과가 없습니다' : '근처에 등록된 암장이 없습니다',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _places.length + 1, // +1 for header
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              if (!_isSearchMode) {
                                return const Padding(
                                  padding: EdgeInsets.only(
                                    top: 8,
                                    bottom: 4,
                                  ),
                                  child: Text(
                                    '📍 근처 암장',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            }
                            final place = _places[index - 1];
                            return _buildPlaceItem(place);
                          },
                        ),
            ),
            // Divider + Register button
            const Divider(height: 1),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildRegisterButton(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaceItem(PlaceData place) {
    final bool isSelected = widget.currentPlace?.id == place.id;
    final bool isPrivate = place.type == 'private-gym';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.pop(context, place),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isPrivate ? const Color(0xFFFFF8E1) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF6750A4)
                    : Colors.grey.withValues(alpha: 0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: place.thumbnailUrl != null
                            ? CachedNetworkImage(
                                imageUrl: place.thumbnailUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey[200],
                                  child: const Icon(
                                    Icons.store,
                                    color: Colors.grey,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey[200],
                                  child: const Icon(
                                    Icons.store,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            : Container(
                                color: Colors.grey[200],
                                child: const Icon(
                                  Icons.store,
                                  color: Colors.grey,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name + distance
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isPrivate) ...[
                                const Text('🔒 ',
                                    style: TextStyle(fontSize: 13)),
                              ],
                              Flexible(
                                child: Text(
                                  place.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (place.distance != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              _formatDistance(place.distance),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                          if (isPrivate) ...[
                            const SizedBox(height: 2),
                            Text(
                              '나만 보임',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange[700],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Type badge + selected badge
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isPrivate
                                ? Colors.orange.withValues(alpha: 0.15)
                                : Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isPrivate ? 'private' : 'gym',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isPrivate
                                  ? Colors.orange[800]
                                  : Colors.green[800],
                            ),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6750A4)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '선택됨',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6750A4),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                // Edit suggestion link for selected item
                if (isSelected) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      PlaceSuggestionSheet.show(context, place: place);
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('✏️ ', style: TextStyle(fontSize: 12)),
                        Text(
                          '정보 수정 제안',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6750A4),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterButton() {
    return InkWell(
      onTap: () async {
        final result = await PlaceRegistrationSheet.show(
          context,
          latitude: widget.latitude,
          longitude: widget.longitude,
        );
        if (result != null && mounted) {
          Navigator.pop(context, result);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[400]!,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 18, color: Colors.grey[700]),
            const SizedBox(width: 8),
            Text(
              '새 암장 등록하기',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
