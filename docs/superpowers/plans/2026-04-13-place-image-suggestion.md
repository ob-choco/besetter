# Place Image Suggestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add cover image suggestion to the `gym`-type place suggestion flow on mobile, extend the server suggestion endpoint to accept multipart images, and rename `image_url`/`thumbnail_url` → single `cover_image_url` across Place and PlaceSuggestion.

**Architecture:** Mobile Suggest sheet gains an "대표 이미지" section (overlay pattern when a cover image exists, CTA card when it doesn't). `PlaceService.createSuggestion` switches from JSON to multipart. Server `POST /places/suggestions` switches from Pydantic JSON body to `Form(...)` + `UploadFile` and writes the uploaded URL into `PlaceSuggestionChanges.cover_image_url`. On Place / PlaceSuggestionChanges, the legacy `image_url` field is renamed to `cover_image_url` and the separate `thumbnail_url` field is dropped entirely — list cards instead build thumbnail URLs at read time via the existing `/images/{blob}?type=<preset>` endpoint using the `toThumbnailUrl()` mobile helper.

**Tech Stack:** FastAPI (Python, Beanie ODM, Pydantic), Flutter (Dart, hooks_riverpod, cached_network_image, image_picker).

**Spec reference:** `docs/superpowers/specs/2026-04-13-place-image-suggestion-design.md`

**Spec ↔ code reconciliation:**
- Spec says `PlaceSuggestion.image_url` → `cover_image_url`. The actual field lives on the nested `PlaceSuggestionChanges` model (`services/api/app/models/place.py:76`). This plan renames `PlaceSuggestionChanges.image_url` → `PlaceSuggestionChanges.cover_image_url`.
- Spec says "DB 마이그레이션 없음." — no Mongo update scripts are run. Existing documents keep their old field names in storage; reads will simply see `None` for `cover_image_url` until overwritten. This is acceptable for the current development dataset.

---

## File Structure

**Server (`services/api`)**
- Modify `app/models/place.py` — rename fields on `Place` and `PlaceSuggestionChanges`, drop `thumbnail_url`.
- Modify `app/routers/places.py` — update `PlaceView`, `PlaceImageUploadResponse`, `place_to_view`, `_upload_place_image`, `create_place`, and rewrite `POST /places/suggestions` to multipart.
- Create `tests/routers/test_places.py` — unit test for `_upload_place_image` helper.

**Mobile (`apps/mobile`)**
- Modify `lib/models/place_data.dart` — rename `imageUrl` → `coverImageUrl`, remove `thumbnailUrl`.
- Modify `lib/widgets/editors/place_selection_sheet.dart` — update list card thumbnail source, add suggest image state / picker / reset, add image section UI with two visual states.
- Modify `lib/services/place_service.dart` — convert `createSuggestion` to multipart with optional `imagePath`.

---

## Task 1: Server — Rename `Place` cover image field, drop thumbnail

**Files:**
- Modify: `services/api/app/models/place.py:36-37`

- [ ] **Step 1: Update the `Place` document fields**

Replace the two lines defining `image_url` and `thumbnail_url` on the `Place` class (lines 36-37):

```python
    cover_image_url: Optional[str] = Field(None, description="대표 이미지 URL")
```

(Only one field. `thumbnail_url` is removed entirely.)

- [ ] **Step 2: Run pytest to make sure nothing unrelated breaks**

```bash
cd services/api && uv run pytest -x
```

Expected: PASS. (Places router code in `app/routers/places.py` still references the old names, but Python does not import-check field names until runtime — the existing test suite does not touch the places router so it should remain green. If it fails, stop and read the error rather than blindly fixing.)

- [ ] **Step 3: Commit**

```bash
git add services/api/app/models/place.py
git commit -m "refactor(api): rename Place.image_url to cover_image_url, drop thumbnail_url"
```

---

## Task 2: Server — Rename `PlaceSuggestionChanges.image_url`

**Files:**
- Modify: `services/api/app/models/place.py:70-76`

- [ ] **Step 1: Update the field on `PlaceSuggestionChanges`**

Replace line 76 inside the `PlaceSuggestionChanges` class:

```python
    cover_image_url: Optional[str] = Field(None, description="변경 제안된 대표 이미지 URL")
```

The rest of the class (`name`, `latitude`, `longitude`) is unchanged.

- [ ] **Step 2: Run pytest**

```bash
cd services/api && uv run pytest -x
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add services/api/app/models/place.py
git commit -m "refactor(api): rename PlaceSuggestionChanges.image_url to cover_image_url"
```

---

## Task 3: Server — Refactor `_upload_place_image` to return a single URL

**Files:**
- Modify: `services/api/app/routers/places.py:108-130`

- [ ] **Step 1: Replace the helper function body**

Replace the entire `_upload_place_image` function (lines 108-130) with:

```python
def _upload_place_image(content: bytes, file_ext: str) -> str:
    """Upload the place cover image to GCS and return its public URL."""
    unique_name = str(uuid.uuid4())
    blob = bucket.blob(f"place_images/{unique_name}{file_ext}")
    content_type = "image/png" if file_ext == ".png" else "image/jpeg"
    blob.upload_from_string(data=content, content_type=content_type)
    return f"{get_base_url()}/place_images/{unique_name}{file_ext}"
```

Note what's removed:
- The 200x200 thumbnail generation block (PIL open, `img.thumbnail((200, 200))`, second `bucket.blob` upload).
- The tuple return.

- [ ] **Step 2: Remove the now-unused `io` and `PILImage` imports if possible**

Check the top of `services/api/app/routers/places.py`:

```bash
cd services/api && python -c "import ast; tree = ast.parse(open('app/routers/places.py').read()); [print(n.names[0].name) for n in ast.walk(tree) if isinstance(n, (ast.Import, ast.ImportFrom))]"
```

If `io` and `PIL` (via `from PIL import Image as PILImage`) are no longer used anywhere else in the file, remove those import lines from lines 1-11. If they are still used (unlikely but possible), leave them.

- [ ] **Step 3: Write a unit test for the refactored helper**

Create `services/api/tests/routers/test_places.py`:

```python
from unittest.mock import MagicMock, patch

from tests.conftest import create_test_image


@patch("app.routers.places.bucket")
@patch("app.routers.places.get_base_url", return_value="https://example.com")
def test_upload_place_image_returns_single_url(mock_get_base_url, mock_bucket):
    """_upload_place_image uploads exactly one blob and returns its URL."""
    from app.routers.places import _upload_place_image

    mock_blob = MagicMock()
    mock_bucket.blob.return_value = mock_blob

    content = create_test_image(400, 400)
    url = _upload_place_image(content, ".jpg")

    # Exactly one blob creation (no thumbnail)
    assert mock_bucket.blob.call_count == 1
    call_path = mock_bucket.blob.call_args[0][0]
    assert call_path.startswith("place_images/")
    assert call_path.endswith(".jpg")

    # Exactly one upload_from_string call
    assert mock_blob.upload_from_string.call_count == 1

    # Returned URL is a string pointing at the same blob path
    assert isinstance(url, str)
    assert url == f"https://example.com/{call_path}"


@patch("app.routers.places.bucket")
@patch("app.routers.places.get_base_url", return_value="https://example.com")
def test_upload_place_image_uses_png_content_type(mock_get_base_url, mock_bucket):
    """PNG files should be uploaded with image/png content type."""
    from app.routers.places import _upload_place_image

    mock_blob = MagicMock()
    mock_bucket.blob.return_value = mock_blob

    _upload_place_image(b"fake png bytes", ".png")

    kwargs = mock_blob.upload_from_string.call_args.kwargs
    assert kwargs["content_type"] == "image/png"
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd services/api && uv run pytest tests/routers/test_places.py -v
```

Expected: 2 passing. If it fails with `ModuleNotFoundError` on `app.routers.places`, it's because the router still references the old `image_url`/`thumbnail_url` fields on `Place`. That's fixed in Task 4 — temporarily skip this test run and pick it up at the end of Task 4 instead.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/places.py services/api/tests/routers/test_places.py
git commit -m "refactor(api): _upload_place_image returns single url, drop thumbnail generation"
```

---

## Task 4: Server — Update `PlaceView`, `PlaceImageUploadResponse`, `place_to_view`, `create_place`

**Files:**
- Modify: `services/api/app/routers/places.py:63-100`, `:133-179`

- [ ] **Step 1: Update `PlaceView`**

Replace the `image_url` / `thumbnail_url` pair inside `PlaceView` (lines 71-72):

```python
    cover_image_url: Optional[str]
```

- [ ] **Step 2: Update `PlaceImageUploadResponse`**

Replace both fields in `PlaceImageUploadResponse` (lines 80-81):

```python
    cover_image_url: str
```

- [ ] **Step 3: Update `place_to_view`**

Replace the `image_url=...` / `thumbnail_url=...` pair (lines 96-97) with:

```python
        cover_image_url=place.cover_image_url,
```

- [ ] **Step 4: Update `create_place` endpoint**

In `create_place` (lines 133-179), make these edits:

Replace the pre-upload initialization block (lines 155-156):

```python
    cover_image_url = None
```

Replace the upload call (line 165):

```python
        cover_image_url = _upload_place_image(content, file_ext)
```

Replace the `Place(...)` construction's image fields (lines 171-172):

```python
        cover_image_url=cover_image_url,
```

(The surrounding `name=`, `normalized_name=`, `type=`, `created_by=`, `created_at=` lines stay the same.)

- [ ] **Step 5: Run the suite**

```bash
cd services/api && uv run pytest -x
```

Expected: PASS, including the `test_places.py` tests from Task 3 that may have been deferred.

- [ ] **Step 6: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "refactor(api): use cover_image_url in PlaceView and create_place"
```

---

## Task 5: Server — Convert `POST /places/suggestions` to multipart

**Files:**
- Modify: `services/api/app/routers/places.py:45-50`, `:263-294`

- [ ] **Step 1: Delete the now-unused `CreatePlaceSuggestionRequest` model**

Remove lines 45-50 (`class CreatePlaceSuggestionRequest(BaseModel): ...`). The new multipart endpoint reads form fields directly.

- [ ] **Step 2: Rewrite the suggestion endpoint**

Replace `create_place_suggestion` (lines 263-294) with:

```python
@router.post("/suggestions", status_code=status.HTTP_201_CREATED, response_model=PlaceSuggestionView)
async def create_place_suggestion(
    place_id: str = Form(...),
    name: Optional[str] = Form(None),
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    image: Optional[UploadFile] = File(None),
    current_user: User = Depends(get_current_user),
):
    place = await Place.get(place_id)
    if place is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Place not found")

    if place.type == "private-gym":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Suggestions are not allowed for private-gym places",
        )

    # Upload image if provided
    cover_image_url: Optional[str] = None
    if image is not None and image.filename:
        file_ext = os.path.splitext(image.filename)[1].lower()
        if file_ext not in (".jpg", ".jpeg", ".png"):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Only jpg/jpeg/png files are supported",
            )
        content = await image.read()
        cover_image_url = _upload_place_image(content, file_ext)

    # Reject no-op suggestions
    if name is None and latitude is None and longitude is None and cover_image_url is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least one of name, latitude/longitude, or image must be provided",
        )

    changes = PlaceSuggestionChanges(
        name=name,
        latitude=latitude,
        longitude=longitude,
        cover_image_url=cover_image_url,
    )

    suggestion = PlaceSuggestion(
        place_id=place.id,
        requested_by=current_user.id,
        status="pending",
        changes=changes,
        created_at=datetime.now(tz=timezone.utc),
    )
    created = await suggestion.save()

    return PlaceSuggestionView(
        id=created.id,
        place_id=created.place_id,
        requested_by=created.requested_by,
        status=created.status,
        changes=created.changes,
        created_at=created.created_at,
    )
```

Note: the form field is `place_id` (snake_case), matching the other form fields in this router. The mobile client in Task 8 must send it as `place_id` in its `fields` map — not `placeId`.

- [ ] **Step 3: Run pytest**

```bash
cd services/api && uv run pytest -x
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): accept multipart image on POST /places/suggestions"
```

---

## Task 6: Mobile — Rename `PlaceData.imageUrl` → `coverImageUrl`, remove `thumbnailUrl`

**Files:**
- Modify: `apps/mobile/lib/models/place_data.dart`

- [ ] **Step 1: Rewrite `PlaceData`**

Replace the entire contents of `apps/mobile/lib/models/place_data.dart` with:

```dart
class PlaceData {
  final String id;
  final String name;
  final String type; // "gym" | "private-gym"
  final double? latitude;
  final double? longitude;
  final String? coverImageUrl;
  final String createdBy;
  final double? distance;

  PlaceData({
    required this.id,
    required this.name,
    required this.type,
    this.latitude,
    this.longitude,
    this.coverImageUrl,
    required this.createdBy,
    this.distance,
  });

  factory PlaceData.fromJson(Map<String, dynamic> json) {
    return PlaceData(
      id: json['_id'],
      name: json['name'],
      type: json['type'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      coverImageUrl: json['coverImageUrl'],
      createdBy: json['createdBy'],
      distance: json['distance']?.toDouble(),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze to find all broken references**

```bash
cd apps/mobile && flutter analyze
```

Expected: FAIL with errors pointing at:
- `lib/widgets/editors/place_selection_sheet.dart:435` (`place.thumbnailUrl != null`)
- `lib/widgets/editors/place_selection_sheet.dart:437` (`imageUrl: place.thumbnailUrl!`)

Note the exact set of error locations — Task 7 fixes them.

- [ ] **Step 3: Do not commit yet**

This task leaves the tree in a broken state intentionally. Task 7 is the companion fix that ships in the same commit:

```bash
# Do not commit here.
```

---

## Task 7: Mobile — Fix list card thumbnail to use `coverImageUrl` via `toThumbnailUrl`

**Files:**
- Modify: `apps/mobile/lib/widgets/editors/place_selection_sheet.dart:430-445`

- [ ] **Step 1: Verify `toThumbnailUrl` is already imported**

Run:

```bash
cd apps/mobile && grep -n "thumbnail_url" lib/widgets/editors/place_selection_sheet.dart
```

Expected: no matches. The file currently imports from `cached_network_image` and `image_picker` but not the `toThumbnailUrl` helper. Add this import near the top of the file (alongside the other `../` imports):

```dart
import '../../utils/thumbnail_url.dart';
```

- [ ] **Step 2: Update the list card thumbnail rendering**

Find the existing block around line 435 that looks like:

```dart
                        child: place.thumbnailUrl != null
                            ? CachedNetworkImage(
                                imageUrl: place.thumbnailUrl!,
```

Replace both references:

```dart
                        child: place.coverImageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: toThumbnailUrl(place.coverImageUrl!, 's100'),
```

(`s100` is the 100x100 square crop preset defined in `services/api/app/services/thumbnail.py`'s `PRESETS`. Confirm the preset name exists by grepping that file if uncertain: `grep -n "s100\|w400" services/api/app/services/thumbnail.py` — should print the `PRESETS` dict entries.)

- [ ] **Step 3: Run flutter analyze**

```bash
cd apps/mobile && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Commit Tasks 6 + 7 together**

```bash
git add apps/mobile/lib/models/place_data.dart apps/mobile/lib/widgets/editors/place_selection_sheet.dart
git commit -m "refactor(mobile): rename PlaceData.imageUrl to coverImageUrl, use dynamic thumbnail endpoint"
```

---

## Task 8: Mobile — Extend `PlaceService.createSuggestion` to multipart

**Files:**
- Modify: `apps/mobile/lib/services/place_service.dart:94-111`

- [ ] **Step 1: Replace `createSuggestion`**

Replace the entire `createSuggestion` function (lines 94-111) with:

```dart
  static Future<void> createSuggestion({
    required String placeId,
    String? name,
    double? latitude,
    double? longitude,
    String? imagePath,
  }) async {
    final fields = <String, String>{
      'place_id': placeId,
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
    };
    final response = await AuthorizedHttpClient.multipartPost(
      '/places/suggestions',
      imagePath,
      fieldName: 'image',
      fields: fields,
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to create suggestion. Status: ${response.statusCode}');
    }
  }
```

Note: `multipartPost` accepts a `null` file path and will simply omit the file from the request — so existing callers that pass no `imagePath` still work.

- [ ] **Step 2: Run flutter analyze**

```bash
cd apps/mobile && flutter analyze
```

Expected: `No issues found!` (the existing caller in `place_selection_sheet.dart:230-235` passes `placeId`, `name`, `latitude`, `longitude` as named args and those still type-check).

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/services/place_service.dart
git commit -m "feat(mobile): createSuggestion uses multipart with optional imagePath"
```

---

## Task 9: Mobile — Add suggest image state, picker, reset, and `_hasSuggestChanges` update

**Files:**
- Modify: `apps/mobile/lib/widgets/editors/place_selection_sheet.dart`
  - State vars block (around lines 67-74)
  - `_goToSuggest` (around line 153)
  - `_pickRegisterImage` area (around line 183) — add sibling `_pickSuggestImage`
  - `_hasSuggestChanges` getter (around lines 233-238)
  - `_submitSuggest` (around lines 240-275)

- [ ] **Step 1: Add `_suggestImage` state field**

In the `_PlaceSelectionSheetState` state variables block (just after `GoogleMapController? _suggestMapController;` at line 74), add:

```dart
  File? _suggestImage;
```

(`File` is already imported via `dart:io` indirectly through `_registerImage`; verify by grepping — `grep -n "import 'dart:io'" apps/mobile/lib/widgets/editors/place_selection_sheet.dart`. If it's missing, add `import 'dart:io';` to the top of the file alongside the other `dart:` imports.)

- [ ] **Step 2: Reset `_suggestImage` in `_goToSuggest`**

In `_goToSuggest` (around line 153-158), after `_suggestNewPosition = null;`, add:

```dart
    _suggestImage = null;
```

So the block becomes:

```dart
  void _goToSuggest(PlaceData place) {
    _suggestPlace = place;
    _suggestNameController.text = place.type == 'gym' ? '' : place.name;
    _suggestNewPosition = null;
    _suggestImage = null;
    setState(() => _mode = _SheetMode.suggest);
  }
```

- [ ] **Step 3: Add `_pickSuggestImage` helper**

Just after `_pickRegisterImage` (ends around line 189), add a sibling:

```dart
  Future<void> _pickSuggestImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() => _suggestImage = File(picked.path));
    }
  }
```

- [ ] **Step 4: Extend `_hasSuggestChanges`**

Replace the `_hasSuggestChanges` getter (lines 233-238) with:

```dart
  bool get _hasSuggestChanges {
    final nameChanged = _isGymSuggest
        ? _suggestNameController.text.trim().isNotEmpty
        : _suggestNameController.text.trim() != _suggestPlace?.name;
    return nameChanged || _suggestNewPosition != null || _suggestImage != null;
  }
```

- [ ] **Step 5: Wire image into `_submitSuggest` (gym path only)**

In `_submitSuggest` around lines 246-256 (the `_isGymSuggest` branch), update the `PlaceService.createSuggestion` call to pass `imagePath`:

```dart
      if (_isGymSuggest) {
        await PlaceService.createSuggestion(
          placeId: _suggestPlace!.id,
          name: newName.isNotEmpty ? newName : null,
          latitude: _suggestNewPosition?.latitude,
          longitude: _suggestNewPosition?.longitude,
          imagePath: _suggestImage?.path,
        );
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _mode = _SheetMode.select;
            _suggestImage = null;
          });
          _showSuccessDialog();
        }
      } else {
```

(The `else` branch for private-gym `updatePlace` is unchanged — images are out of scope for private places.)

- [ ] **Step 6: Run flutter analyze**

```bash
cd apps/mobile && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/widgets/editors/place_selection_sheet.dart
git commit -m "feat(mobile): track suggest cover image state and include in submission"
```

---

## Task 10: Mobile — Add image section UI to suggest mode (`_buildSuggestMode`)

**Files:**
- Modify: `apps/mobile/lib/widgets/editors/place_selection_sheet.dart` — `_buildSuggestMode()` around lines 689-833

- [ ] **Step 1: Insert the image section at the top of the scrolling column**

Inside `_buildSuggestMode`, locate the `SingleChildScrollView` → `Column` (around line 713-716). Immediately after `const SizedBox(height: 8),` and BEFORE the existing `const Text('이름', ...)` line, insert an image section that renders only when `_isGymSuggest` is true:

```dart
                if (_isGymSuggest) ...[
                  const Text('대표 이미지', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _buildSuggestImageSection(),
                  const SizedBox(height: 16),
                ],
```

- [ ] **Step 2: Add the `_buildSuggestImageSection` method**

Add a new method on `_PlaceSelectionSheetState` just after `_buildSuggestMode` (before `// ==================== Common Widgets ====================` around line 835):

```dart
  Widget _buildSuggestImageSection() {
    final currentUrl = _suggestPlace?.coverImageUrl;
    final pickedFile = _suggestImage;

    // State: user has picked a new image (overrides both "has original" and "empty")
    if (pickedFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: 120,
              child: Image.file(pickedFile, fit: BoxFit.cover),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => setState(() => _suggestImage = null),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // State 1: existing cover image — overlay "사진 변경" button
    if (currentUrl != null) {
      return GestureDetector(
        onTap: _pickSuggestImage,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: 120,
                child: CachedNetworkImage(
                  imageUrl: currentUrl,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
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

    // State 2: no existing image — CTA card encouraging first photo
    return GestureDetector(
      onTap: _pickSuggestImage,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          border: Border.all(color: _suggestAccentColor.withValues(alpha: 0.4), width: 1.5, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(12),
          color: _suggestAccentColor.withValues(alpha: 0.04),
        ),
        child: Column(
          children: [
            Icon(Icons.camera_alt_outlined, size: 32, color: _suggestAccentColor),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _suggestAccentColor,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.camera_alt, color: Colors.white, size: 14),
                  SizedBox(width: 6),
                  Text('사진 선택', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 3: Run flutter analyze**

```bash
cd apps/mobile && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Format**

```bash
cd apps/mobile && dart format lib/widgets/editors/place_selection_sheet.dart
```

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/editors/place_selection_sheet.dart
git commit -m "feat(mobile): add cover image suggest section with overlay and empty-state CTA"
```

---

## Task 11: Final verification

- [ ] **Step 1: Full server test suite**

```bash
cd services/api && uv run pytest
```

Expected: all passing, including the new `test_places.py`.

- [ ] **Step 2: Full mobile static analysis**

```bash
cd apps/mobile && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Manual checks that cannot be verified by code**

Document these for the user to try on-device; they are not automatable in this plan:

- Open Suggest mode on a gym **with** a cover image → image renders as background with the "사진 변경" pill at bottom-right.
- Tap the image → picker opens, selecting a photo replaces the preview with `Image.file` and shows the close `X`.
- Open Suggest mode on a gym **without** a cover image → CTA card with the "이 암장에 아직 사진이 없어요" message and "사진 선택" button.
- Submit with only an image (no name/location change) → submit button becomes enabled, POST succeeds, success dialog shows.
- Submit name + image together → POST succeeds.
- Select list card thumbnails still render for gyms that have a cover image (now through the dynamic `/images/{blob}?type=s100` endpoint).
