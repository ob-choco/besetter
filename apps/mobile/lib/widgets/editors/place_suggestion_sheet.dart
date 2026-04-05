import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place_data.dart';
import '../../services/place_service.dart';

class PlaceSuggestionSheet extends StatefulWidget {
  final PlaceData place;

  const PlaceSuggestionSheet({
    Key? key,
    required this.place,
  }) : super(key: key);

  static Future<void> show(
    BuildContext context, {
    required PlaceData place,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: PlaceSuggestionSheet(place: place),
      ),
    );
  }

  @override
  State<PlaceSuggestionSheet> createState() => _PlaceSuggestionSheetState();
}

class _PlaceSuggestionSheetState extends State<PlaceSuggestionSheet> {
  late final TextEditingController _nameController;
  LatLng? _newPosition;
  bool _isSubmitting = false;

  bool get _isGym => widget.place.type == 'gym';

  Color get _accentColor =>
      _isGym ? const Color(0xFF6750A4) : const Color(0xFFF57C00);

  LatLng? get _originalPosition {
    if (widget.place.latitude != null && widget.place.longitude != null) {
      return LatLng(widget.place.latitude!, widget.place.longitude!);
    }
    return null;
  }

  bool get _hasCoordinates => _originalPosition != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _isGym ? '' : widget.place.name,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    final nameChanged = _isGym
        ? _nameController.text.trim().isNotEmpty
        : _nameController.text.trim() != widget.place.name;
    return nameChanged || _newPosition != null;
  }

  Future<void> _submit() async {
    if (!_hasChanges || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    final newName = _nameController.text.trim();

    try {
      if (_isGym) {
        // Suggestion mode
        await PlaceService.createSuggestion(
          placeId: widget.place.id,
          name: newName.isNotEmpty ? newName : null,
          latitude: _newPosition?.latitude,
          longitude: _newPosition?.longitude,
        );
        if (mounted) {
          Navigator.pop(context);
          _showSuccessDialog();
        }
      } else {
        // Direct edit mode for private-gym
        await PlaceService.updatePlace(
          widget.place.id,
          name: newName.isNotEmpty && newName != widget.place.name
              ? newName
              : null,
          latitude: _newPosition?.latitude,
          longitude: _newPosition?.longitude,
        );
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('수정되었습니다')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('요청에 실패했습니다. 다시 시도해주세요.')),
        );
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF6750A4).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Color(0xFF6750A4),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '제안이 접수되었습니다',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '운영자 검수 후 반영됩니다.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6750A4),
              ),
              child: const Text('확인'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            _isGym ? '정보 수정 제안' : '암장 정보 수정',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        // Subtitle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _isGym ? '검수 후 반영됩니다' : '🔒 개인 암장 · 즉시 반영됩니다',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
        const SizedBox(height: 8),
        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                // Name section
                const Text(
                  '이름',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (_isGym) ...[
                  // Current name with strikethrough for gym
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          widget.place.name,
                          style: const TextStyle(
                            fontSize: 14,
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '현재',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Icon(
                      Icons.arrow_downward,
                      size: 18,
                      color: Colors.grey,
                    ),
                  ),
                ],
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: _isGym ? '변경할 이름 입력' : '암장 이름',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                // Map
                if (_hasCoordinates) ...[
                  const Text(
                    '위치',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_isGym)
                    Text(
                      '지도를 탭하여 올바른 위치를 지정하세요',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _originalPosition!,
                          initialZoom: 16,
                          onTap: (tapPosition, point) {
                            setState(() => _newPosition = point);
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.besetter.app',
                          ),
                          MarkerLayer(
                            markers: [
                              // Original position marker (grey for gym)
                              if (_isGym)
                                Marker(
                                  point: _originalPosition!,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(
                                    Icons.location_pin,
                                    color: Colors.grey,
                                    size: 40,
                                  ),
                                ),
                              // New position marker (gym: purple when moved)
                              if (_isGym && _newPosition != null)
                                Marker(
                                  point: _newPosition!,
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    Icons.location_pin,
                                    color: _accentColor,
                                    size: 40,
                                  ),
                                ),
                              // Private gym: single colored pin
                              if (!_isGym)
                                Marker(
                                  point: _newPosition ?? _originalPosition!,
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    Icons.location_pin,
                                    color: _accentColor,
                                    size: 40,
                                  ),
                                ),
                            ],
                          ),
                          RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution(
                                  'OpenStreetMap contributors'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Submit button
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _hasChanges && !_isSubmitting ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _accentColor,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isGym ? '수정 제안하기' : '수정하기'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
