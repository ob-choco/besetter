import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place_data.dart';
import '../../services/place_service.dart';

class PlaceRegistrationSheet extends StatefulWidget {
  final double? latitude;
  final double? longitude;

  const PlaceRegistrationSheet({
    Key? key,
    this.latitude,
    this.longitude,
  }) : super(key: key);

  static Future<PlaceData?> show(
    BuildContext context, {
    double? latitude,
    double? longitude,
  }) {
    return showModalBottomSheet<PlaceData>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: PlaceRegistrationSheet(
          latitude: latitude,
          longitude: longitude,
        ),
      ),
    );
  }

  @override
  State<PlaceRegistrationSheet> createState() =>
      _PlaceRegistrationSheetState();
}

class _PlaceRegistrationSheetState extends State<PlaceRegistrationSheet> {
  final TextEditingController _nameController = TextEditingController();
  LatLng? _pinPosition;
  bool _isPrivate = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.latitude != null && widget.longitude != null) {
      _pinPosition = LatLng(widget.latitude!, widget.longitude!);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  LatLng get _mapCenter {
    if (_pinPosition != null) return _pinPosition!;
    return const LatLng(37.5665, 126.9780); // Seoul default
  }

  bool get _showMap {
    if (_isPrivate) return false;
    return _pinPosition != null ||
        (widget.latitude != null && widget.longitude != null);
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final type = _isPrivate ? 'private-gym' : 'gym';

    // gym type requires coordinates
    if (!_isPrivate && _pinPosition == null) return;

    setState(() => _isSubmitting = true);

    try {
      final place = await PlaceService.createPlace(
        name: name,
        type: type,
        latitude: _pinPosition?.latitude,
        longitude: _pinPosition?.longitude,
      );
      if (mounted) {
        Navigator.pop(context, place);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('등록에 실패했습니다. 다시 시도해주세요.')),
        );
      }
    }
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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            '새 암장 등록',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '새로운 클라이밍 암장을 등록합니다',
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
                // Name field
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '암장 이름',
                    hintText: '암장 이름을 입력하세요',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                // Map
                if (_showMap) ...[
                  const Text(
                    '위치 선택',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '지도를 탭하여 위치를 지정하세요',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _mapCenter,
                          initialZoom: 16,
                          onTap: (tapPosition, point) {
                            setState(() => _pinPosition = point);
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.besetter.app',
                          ),
                          if (_pinPosition != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _pinPosition!,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(
                                    Icons.location_pin,
                                    color: Colors.red,
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
                  const SizedBox(height: 16),
                ],
                // Private toggle
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '개인 암장',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '나만 볼 수 있는 암장',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    value: _isPrivate,
                    onChanged: (value) {
                      setState(() => _isPrivate = value);
                    },
                  ),
                ),
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
                onPressed: _canSubmit ? _submit : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('등록하기'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool get _canSubmit {
    if (_isSubmitting) return false;
    if (_nameController.text.trim().isEmpty) return false;
    if (!_isPrivate && _pinPosition == null) return false;
    return true;
  }
}
