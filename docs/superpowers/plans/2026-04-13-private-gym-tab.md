# Private Gym Tab & Edit Pane Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Private 암장을 별도 탭으로 분리하고, private 편집 화면(suggest/edit 패널)을 `place_edit_pane.dart`로 추출하며, private 편집에서도 이미지 수정을 즉시 반영한다.

**Architecture:** 백엔드는 `GET /places/my-private` 신설 + `nearby`/`instant-search`는 `type=gym`으로 제한 + `PUT /places/{id}` multipart 전환. Flutter는 place selection sheet에 `[근처]`/`[내 프라이빗]` 탭을 추가하고 suggest/edit 패널을 별도 파일로 추출한 뒤 private 경로에도 이미지 섹션을 노출한다.

**Tech Stack:** FastAPI + Beanie + MongoDB (services/api), Flutter + http package (apps/mobile), pytest, flutter analyze

**Spec:** `docs/superpowers/specs/2026-04-13-private-gym-tab-design.md`

---

## File Structure

### Backend

- **Modify** `services/api/app/routers/places.py`
  - `get_nearby_places`: add `"type": "gym"` filter, remove private filtering loop
  - `instant_search_places`: add `"type": "gym"` filter, remove private filtering loop
  - New `get_my_private_places` endpoint
  - `update_place`: JSON body → multipart (`Form`/`File`), support image upload
  - Remove (or leave unused) `UpdatePlaceRequest` — kept for safety, not imported elsewhere
- **Modify** `services/api/tests/routers/test_places.py` — add unit test for `_upload_place_image` already exists; add no new endpoint tests (no integration fixture exists in this repo)

### Frontend

- **Create** `apps/mobile/lib/widgets/editors/place_edit_pane.dart`
  - `PlaceEditPane` StatefulWidget — unified suggest(gym)/edit(private) pane
  - `PlaceEditResult` small value class for callback
- **Modify** `apps/mobile/lib/services/place_service.dart`
  - Add `getMyPrivatePlaces()`
  - Change `updatePlace` to multipart PUT + optional `imagePath`
- **Modify** `apps/mobile/lib/widgets/editors/place_selection_sheet.dart`
  - Remove `_buildSuggestMode`, `_buildSuggestImageSection`, `_buildSuggestImageBody`, `_submitSuggest`, `_showSuccessDialog`, suggest-related state — now owned by `PlaceEditPane`
  - Add `_SelectTab` enum and tab UI
  - Split `_places` into `_nearbyPlaces`, `_privatePlaces`, `_searchResults`
  - Load both lists on init

---

## Task 1: Backend — filter private from nearby and instant-search

**Files:**
- Modify: `services/api/app/routers/places.py:153-204`
- Verify: `services/api/tests/routers/test_places.py`

**Context:** `get_nearby_places` builds a raw pymongo `$nearSphere` dict and then loops over candidates with `if place.type == "private-gym" and str(place.created_by) != str(current_user.id): continue`. With the new tab separation we always exclude private from both endpoints, so the loop becomes dead weight and the query can filter at the DB layer. `instant_search_places` has the same pattern.

- [ ] **Step 1: Edit `get_nearby_places` to filter `type=gym` at the query level**

Replace lines 161-182 (the full function body after the signature) with:

```python
    # $nearSphere with 2dsphere index — returns sorted by distance
    query_filter = {
        "type": "gym",
        "location": {
            "$nearSphere": {
                "$geometry": {
                    "type": "Point",
                    "coordinates": [longitude, latitude],
                },
                "$maxDistance": radius,
            }
        },
    }

    candidates = await Place.find(query_filter).to_list()

    results: List[PlaceView] = []
    for place in candidates:
        distance = (
            haversine_distance(latitude, longitude, place.latitude, place.longitude)
            if place.latitude and place.longitude
            else None
        )
        results.append(
            place_to_view(place, distance=round(distance, 2) if distance else None)
        )

    return results
```

- [ ] **Step 2: Edit `instant_search_places` to filter `type=gym` and drop the private loop**

Replace lines 185-204 with:

```python
@router.get("/instant-search", response_model=List[PlaceView])
async def instant_search_places(
    query: str = Query(..., description="검색어"),
    current_user: User = Depends(get_current_user),
):
    normalized_query = normalize_name(query)
    if len(normalized_query) < 2:
        return []

    candidates = await Place.find(
        {
            "type": "gym",
            "normalizedName": {
                "$regex": re.escape(normalized_query),
                "$options": "i",
            },
        }
    ).limit(20).to_list()

    return [place_to_view(place) for place in candidates]
```

- [ ] **Step 3: Run syntax + existing tests to confirm no regression**

```bash
cd /Users/htjo/besetter/services/api
python3 -m py_compile app/routers/places.py
pytest tests/routers/test_places.py -q
```

Expected: py_compile silent, pytest `2 passed` (or whatever the current count is — all green, no new failures).

- [ ] **Step 4: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/places.py
git commit -m "$(cat <<'EOF'
feat(api): exclude private gyms from nearby/instant-search

With the new private-gym tab, place selection shows private gyms in a
dedicated list, so nearby and instant-search no longer need to include
them. Filter type=gym at the query level and drop the post-query
private filtering loop.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Backend — add GET /places/my-private

**Files:**
- Modify: `services/api/app/routers/places.py` (add new endpoint after `instant_search_places`)

**Context:** `PlaceSelectionSheet` will call this on open to populate the `[내 프라이빗]` tab. No pagination; typical user has a handful of private places.

- [ ] **Step 1: Add the endpoint after `instant_search_places`**

Insert the following function immediately after the `instant_search_places` function (before `update_place`):

```python
@router.get("/my-private", response_model=List[PlaceView])
async def get_my_private_places(
    current_user: User = Depends(get_current_user),
):
    """Return every private-gym place owned by the current user, newest first."""
    candidates = await Place.find(
        Place.type == "private-gym",
        Place.created_by == current_user.id,
    ).sort(-Place.created_at).to_list()

    return [place_to_view(place) for place in candidates]
```

Note on ordering: Beanie's `.sort(-Place.created_at)` uses the field expression and will translate the field name via the alias generator (stored as `createdAt`). This is the alias-aware path, not a raw dict.

- [ ] **Step 2: Verify syntax**

```bash
cd /Users/htjo/besetter/services/api
python3 -m py_compile app/routers/places.py
```

Expected: no output.

- [ ] **Step 3: Run existing tests to confirm no import regression**

```bash
cd /Users/htjo/besetter/services/api
pytest tests/routers/test_places.py -q
```

Expected: all existing tests still pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/places.py
git commit -m "$(cat <<'EOF'
feat(api): add GET /places/my-private endpoint

Returns every private-gym place owned by the current user, sorted
newest first. Used by the mobile place selection sheet to populate
the dedicated private gym tab.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Backend — convert PUT /places/{id} to multipart with image upload

**Files:**
- Modify: `services/api/app/routers/places.py:207-231` (`update_place` + `UpdatePlaceRequest`)

**Context:** Currently `update_place` receives `UpdatePlaceRequest` as JSON body (name/latitude/longitude). To support image editing for private gyms, we convert it to multipart form like `create_place`. The only client caller is `PlaceService.updatePlace` (grep-confirmed in spec). Old `UpdatePlaceRequest` becomes dead code; delete it.

- [ ] **Step 1: Delete `UpdatePlaceRequest` class**

Remove lines 36-42:

```python
class UpdatePlaceRequest(BaseModel):
    model_config = model_config

    name: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
```

- [ ] **Step 2: Rewrite `update_place` to use multipart form and support image**

Replace the current `update_place` function (at ~line 207) with:

```python
@router.put("/{place_id}", response_model=PlaceView)
async def update_place(
    place_id: str,
    name: Optional[str] = Form(None),
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    image: Optional[UploadFile] = File(None),
    current_user: User = Depends(get_current_user),
):
    place = await Place.get(place_id)
    if place is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Place not found")

    if place.type != "private-gym" or str(place.created_by) != str(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not allowed to update this place",
        )

    if name is not None:
        place.name = name
        place.normalized_name = normalize_name(name)

    new_lat = latitude if latitude is not None else place.latitude
    new_lng = longitude if longitude is not None else place.longitude
    place.set_location_from(new_lat, new_lng)

    if image is not None and image.filename:
        file_ext = os.path.splitext(image.filename)[1].lower()
        if file_ext not in (".jpg", ".jpeg", ".png"):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Only jpg/jpeg/png files are supported",
            )
        content = await image.read()
        place.cover_image_url = _upload_place_image(content, file_ext)

    await place.save()
    return place_to_view(place)
```

- [ ] **Step 3: Verify syntax + existing tests**

```bash
cd /Users/htjo/besetter/services/api
python3 -m py_compile app/routers/places.py
pytest tests/routers/test_places.py -q
```

Expected: py_compile silent, pytest all green.

- [ ] **Step 4: Commit**

```bash
cd /Users/htjo/besetter
git add services/api/app/routers/places.py
git commit -m "$(cat <<'EOF'
feat(api): PUT /places/{id} accepts multipart with optional image

Private gym edit now supports changing the cover image. Converts the
endpoint from a JSON body (UpdatePlaceRequest) to multipart Form/File
params, mirroring POST /places. Only caller is mobile
PlaceService.updatePlace, so no backwards-compat shim needed.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Flutter — PlaceService.getMyPrivatePlaces + multipart updatePlace

**Files:**
- Modify: `apps/mobile/lib/services/place_service.dart:74-92` (updatePlace) and add new method

**Context:** New endpoint consumer + multipart PUT. `AuthorizedHttpClient.multipartRequest` already supports arbitrary method (http_client.dart:178-210) — we use it with `method: 'PUT'`. `multipartPost` is used by `createPlace` for reference.

- [ ] **Step 1: Add `getMyPrivatePlaces` method**

Add the following method in `PlaceService`, immediately before `updatePlace`:

```dart
  static Future<List<PlaceData>> getMyPrivatePlaces() async {
    final response = await AuthorizedHttpClient.get('/places/my-private');

    if (response.statusCode == 200) {
      final List<dynamic> data =
          jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      return data.map((e) => PlaceData.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception(
        'Failed to fetch my private places. Status: ${response.statusCode}');
  }
```

Note: Use the same `AuthorizedHttpClient.get` + `jsonDecode(utf8.decode(...))` pattern the file uses elsewhere (see `getNearbyPlaces` / `instantSearch` for the exact form). If one of those is already `getNearbyPlaces`, mirror its parse code exactly.

- [ ] **Step 2: Rewrite `updatePlace` as a multipart PUT with optional image**

Replace the existing `updatePlace` (lines 74-92) with:

```dart
  static Future<PlaceData> updatePlace(
    String placeId, {
    String? name,
    double? latitude,
    double? longitude,
    String? imagePath,
  }) async {
    final fields = <String, String>{
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
    };
    final response = await AuthorizedHttpClient.multipartRequest(
      '/places/$placeId',
      imagePath,
      fieldName: 'image',
      fields: fields,
      method: 'PUT',
    );

    if (response.statusCode == 200) {
      return PlaceData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    }
    throw Exception('Failed to update place. Status: ${response.statusCode}');
  }
```

- [ ] **Step 3: Run flutter analyze**

```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze
```

Expected: "No issues found!" (or unchanged pre-existing issues — no new issues in `place_service.dart`).

- [ ] **Step 4: Commit**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/services/place_service.dart
git commit -m "$(cat <<'EOF'
feat(mobile): PlaceService.getMyPrivatePlaces + multipart updatePlace

Add GET /places/my-private consumer and switch updatePlace to a
multipart PUT so private gym edits can upload a new cover image.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Flutter — extract PlaceEditPane (no behavior change)

**Files:**
- Create: `apps/mobile/lib/widgets/editors/place_edit_pane.dart`
- Modify: `apps/mobile/lib/widgets/editors/place_selection_sheet.dart` (remove suggest-mode code, mount `PlaceEditPane`)

**Context:** Move `_buildSuggestMode`, `_buildSuggestImageSection`, `_buildSuggestImageBody`, `_submitSuggest`, `_showSuccessDialog`, `_suggestAccentColor`, `_suggestOriginalPosition`, `_hasSuggestChanges`, `_isGymSuggest`, `_pickSuggestImage`, and related state (`_suggestPlace`, `_suggestNameController`, `_suggestNewPosition`, `_suggestMapController`, `_suggestImage`, `_isSubmitting`) from `_PlaceSelectionSheetState` to a new `_PlaceEditPaneState`. The new widget wraps the same UI, exposes `onBack` and `onCompleted`. Behavior for both gym(suggest) and private(edit) paths is identical to before — image section remains gym-only for now (Task 6 fixes).

The `_MapZoomControls` class currently at the bottom of `place_selection_sheet.dart` (lines 1166-1205) should also move into `place_edit_pane.dart` since it's only used by the edit pane.

- [ ] **Step 1: Create `place_edit_pane.dart` with `PlaceEditPane` widget**

Create `apps/mobile/lib/widgets/editors/place_edit_pane.dart` with this content:

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/place_data.dart';
import '../../services/place_service.dart';

class PlaceEditResult {
  final PlaceData? updatedPlace;
  final bool suggestionSubmitted;
  const PlaceEditResult({this.updatedPlace, this.suggestionSubmitted = false});
}

class PlaceEditPane extends StatefulWidget {
  final PlaceData place;
  final VoidCallback onBack;
  final ValueChanged<PlaceEditResult> onCompleted;

  const PlaceEditPane({
    super.key,
    required this.place,
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
      if (_isGym) {
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
        widget.onCompleted(const PlaceEditResult(suggestionSubmitted: true));
      } else {
        final updated = await PlaceService.updatePlace(
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
        widget.onCompleted(PlaceEditResult(updatedPlace: updated));
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
              Text(_isGym ? '정보 수정 제안' : '암장 정보 수정',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _isGym ? '검수 후 반영됩니다' : '🔒 개인 암장 · 즉시 반영됩니다',
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
                if (_isGym) ...[
                  const Text('대표 이미지',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _buildImageSection(),
                  const SizedBox(height: 16),
                ],
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
```

**Note:** Image section is still wrapped with `if (_isGym)` in this task. Private path exposing the image section happens in Task 6. This keeps Task 5 a pure refactor with zero behavior change.

- [ ] **Step 2: Update `place_selection_sheet.dart` to import and use `PlaceEditPane`**

Add import at top (after existing imports):

```dart
import 'place_edit_pane.dart';
```

Remove `_SheetMode.suggest` and related — change enum to:

```dart
enum _SheetMode { select, register, edit }
```

Remove these fields from `_PlaceSelectionSheetState`:

```dart
// --- Suggest mode state ---
PlaceData? _suggestPlace;
final TextEditingController _suggestNameController = TextEditingController();
LatLng? _suggestNewPosition;
GoogleMapController? _suggestMapController;
File? _suggestImage;
```

Replace with a single field:

```dart
PlaceData? _editTarget;
```

Remove the `_suggestNameController.dispose();` line in `dispose()`.

Change `_goToSuggest` to `_goToEdit`:

```dart
void _goToEdit(PlaceData place) {
  setState(() {
    _editTarget = place;
    _mode = _SheetMode.edit;
  });
}
```

Update the caller in `_buildPlaceItem` (inside the `if (isSelected) ...` block) from `_goToSuggest(place)` to `_goToEdit(place)`.

Remove all these methods from `_PlaceSelectionSheetState` (they've moved to `PlaceEditPane`):
- `_isGymSuggest` getter
- `_suggestAccentColor` getter
- `_suggestOriginalPosition` getter
- `_hasSuggestChanges` getter
- `_pickSuggestImage`
- `_submitSuggest`
- `_showSuccessDialog`
- `_buildSuggestMode`
- `_buildSuggestImageSection`
- `_buildSuggestImageBody`

Remove the bottom `_MapZoomControls` class (moved to `place_edit_pane.dart`).

Update the `build` method's switch to mount `PlaceEditPane`:

```dart
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
            onCompleted: (_) => _goBackToSelect(),
          );
      }
    },
  );
}
```

Remove now-unused imports at the top of `place_selection_sheet.dart`:
- `import 'package:flutter/foundation.dart';`
- `import 'package:flutter/gestures.dart';`
- `import 'package:google_maps_flutter/google_maps_flutter.dart';` — **keep** if register mode still uses it (it does — `_registerMapController`, `LatLng`)
- Check `dart:io` — still needed for `_registerImage` field
- Check `image_picker` — still needed for `_pickRegisterImage`

Keep these — only the map/gesture/foundation imports might become unused. Run `flutter analyze` to confirm.

- [ ] **Step 3: Run flutter analyze**

```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze
```

Expected: no new errors. Unused import warnings should be addressed by removing the specific imports flagged.

- [ ] **Step 4: Smoke-verify behavior mentally**

Confirm these three flows still compile and route correctly:
- Gym suggest: tap selected gym → "정보 수정 제안" → gym suggest path in `PlaceEditPane` with image section visible
- Private edit: tap selected private → "암장 정보 수정" → private edit path in `PlaceEditPane` without image section (unchanged from pre-refactor)
- Back button: `onBack` callback returns to select mode

- [ ] **Step 5: Commit**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/widgets/editors/place_edit_pane.dart apps/mobile/lib/widgets/editors/place_selection_sheet.dart
git commit -m "$(cat <<'EOF'
refactor(mobile): extract PlaceEditPane from place_selection_sheet

Move the suggest/edit pane (~400 lines including _MapZoomControls)
to a dedicated file. Pure refactor — no behavior change. Prepares
ground for adding image edit support to the private gym path and
the new private gym tab.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Flutter — enable image edit on the private gym path

**Files:**
- Modify: `apps/mobile/lib/widgets/editors/place_edit_pane.dart`

**Context:** Task 5 preserved the `if (_isGym)` wrapper around the image section so the refactor was zero-behavior-change. Now remove that wrapper so private gyms can also edit their cover image. The submit path already passes `imagePath: _pickedImage?.path` to `PlaceService.updatePlace` (added in Task 5), so nothing else needs to change.

- [ ] **Step 1: Remove the `_isGym` guard around the image section**

In `_PlaceEditPaneState.build`, change the block currently reading:

```dart
if (_isGym) ...[
  const Text('대표 이미지',
      style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600)),
  const SizedBox(height: 8),
  _buildImageSection(),
  const SizedBox(height: 16),
],
```

to:

```dart
const Text('대표 이미지',
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
const SizedBox(height: 8),
_buildImageSection(),
const SizedBox(height: 16),
```

(Remove the `if (_isGym) ...[` wrapper and its closing `]`.)

- [ ] **Step 2: Run flutter analyze**

```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze
```

Expected: "No issues found!" (or unchanged pre-existing issues).

- [ ] **Step 3: Commit**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/widgets/editors/place_edit_pane.dart
git commit -m "$(cat <<'EOF'
feat(mobile): allow editing private gym cover image

The image section was previously gated on _isGym. With the multipart
updatePlace endpoint, private gyms can now upload a new cover image
from the same pane.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Flutter — add tab UI and private gym loading to place selection sheet

**Files:**
- Modify: `apps/mobile/lib/widgets/editors/place_selection_sheet.dart`

**Context:** Final piece. Split `_places` into three lists, add tab state, load private gyms on init alongside nearby, and render a tab row above the list when search is inactive.

- [ ] **Step 1: Add `_SelectTab` enum below `_SheetMode`**

Add after the existing `enum _SheetMode { select, register, edit }`:

```dart
enum _SelectTab { nearby, private }
```

- [ ] **Step 2: Replace `_places` / `_isLoading` / `_isSearchMode` with tab-aware state**

Replace these fields:

```dart
List<PlaceData> _places = [];
bool _isLoading = false;
bool _isSearchMode = false;
```

with:

```dart
_SelectTab _activeTab = _SelectTab.nearby;
List<PlaceData> _nearbyPlaces = [];
List<PlaceData> _privatePlaces = [];
List<PlaceData> _searchResults = [];
bool _loadingNearby = false;
bool _loadingPrivate = false;
bool _loadingSearch = false;
bool _isSearchMode = false;
```

- [ ] **Step 3: Replace `_loadNearbyPlaces` body to use the new field; add `_loadMyPrivatePlaces`**

Replace `_loadNearbyPlaces`:

```dart
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
```

Add below it:

```dart
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
```

- [ ] **Step 4: Fire both loads in parallel from `initState`**

Replace the current `initState` body:

```dart
@override
void initState() {
  super.initState();
  if (widget.latitude != null && widget.longitude != null) {
    _registerPinPosition = LatLng(widget.latitude!, widget.longitude!);
  }
  _loadNearbyPlaces();
  _loadMyPrivatePlaces();
}
```

- [ ] **Step 5: Update `_onSearchChanged` to use `_searchResults`**

Replace the existing `_onSearchChanged`:

```dart
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
```

- [ ] **Step 6: Rewrite `_buildSelectMode` to render tabs and active-tab list**

Replace the entire `_buildSelectMode` method with:

```dart
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
```

- [ ] **Step 7: Add `_buildTabBar` and `_buildListArea` helpers**

Add these methods inside `_PlaceSelectionSheetState` (above `_buildPlaceItem`):

```dart
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
```

- [ ] **Step 8: Remove the old inline `📍 근처 암장` header emitted from the listview builder**

The prior `_buildSelectMode` injected a `'📍 근처 암장'` label at index 0 of the list. The tab bar now replaces that label. Confirm no stray header-emitting code remains in the file after step 6's replacement. If any `Text('📍 근처 암장'...)` or `Text('🔍 ... 근처 암장'...)` remains outside `_tabButton`, delete it.

- [ ] **Step 9: Run flutter analyze**

```bash
cd /Users/htjo/besetter/apps/mobile && flutter analyze
```

Expected: "No issues found!" (or unchanged pre-existing issues).

- [ ] **Step 10: Commit**

```bash
cd /Users/htjo/besetter
git add apps/mobile/lib/widgets/editors/place_selection_sheet.dart
git commit -m "$(cat <<'EOF'
feat(mobile): add private gym tab to place selection sheet

Split the place list into [근처 암장] and [내 프라이빗] tabs, loaded in
parallel on sheet open. Search (gym-only per updated backend) hides the
tabs and shows a single result list. Empty private tab shows text-only
message — the existing "새 암장 등록하기" button remains available at the
bottom of the sheet.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Summary

- Tasks 1-3: Backend API changes (filter, new endpoint, multipart update)
- Task 4: PlaceService mirror of backend changes
- Task 5: Pure refactor to extract `PlaceEditPane` (zero behavior change)
- Task 6: Enable private gym image edit (one-line guard removal)
- Task 7: Tab UI + private loading wire-up

Each task produces a working, testable state. Backend tasks can ship independently of frontend tasks (nearby/search simply stop returning private, which the current client already tolerates since private gyms have a separate badge that won't trigger anything broken).
