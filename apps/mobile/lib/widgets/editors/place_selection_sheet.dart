import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place_data.dart';
import '../../services/place_service.dart';

enum _SheetMode { select, register, suggest }

class PlaceSelectionSheet extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final PlaceData? currentPlace;

  const PlaceSelectionSheet({
    super.key,
    this.latitude,
    this.longitude,
    this.currentPlace,
  });

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
  // --- Shared state ---
  _SheetMode _mode = _SheetMode.select;

  // --- Select mode state ---
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<PlaceData> _places = [];
  bool _isLoading = false;
  bool _isSearchMode = false;

  // --- Register mode state ---
  final TextEditingController _registerNameController = TextEditingController();
  LatLng? _registerPinPosition;
  bool _isPrivate = false;
  bool _isSubmitting = false;
  File? _registerImage;

  // --- Suggest mode state ---
  PlaceData? _suggestPlace;
  final TextEditingController _suggestNameController = TextEditingController();
  LatLng? _suggestNewPosition;

  @override
  void initState() {
    super.initState();
    if (widget.latitude != null && widget.longitude != null) {
      _registerPinPosition = LatLng(widget.latitude!, widget.longitude!);
    }
    _loadNearbyPlaces();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _registerNameController.dispose();
    _suggestNameController.dispose();
    super.dispose();
  }

  // ==================== Select Mode ====================

  Future<void> _loadNearbyPlaces() async {
    if (widget.latitude == null || widget.longitude == null) return;
    setState(() => _isLoading = true);
    try {
      final places = await PlaceService.getNearbyPlaces(
        latitude: widget.latitude!,
        longitude: widget.longitude!,
        radius: 5000,
      );
      if (mounted) setState(() { _places = places; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
      setState(() { _isSearchMode = true; _isLoading = true; });
      try {
        final results = await PlaceService.instantSearch(query);
        if (mounted) setState(() { _places = results; _isLoading = false; });
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '';
    if (distance < 1000) return '${distance.round()}m';
    return '${(distance / 1000).toStringAsFixed(1)}km';
  }

  void _goToRegister() {
    setState(() => _mode = _SheetMode.register);
  }

  void _goToSuggest(PlaceData place) {
    _suggestPlace = place;
    _suggestNameController.text = place.type == 'gym' ? '' : place.name;
    _suggestNewPosition = null;
    setState(() => _mode = _SheetMode.suggest);
  }

  void _goBackToSelect() {
    setState(() => _mode = _SheetMode.select);
  }

  // ==================== Register Mode ====================

  bool get _showRegisterMap {
    if (_isPrivate) return false;
    return _registerPinPosition != null || (widget.latitude != null && widget.longitude != null);
  }

  LatLng get _registerMapCenter {
    if (_registerPinPosition != null) return _registerPinPosition!;
    return const LatLng(37.5665, 126.9780);
  }

  bool get _canRegister {
    if (_isSubmitting) return false;
    if (_registerNameController.text.trim().isEmpty) return false;
    if (!_isPrivate && _registerPinPosition == null) return false;
    return true;
  }

  Future<void> _pickRegisterImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() => _registerImage = File(picked.path));
    }
  }

  Future<void> _submitRegister() async {
    final name = _registerNameController.text.trim();
    if (name.isEmpty) return;
    if (!_isPrivate && _registerPinPosition == null) return;

    setState(() => _isSubmitting = true);
    try {
      final place = await PlaceService.createPlace(
        name: name,
        type: _isPrivate ? 'private-gym' : 'gym',
        latitude: _registerPinPosition?.latitude,
        longitude: _registerPinPosition?.longitude,
        imagePath: _registerImage?.path,
      );
      if (mounted) Navigator.pop(context, place);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('등록에 실패했습니다. 다시 시도해주세요.')),
        );
      }
    }
  }

  // ==================== Suggest Mode ====================

  bool get _isGymSuggest => _suggestPlace?.type == 'gym';

  Color get _suggestAccentColor =>
      _isGymSuggest ? const Color(0xFF6750A4) : const Color(0xFFF57C00);

  LatLng? get _suggestOriginalPosition {
    if (_suggestPlace?.latitude != null && _suggestPlace?.longitude != null) {
      return LatLng(_suggestPlace!.latitude!, _suggestPlace!.longitude!);
    }
    return null;
  }

  bool get _hasSuggestChanges {
    final nameChanged = _isGymSuggest
        ? _suggestNameController.text.trim().isNotEmpty
        : _suggestNameController.text.trim() != _suggestPlace?.name;
    return nameChanged || _suggestNewPosition != null;
  }

  Future<void> _submitSuggest() async {
    if (!_hasSuggestChanges || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    final newName = _suggestNameController.text.trim();
    try {
      if (_isGymSuggest) {
        await PlaceService.createSuggestion(
          placeId: _suggestPlace!.id,
          name: newName.isNotEmpty ? newName : null,
          latitude: _suggestNewPosition?.latitude,
          longitude: _suggestNewPosition?.longitude,
        );
        if (mounted) {
          setState(() { _isSubmitting = false; _mode = _SheetMode.select; });
          _showSuccessDialog();
        }
      } else {
        await PlaceService.updatePlace(
          _suggestPlace!.id,
          name: newName.isNotEmpty && newName != _suggestPlace!.name ? newName : null,
          latitude: _suggestNewPosition?.latitude,
          longitude: _suggestNewPosition?.longitude,
        );
        if (mounted) {
          setState(() { _isSubmitting = false; _mode = _SheetMode.select; });
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF6750A4).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Color(0xFF6750A4), size: 32),
            ),
            const SizedBox(height: 16),
            const Text('제안이 접수되었습니다', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('운영자 검수 후 반영됩니다.', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 16),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6750A4)),
              child: const Text('확인'),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        switch (_mode) {
          case _SheetMode.select:
            return _buildSelectMode(scrollController);
          case _SheetMode.register:
            return _buildRegisterMode();
          case _SheetMode.suggest:
            return _buildSuggestMode();
        }
      },
    );
  }

  // ==================== Select Mode UI ====================

  Widget _buildSelectMode(ScrollController scrollController) {
    return Column(
      children: [
        _buildDragHandle(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('암장 선택', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: '암장 이름으로 검색',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
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
                      itemCount: _places.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          if (!_isSearchMode) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 8, bottom: 4),
                              child: Text('📍 근처 암장', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                            );
                          }
                          return const SizedBox.shrink();
                        }
                        return _buildPlaceItem(_places[index - 1]);
                      },
                    ),
        ),
        const Divider(height: 1),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: _goToRegister,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[400]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 18, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Text('새 암장 등록하기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
                color: isSelected ? const Color(0xFF6750A4) : Colors.grey.withValues(alpha: 0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 48, height: 48,
                        child: place.thumbnailUrl != null
                            ? CachedNetworkImage(
                                imageUrl: place.thumbnailUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: Colors.grey[200], child: const Icon(Icons.store, color: Colors.grey)),
                                errorWidget: (_, __, ___) => Container(color: Colors.grey[200], child: const Icon(Icons.store, color: Colors.grey)),
                              )
                            : Container(color: Colors.grey[200], child: const Icon(Icons.store, color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isPrivate) const Text('🔒 ', style: TextStyle(fontSize: 13)),
                              Flexible(
                                child: Text(place.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          if (place.distance != null) ...[
                            const SizedBox(height: 2),
                            Text(_formatDistance(place.distance), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                          if (isPrivate) ...[
                            const SizedBox(height: 2),
                            Text('나만 보임', style: TextStyle(fontSize: 11, color: Colors.orange[700])),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isPrivate ? Colors.orange.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isPrivate ? 'private' : 'gym',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isPrivate ? Colors.orange[800] : Colors.green[800]),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6750A4).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('선택됨', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6750A4))),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                if (isSelected) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _goToSuggest(place),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('✏️ ', style: TextStyle(fontSize: 12)),
                        Text('정보 수정 제안', style: TextStyle(fontSize: 12, color: Color(0xFF6750A4), decoration: TextDecoration.underline)),
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

  // ==================== Register Mode UI ====================

  Widget _buildRegisterMode() {
    return Column(
      children: [
        _buildDragHandle(),
        // Title row with back button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBackToSelect),
              const Text('새 암장 등록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('새로운 클라이밍 암장을 등록합니다', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                // 이미지 선택
                GestureDetector(
                  onTap: _pickRegisterImage,
                  child: _registerImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                height: 120,
                                child: Image.file(_registerImage!, fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: 8, right: 8,
                                child: GestureDetector(
                                  onTap: () => setState(() => _registerImage = null),
                                  child: Container(
                                    width: 28, height: 28,
                                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[50],
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.camera_alt, size: 28, color: Colors.grey[400]),
                              const SizedBox(height: 4),
                              Text('대표 사진 선택 (선택)', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _registerNameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '암장 이름',
                    hintText: '암장 이름을 입력하세요',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                if (_showRegisterMap) ...[
                  const Text('위치 선택', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('지도를 탭하여 위치를 지정하세요', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _registerMapCenter,
                          initialZoom: 16,
                          onTap: (_, point) => setState(() => _registerPinPosition = point),
                        ),
                        children: [
                          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.besetter.app'),
                          if (_registerPinPosition != null)
                            MarkerLayer(markers: [
                              Marker(point: _registerPinPosition!, width: 40, height: 40, child: const Icon(Icons.location_pin, color: Colors.red, size: 40)),
                            ]),
                          RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('개인 암장', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text('나만 볼 수 있는 암장', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    value: _isPrivate,
                    onChanged: (v) => setState(() => _isPrivate = v),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canRegister ? _submitRegister : null,
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('등록하기'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== Suggest Mode UI ====================

  Widget _buildSuggestMode() {
    final hasCoords = _suggestOriginalPosition != null;

    return Column(
      children: [
        _buildDragHandle(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBackToSelect),
              Text(_isGymSuggest ? '정보 수정 제안' : '암장 정보 수정', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _isGymSuggest ? '검수 후 반영됩니다' : '🔒 개인 암장 · 즉시 반영됩니다',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text('이름', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_isGymSuggest) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Text(_suggestPlace!.name, style: const TextStyle(fontSize: 14, decoration: TextDecoration.lineThrough, color: Colors.grey)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                          child: const Text('현재', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Icon(Icons.arrow_downward, size: 18, color: Colors.grey),
                  ),
                ],
                TextField(
                  controller: _suggestNameController,
                  decoration: InputDecoration(
                    hintText: _isGymSuggest ? '변경할 이름 입력' : '암장 이름',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                if (hasCoords) ...[
                  const Text('위치', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (_isGymSuggest)
                    Text('지도를 탭하여 올바른 위치를 지정하세요', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _suggestOriginalPosition!,
                          initialZoom: 16,
                          onTap: (_, point) => setState(() => _suggestNewPosition = point),
                        ),
                        children: [
                          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.besetter.app'),
                          MarkerLayer(markers: [
                            if (_isGymSuggest)
                              Marker(point: _suggestOriginalPosition!, width: 40, height: 40, child: const Icon(Icons.location_pin, color: Colors.grey, size: 40)),
                            if (_isGymSuggest && _suggestNewPosition != null)
                              Marker(point: _suggestNewPosition!, width: 40, height: 40, child: Icon(Icons.location_pin, color: _suggestAccentColor, size: 40)),
                            if (!_isGymSuggest)
                              Marker(point: _suggestNewPosition ?? _suggestOriginalPosition!, width: 40, height: 40, child: Icon(Icons.location_pin, color: _suggestAccentColor, size: 40)),
                          ]),
                          RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _hasSuggestChanges && !_isSubmitting ? _submitSuggest : null,
                style: FilledButton.styleFrom(backgroundColor: _suggestAccentColor),
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isGymSuggest ? '수정 제안하기' : '수정하기'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== Common Widgets ====================

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Container(
        width: 36, height: 4,
        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}
