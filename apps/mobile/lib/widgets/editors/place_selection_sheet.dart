import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/place_data.dart';
import '../../services/place_service.dart';
import '../../utils/thumbnail_url.dart';
import 'place_edit_pane.dart';

enum _SheetMode { select, register, edit }

enum _SelectTab { nearby, private }

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
  _SelectTab _activeTab = _SelectTab.nearby;
  List<PlaceData> _nearbyPlaces = [];
  List<PlaceData> _privatePlaces = [];
  List<PlaceData> _searchResults = [];
  bool _loadingNearby = false;
  bool _loadingPrivate = false;
  bool _loadingSearch = false;
  bool _isSearchMode = false;

  // --- Register mode state ---
  final TextEditingController _registerNameController = TextEditingController();
  LatLng? _registerPinPosition;
  bool _isPrivate = false;
  bool _isSubmitting = false;
  File? _registerImage;
  GoogleMapController? _registerMapController;

  // --- Edit mode state ---
  PlaceData? _editTarget;

  @override
  void initState() {
    super.initState();
    if (widget.latitude != null && widget.longitude != null) {
      _registerPinPosition = LatLng(widget.latitude!, widget.longitude!);
    }
    _loadNearbyPlaces();
    _loadMyPrivatePlaces();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _registerNameController.dispose();
    super.dispose();
  }

  // ==================== Select Mode ====================

  Future<void> _loadNearbyPlaces() async {
    if (widget.latitude == null || widget.longitude == null) return;
    setState(() => _loadingNearby = true);
    try {
      final places = await PlaceService.getNearbyPlaces(
        latitude: widget.latitude!,
        longitude: widget.longitude!,
        radius: 5000,
      );
      if (mounted) {
        setState(() {
          _nearbyPlaces = places;
          _loadingNearby = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingNearby = false);
    }
  }

  Future<void> _loadMyPrivatePlaces() async {
    setState(() => _loadingPrivate = true);
    try {
      final places = await PlaceService.getMyPrivatePlaces();
      if (mounted) {
        setState(() {
          _privatePlaces = places;
          _loadingPrivate = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingPrivate = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _isSearchMode = false;
        _searchResults = [];
        _loadingSearch = false;
      });
      return;
    }
    _debounce = Timer(const Duration(seconds: 1), () async {
      setState(() {
        _isSearchMode = true;
        _loadingSearch = true;
      });
      try {
        final results = await PlaceService.instantSearch(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _loadingSearch = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _loadingSearch = false);
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

  void _goToEdit(PlaceData place) {
    setState(() {
      _editTarget = place;
      _mode = _SheetMode.edit;
    });
  }

  void _goBackToSelect() {
    setState(() => _mode = _SheetMode.select);
  }

  // ==================== Register Mode ====================

  bool get _showRegisterMap {
    return _registerPinPosition != null ||
        (widget.latitude != null && widget.longitude != null);
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
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
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

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        switch (_mode) {
          case _SheetMode.select:
            return _buildSelectMode(scrollController);
          case _SheetMode.register:
            return _buildRegisterMode();
          case _SheetMode.edit:
            return PlaceEditPane(
              place: _editTarget!,
              onBack: _goBackToSelect,
              onCompleted: _goBackToSelect,
            );
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
          child: Text('암장 선택',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: '암장 이름으로 검색',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        if (!_isSearchMode) _buildTabBar(),
        Expanded(child: _buildListArea(scrollController)),
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
                    Text('새 암장 등록하기',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700])),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _tabButton(
              label: '📍 근처 암장',
              active: _activeTab == _SelectTab.nearby,
              onTap: () => setState(() => _activeTab = _SelectTab.nearby),
            ),
          ),
          Expanded(
            child: _tabButton(
              label: '🔒 내 프라이빗',
              active: _activeTab == _SelectTab.private,
              onTap: () => setState(() => _activeTab = _SelectTab.private),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? const Color(0xFF6750A4) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? const Color(0xFF6750A4) : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListArea(ScrollController scrollController) {
    if (_isSearchMode) {
      if (_loadingSearch) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_searchResults.isEmpty) {
        return Center(
          child: Text('검색 결과가 없습니다',
              style: TextStyle(color: Colors.grey[500])),
        );
      }
      return ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) => _buildPlaceItem(_searchResults[index]),
      );
    }

    if (_activeTab == _SelectTab.nearby) {
      if (_loadingNearby) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_nearbyPlaces.isEmpty) {
        return Center(
          child: Text('근처에 등록된 암장이 없습니다',
              style: TextStyle(color: Colors.grey[500])),
        );
      }
      return ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _nearbyPlaces.length,
        itemBuilder: (context, index) => _buildPlaceItem(_nearbyPlaces[index]),
      );
    }

    // private tab
    if (_loadingPrivate) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_privatePlaces.isEmpty) {
      return Center(
        child: Text('등록된 프라이빗 암장이 없습니다',
            style: TextStyle(color: Colors.grey[500])),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _privatePlaces.length,
      itemBuilder: (context, index) => _buildPlaceItem(_privatePlaces[index]),
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: place.coverImageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: toThumbnailUrl(
                                    place.coverImageUrl!, 's100'),
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.store,
                                        color: Colors.grey)),
                                errorWidget: (_, __, ___) => Container(
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.store,
                                        color: Colors.grey)),
                              )
                            : Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.store,
                                    color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isPrivate)
                                const Text('🔒 ',
                                    style: TextStyle(fontSize: 13)),
                              Flexible(
                                child: Text(place.name,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          if (place.distance != null) ...[
                            const SizedBox(height: 2),
                            Text(_formatDistance(place.distance),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600])),
                          ],
                          if (isPrivate) ...[
                            const SizedBox(height: 2),
                            Text('나만 보임',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.orange[700])),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
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
                                    : Colors.green[800]),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6750A4)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('선택됨',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6750A4))),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                if (isSelected) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _goToEdit(place),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('✏️ ', style: TextStyle(fontSize: 12)),
                        Text('정보 수정 제안',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6750A4),
                                decoration: TextDecoration.underline)),
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
              IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _goBackToSelect),
              const Text('새 암장 등록',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('새로운 클라이밍 암장을 등록합니다',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
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
                                child: Image.file(_registerImage!,
                                    fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _registerImage = null),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 18),
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
                            border: Border.all(
                                color: Colors.grey[300]!,
                                style: BorderStyle.solid),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[50],
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.camera_alt,
                                  size: 28, color: Colors.grey[400]),
                              const SizedBox(height: 4),
                              Text('대표 사진 선택 (선택)',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey[500])),
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
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                if (_showRegisterMap) ...[
                  const Text('위치 선택',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('지도를 탭하여 위치를 지정하세요',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      child: Stack(
                        children: [
                          GoogleMap(
                            onMapCreated: (c) => _registerMapController = c,
                            initialCameraPosition: CameraPosition(
                              target: _registerMapCenter,
                              zoom: 16,
                            ),
                            onTap: (point) =>
                                setState(() => _registerPinPosition = point),
                            markers: _registerPinPosition != null
                                ? {
                                    Marker(
                                      markerId: const MarkerId('register'),
                                      position: _registerPinPosition!,
                                    ),
                                  }
                                : {},
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            gestureRecognizers: <Factory<
                                OneSequenceGestureRecognizer>>{
                              Factory<OneSequenceGestureRecognizer>(
                                () => EagerGestureRecognizer(),
                              ),
                            },
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: _MapZoomControls(
                              onZoomIn: () => _registerMapController
                                  ?.animateCamera(CameraUpdate.zoomIn()),
                              onZoomOut: () => _registerMapController
                                  ?.animateCamera(CameraUpdate.zoomOut()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('개인 암장',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text('나만 볼 수 있는 암장',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
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
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('등록하기'),
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
        width: 36,
        height: 4,
        decoration: BoxDecoration(
            color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _MapZoomControls({required this.onZoomIn, required this.onZoomOut});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onZoomIn,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            child: const SizedBox(
              width: 32,
              height: 32,
              child: Icon(Icons.add, size: 18, color: Color(0xFF2C2F30)),
            ),
          ),
          Container(width: 32, height: 1, color: const Color(0xFFE0E0E0)),
          InkWell(
            onTap: onZoomOut,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(6)),
            child: const SizedBox(
              width: 32,
              height: 32,
              child: Icon(Icons.remove, size: 18, color: Color(0xFF2C2F30)),
            ),
          ),
        ],
      ),
    );
  }
}
