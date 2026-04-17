import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/place_data.dart';
import '../../services/place_service.dart';

class PlaceEditPane extends StatefulWidget {
  final PlaceData place;
  final bool isDirectEdit;
  final VoidCallback onBack;
  final VoidCallback onCompleted;

  const PlaceEditPane({
    super.key,
    required this.place,
    this.isDirectEdit = false,
    required this.onBack,
    required this.onCompleted,
  });

  @override
  State<PlaceEditPane> createState() => _PlaceEditPaneState();
}

class _PlaceEditPaneState extends State<PlaceEditPane> {
  late final TextEditingController _nameController;
  LatLng? _newPosition;
  GoogleMapController? _mapController;
  File? _pickedImage;
  bool _isSubmitting = false;

  bool get _isGym => widget.place.type == 'gym';

  Color get _accent =>
      _isGym ? const Color(0xFF6750A4) : const Color(0xFFF57C00);

  LatLng? get _originalPosition {
    if (widget.place.latitude != null && widget.place.longitude != null) {
      return LatLng(widget.place.latitude!, widget.place.longitude!);
    }
    return null;
  }

  bool get _hasChanges {
    final nameChanged = _isGym
        ? _nameController.text.trim().isNotEmpty
        : _nameController.text.trim() != widget.place.name;
    return nameChanged || _newPosition != null || _pickedImage != null;
  }

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

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!_hasChanges || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    final newName = _nameController.text.trim();
    try {
      if (_isGym && !widget.isDirectEdit) {
        await PlaceService.createSuggestion(
          placeId: widget.place.id,
          name: newName.isNotEmpty ? newName : null,
          latitude: _newPosition?.latitude,
          longitude: _newPosition?.longitude,
          imagePath: _pickedImage?.path,
        );
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        _showSuccessDialog();
        widget.onCompleted();
      } else {
        await PlaceService.updatePlace(
          widget.place.id,
          name: newName.isNotEmpty && newName != widget.place.name
              ? newName
              : null,
          latitude: _newPosition?.latitude,
          longitude: _newPosition?.longitude,
          imagePath: _pickedImage?.path,
        );
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수정되었습니다')),
        );
        widget.onCompleted();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('요청에 실패했습니다. 다시 시도해주세요.')),
      );
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
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF6750A4).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  color: Color(0xFF6750A4), size: 32),
            ),
            const SizedBox(height: 16),
            const Text('제안이 접수되었습니다',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('운영자 검수 후 반영됩니다.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 16),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6750A4)),
              child: const Text('확인'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCoords = _originalPosition != null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
              Text(
                  widget.isDirectEdit
                      ? '암장 정보 수정'
                      : (_isGym ? '정보 수정 제안' : '암장 정보 수정'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            widget.isDirectEdit
                ? '즉시 반영됩니다'
                : (_isGym ? '검수 후 반영됩니다' : '🔒 개인 암장 · 즉시 반영됩니다'),
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.place.isPending && widget.place.type == 'gym')
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: const Text(
              '승인되기 전까지는 자유롭게 수정할 수 있어요. 승인된 이후에는 다른 분들도 쓰게 되므로, '
              '그때부터는 "정보 수정 제안"으로 요청해주시면 반영해드립니다.',
              style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.45),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text('대표 이미지',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _buildImageSection(),
                const SizedBox(height: 16),
                const Text('이름',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_isGym) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Text(widget.place.name,
                            style: const TextStyle(
                                fontSize: 14,
                                decoration: TextDecoration.lineThrough,
                                color: Colors.grey)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('현재',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.grey)),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Icon(Icons.arrow_downward,
                        size: 18, color: Colors.grey),
                  ),
                ],
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: _isGym ? '변경할 이름 입력' : '암장 이름',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                if (hasCoords) ...[
                  const Text('위치',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (_isGym)
                    Text('지도를 탭하여 올바른 위치를 지정하세요',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      child: Stack(
                        children: [
                          GoogleMap(
                            onMapCreated: (c) => _mapController = c,
                            initialCameraPosition: CameraPosition(
                              target: _originalPosition!,
                              zoom: 16,
                            ),
                            onTap: (point) =>
                                setState(() => _newPosition = point),
                            markers: {
                              if (_isGym)
                                Marker(
                                  markerId: const MarkerId('original'),
                                  position: _originalPosition!,
                                  icon: BitmapDescriptor.defaultMarkerWithHue(
                                      BitmapDescriptor.hueAzure),
                                ),
                              if (_isGym && _newPosition != null)
                                Marker(
                                  markerId: const MarkerId('suggest'),
                                  position: _newPosition!,
                                  icon: BitmapDescriptor.defaultMarkerWithHue(
                                      BitmapDescriptor.hueViolet),
                                ),
                              if (!_isGym)
                                Marker(
                                  markerId: const MarkerId('position'),
                                  position:
                                      _newPosition ?? _originalPosition!,
                                  icon: BitmapDescriptor.defaultMarkerWithHue(
                                      BitmapDescriptor.hueOrange),
                                ),
                            },
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
                              onZoomIn: () => _mapController
                                  ?.animateCamera(CameraUpdate.zoomIn()),
                              onZoomOut: () => _mapController
                                  ?.animateCamera(CameraUpdate.zoomOut()),
                            ),
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
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _hasChanges && !_isSubmitting ? _submit : null,
                style: FilledButton.styleFrom(backgroundColor: _accent),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isGym ? '수정 제안하기' : '수정하기'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageSection() {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: _buildImageBody(widget.place.coverImageUrl, _pickedImage),
    );
  }

  Widget _buildImageBody(String? currentUrl, File? pickedFile) {
    if (pickedFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(child: Image.file(pickedFile, fit: BoxFit.cover)),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => setState(() => _pickedImage = null),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (currentUrl != null) {
      return GestureDetector(
        onTap: _pickImage,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: currentUrl,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        '사진 변경',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
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

    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
              color: _accent.withValues(alpha: 0.4),
              width: 1.5,
              style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(12),
          color: _accent.withValues(alpha: 0.04),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt_outlined, size: 32, color: _accent),
              const SizedBox(height: 8),
              const Text(
                '이 암장에 아직 사진이 없어요',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '첫 대표 사진을 등록해 주세요',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt, color: Colors.white, size: 14),
                    SizedBox(width: 6),
                    Text('사진 선택',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
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
