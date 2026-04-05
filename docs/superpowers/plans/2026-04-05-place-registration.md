# Place Registration & Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a user-generated climbing gym (Place) database with GPS-based nearby search, name-based instant search, and place suggestion workflow.

**Architecture:** FastAPI backend with Beanie/MongoDB for data, GCS for image storage. Flutter mobile client with flutter_map for OSM maps, EXIF extraction for GPS, and Riverpod for state. The gym info flow in SprayWallEditorPage changes from free-text gymName to selecting/creating a Place entity via placeId.

**Tech Stack:** FastAPI, Beanie, MongoDB Atlas Search (nGram), Google Cloud Storage, sharp (thumbnail), Flutter, flutter_map, latlong2, exif, Riverpod

---

## File Structure

### Backend (services/api/)

| File | Responsibility |
|------|---------------|
| `app/models/place.py` | **Create** — Place document + PlaceSuggestion document |
| `app/routers/places.py` | **Create** — All place API endpoints (nearby, instant-search, CRUD, image, suggestions) |
| `app/models/image.py` | **Modify** — Add optional `place_id` field |
| `app/models/hold_polygon.py` | **Modify** — Add optional `place_id` field |
| `app/main.py` | **Modify** — Register Place + PlaceSuggestion models and router |

### Frontend (apps/mobile/)

| File | Responsibility |
|------|---------------|
| `lib/models/place_data.dart` | **Create** — Place model for client |
| `lib/services/place_service.dart` | **Create** — Place API calls (nearby, search, create, update, suggest, image) |
| `lib/services/exif_service.dart` | **Create** — EXIF GPS extraction from image files |
| `lib/widgets/editors/place_selection_sheet.dart` | **Create** — Bottom sheet: nearby list + search + new registration |
| `lib/widgets/editors/place_registration_sheet.dart` | **Create** — Bottom sheet: name + OSM map + private toggle + image |
| `lib/widgets/editors/place_suggestion_sheet.dart` | **Create** — Bottom sheet: edit suggestion (gym) or direct edit (private-gym) |
| `lib/widgets/editors/spray_wall_information_input_widget.dart` | **Modify** — Replace gymName text input with place selection |
| `lib/pages/editors/spray_wall_editor_page.dart` | **Modify** — Replace gymName state with placeId, update save flow |

---

## Task 1: Backend — Place & PlaceSuggestion Models

**Files:**
- Create: `services/api/app/models/place.py`
- Modify: `services/api/app/main.py`

- [ ] **Step 1: Create Place and PlaceSuggestion Beanie documents**

```python
# services/api/app/models/place.py
from beanie import Document
from typing import Optional
from beanie.odm.fields import PydanticObjectId
from pydantic import BaseModel, Field
from datetime import datetime
from pymongo import IndexModel, ASCENDING, GEOSPHERE
import re

from . import model_config


def normalize_name(name: str) -> str:
    """Remove spaces, symbols, special characters and lowercase."""
    return re.sub(r'[^a-zA-Z0-9가-힣ぁ-んァ-ヶ一-龠]', '', name).lower()


class PlaceChanges(BaseModel):
    model_config = model_config

    name: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    image_url: Optional[str] = None


class Place(Document):
    model_config = model_config

    name: str = Field(..., description="암장 이름")
    normalized_name: str = Field("", description="검색용 정규화된 이름")
    type: str = Field("gym", description="gym | private-gym")
    latitude: Optional[float] = Field(None, description="위도")
    longitude: Optional[float] = Field(None, description="경도")
    image_url: Optional[str] = Field(None, description="대표 이미지 URL")
    thumbnail_url: Optional[str] = Field(None, description="썸네일 URL")
    created_by: PydanticObjectId = Field(..., description="최초 등록 userId")
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "places"
        indexes = [
            IndexModel([("latitude", ASCENDING), ("longitude", ASCENDING)]),
            IndexModel([("created_by", ASCENDING)]),
            IndexModel([("normalized_name", ASCENDING)]),
        ]

    def set_normalized_name(self):
        self.normalized_name = normalize_name(self.name)


class PlaceSuggestion(Document):
    model_config = model_config

    place_id: PydanticObjectId = Field(..., description="대상 place")
    requested_by: PydanticObjectId = Field(..., description="제안자 userId")
    status: str = Field("pending", description="pending | approved | rejected")
    changes: PlaceChanges = Field(..., description="변경 요청 내용")
    created_at: datetime = Field(default_factory=datetime.utcnow)
    read_at: Optional[datetime] = Field(None, description="운영자 열람 시각")
    reviewed_at: Optional[datetime] = Field(None, description="승인/거절 시각")

    class Settings:
        name = "placeSuggestions"
        indexes = [
            IndexModel([("place_id", ASCENDING)]),
            IndexModel([("status", ASCENDING)]),
        ]
```

- [ ] **Step 2: Register models in main.py**

Add imports and register in `init_beanie`:

```python
# In services/api/app/main.py — add to imports:
from app.models.place import Place as PlaceModel, PlaceSuggestion as PlaceSuggestionModel

# In init_beanie call, add to document_models list:
document_models=[
    OpenIdNonceModel, UserModel, HoldPolygonModel, ImageModel, RouteModel,
    PlaceModel, PlaceSuggestionModel,
],
```

- [ ] **Step 3: Verify — run the server locally**

```bash
cd services/api && python -m app.main
```

Expected: Server starts without errors, collections created in MongoDB.

- [ ] **Step 4: Commit**

```bash
git add services/api/app/models/place.py services/api/app/main.py
git commit -m "feat(api): add Place and PlaceSuggestion models"
```

---

## Task 2: Backend — POST /places & GET /places/nearby

**Files:**
- Create: `services/api/app/routers/places.py`
- Modify: `services/api/app/main.py`

- [ ] **Step 1: Create places router with POST and GET /nearby**

```python
# services/api/app/routers/places.py
from datetime import datetime
from math import radians, cos, sin, asin, sqrt
from typing import Optional, List
from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from pydantic import BaseModel, Field
from beanie.odm.fields import PydanticObjectId

from app.dependencies import get_current_user
from app.models.user import User
from app.models.place import Place, PlaceSuggestion, PlaceChanges, normalize_name
from app.models import model_config

import uuid
from PIL import Image as PILImage
import io

from app.core.gcs import get_base_url, bucket


router = APIRouter(prefix="/places", tags=["places"])


# --- Request/Response schemas ---

class CreatePlaceRequest(BaseModel):
    model_config = model_config
    name: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    type: str = "gym"


class PlaceView(BaseModel):
    model_config = model_config
    id: PydanticObjectId
    name: str
    type: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    image_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    created_by: PydanticObjectId
    distance: Optional[float] = None


class PlaceSuggestionView(BaseModel):
    model_config = model_config
    id: PydanticObjectId
    place_id: PydanticObjectId
    requested_by: PydanticObjectId
    status: str
    changes: PlaceChanges
    created_at: datetime


class CreatePlaceSuggestionRequest(BaseModel):
    model_config = model_config
    place_id: str
    changes: PlaceChanges


class UpdatePlaceRequest(BaseModel):
    model_config = model_config
    name: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None


# --- Helpers ---

def haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance in meters between two GPS coordinates."""
    R = 6371000  # Earth radius in meters
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    return R * 2 * asin(sqrt(a))


# --- Endpoints ---

@router.post("", status_code=status.HTTP_201_CREATED, response_model=PlaceView)
async def create_place(
    req: CreatePlaceRequest,
    current_user: User = Depends(get_current_user),
):
    if req.type == "gym" and (req.latitude is None or req.longitude is None):
        raise HTTPException(status_code=400, detail="gym 타입은 좌표가 필수입니다")

    if req.type not in ("gym", "private-gym"):
        raise HTTPException(status_code=400, detail="유효하지 않은 타입입니다")

    place = Place(
        name=req.name,
        normalized_name=normalize_name(req.name),
        type=req.type,
        latitude=req.latitude,
        longitude=req.longitude,
        created_by=current_user.id,
    )
    await place.insert()

    return PlaceView(
        id=place.id,
        name=place.name,
        type=place.type,
        latitude=place.latitude,
        longitude=place.longitude,
        image_url=place.image_url,
        thumbnail_url=place.thumbnail_url,
        created_by=place.created_by,
    )


@router.get("/nearby", response_model=List[PlaceView])
async def get_nearby_places(
    latitude: float,
    longitude: float,
    radius: float = 100,
    current_user: User = Depends(get_current_user),
):
    # Rough bounding box filter (degree ≈ 111km at equator)
    degree_offset = radius / 111000
    query = {
        "latitude": {"$gte": latitude - degree_offset, "$lte": latitude + degree_offset},
        "longitude": {"$gte": longitude - degree_offset, "$lte": longitude + degree_offset},
        "$or": [
            {"type": "gym"},
            {"type": "private-gym", "created_by": current_user.id},
        ],
    }

    places = await Place.find(query).to_list()

    results = []
    for p in places:
        if p.latitude is None or p.longitude is None:
            continue
        dist = haversine(latitude, longitude, p.latitude, p.longitude)
        if dist <= radius:
            results.append(PlaceView(
                id=p.id,
                name=p.name,
                type=p.type,
                latitude=p.latitude,
                longitude=p.longitude,
                image_url=p.image_url,
                thumbnail_url=p.thumbnail_url,
                created_by=p.created_by,
                distance=round(dist, 1),
            ))

    results.sort(key=lambda x: x.distance or 0)
    return results
```

- [ ] **Step 2: Register the router in main.py**

```python
# In services/api/app/main.py — add import:
from app.routers import places

# Add router:
app.include_router(places.router)
```

- [ ] **Step 3: Commit**

```bash
git add services/api/app/routers/places.py services/api/app/main.py
git commit -m "feat(api): add POST /places and GET /places/nearby endpoints"
```

---

## Task 3: Backend — GET /places/instant-search

**Files:**
- Modify: `services/api/app/routers/places.py`

- [ ] **Step 1: Add instant-search endpoint**

Append to `services/api/app/routers/places.py`:

```python
@router.get("/instant-search", response_model=List[PlaceView])
async def instant_search_places(
    query: str,
    current_user: User = Depends(get_current_user),
):
    normalized_query = normalize_name(query)
    if len(normalized_query) < 2:
        return []

    # Use regex for nGram-like infix matching
    # (Atlas Search nGram index can replace this later for better performance)
    search_filter = {
        "normalized_name": {"$regex": normalized_query, "$options": "i"},
        "$or": [
            {"type": "gym"},
            {"type": "private-gym", "created_by": current_user.id},
        ],
    }

    places = await Place.find(search_filter).limit(20).to_list()

    return [
        PlaceView(
            id=p.id,
            name=p.name,
            type=p.type,
            latitude=p.latitude,
            longitude=p.longitude,
            image_url=p.image_url,
            thumbnail_url=p.thumbnail_url,
            created_by=p.created_by,
        )
        for p in places
    ]
```

Note: This uses regex initially. When Atlas Search nGram index is configured, replace with `$search` aggregate pipeline for better performance.

- [ ] **Step 2: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): add GET /places/instant-search endpoint"
```

---

## Task 4: Backend — PUT /places/:id & POST /place-suggestions

**Files:**
- Modify: `services/api/app/routers/places.py`

- [ ] **Step 1: Add PUT /places/:id for private-gym direct edit**

Append to `services/api/app/routers/places.py`:

```python
@router.put("/{place_id}", response_model=PlaceView)
async def update_place(
    place_id: str,
    req: UpdatePlaceRequest,
    current_user: User = Depends(get_current_user),
):
    place = await Place.get(ObjectId(place_id))
    if not place:
        raise HTTPException(status_code=404, detail="암장을 찾을 수 없습니다")

    if place.type != "private-gym" or place.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="개인 암장만 직접 수정할 수 있습니다")

    if req.name is not None:
        place.name = req.name
        place.normalized_name = normalize_name(req.name)
    if req.latitude is not None:
        place.latitude = req.latitude
    if req.longitude is not None:
        place.longitude = req.longitude

    await place.save()

    return PlaceView(
        id=place.id,
        name=place.name,
        type=place.type,
        latitude=place.latitude,
        longitude=place.longitude,
        image_url=place.image_url,
        thumbnail_url=place.thumbnail_url,
        created_by=place.created_by,
    )
```

- [ ] **Step 2: Add POST /place-suggestions**

Append to `services/api/app/routers/places.py`:

```python
@router.post("/suggestions", status_code=status.HTTP_201_CREATED, response_model=PlaceSuggestionView)
async def create_place_suggestion(
    req: CreatePlaceSuggestionRequest,
    current_user: User = Depends(get_current_user),
):
    place = await Place.get(ObjectId(req.place_id))
    if not place:
        raise HTTPException(status_code=404, detail="암장을 찾을 수 없습니다")

    if place.type != "gym":
        raise HTTPException(status_code=400, detail="공개 암장만 수정 제안이 가능합니다")

    suggestion = PlaceSuggestion(
        place_id=ObjectId(req.place_id),
        requested_by=current_user.id,
        changes=req.changes,
    )
    await suggestion.insert()

    return PlaceSuggestionView(
        id=suggestion.id,
        place_id=suggestion.place_id,
        requested_by=suggestion.requested_by,
        status=suggestion.status,
        changes=suggestion.changes,
        created_at=suggestion.created_at,
    )
```

- [ ] **Step 3: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): add PUT /places/:id and POST /places/suggestions"
```

---

## Task 5: Backend — POST /places/:id/image

**Files:**
- Modify: `services/api/app/routers/places.py`

- [ ] **Step 1: Add image upload endpoint with thumbnail generation**

Add to imports at top of `services/api/app/routers/places.py`:

```python
import uuid
from PIL import Image as PILImage
import io
from app.core.gcs import get_base_url, bucket
```

Append endpoint:

```python
@router.post("/{place_id}/image", response_model=dict)
async def upload_place_image(
    place_id: str,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    place = await Place.get(ObjectId(place_id))
    if not place:
        raise HTTPException(status_code=404, detail="암장을 찾을 수 없습니다")

    # Permission check
    if place.type == "private-gym" and place.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="권한이 없습니다")

    # gym type: only allow if no image exists (otherwise use suggestion)
    if place.type == "gym" and place.image_url is not None:
        raise HTTPException(status_code=400, detail="이미 이미지가 있습니다. 수정 제안을 이용해주세요.")

    import os
    file_ext = os.path.splitext(file.filename)[1].lower()
    if file_ext not in (".jpg", ".jpeg", ".png"):
        raise HTTPException(status_code=400, detail="jpg 또는 png 파일만 지원합니다")

    content = await file.read()
    unique_name = str(uuid.uuid4())

    # Upload original
    original_blob = bucket.blob(f"place_images/{unique_name}{file_ext}")
    content_type = "image/jpeg" if file_ext in (".jpg", ".jpeg") else "image/png"
    original_blob.upload_from_string(data=content, content_type=content_type)
    image_url = f"{get_base_url()}/place_images/{unique_name}{file_ext}"

    # Generate thumbnail (200x200 crop)
    img = PILImage.open(io.BytesIO(content))
    img.thumbnail((200, 200))
    thumb_buffer = io.BytesIO()
    img.save(thumb_buffer, format="JPEG", quality=85)
    thumb_buffer.seek(0)

    thumb_blob = bucket.blob(f"place_images/{unique_name}_thumb.jpg")
    thumb_blob.upload_from_string(data=thumb_buffer.getvalue(), content_type="image/jpeg")
    thumbnail_url = f"{get_base_url()}/place_images/{unique_name}_thumb.jpg"

    # Update place
    place.image_url = image_url
    place.thumbnail_url = thumbnail_url
    await place.save()

    return {"imageUrl": image_url, "thumbnailUrl": thumbnail_url}
```

- [ ] **Step 2: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): add POST /places/:id/image with thumbnail generation"
```

---

## Task 6: Backend — Add place_id to Image & HoldPolygon models

**Files:**
- Modify: `services/api/app/models/image.py`
- Modify: `services/api/app/models/hold_polygon.py`

- [ ] **Step 1: Add place_id field to Image model**

In `services/api/app/models/image.py`, add after `wall_expiration_date` field:

```python
    place_id: Optional[PydanticObjectId] = Field(None, description="연결된 Place ID")
```

- [ ] **Step 2: Add place_id field to HoldPolygon model**

In `services/api/app/models/hold_polygon.py`, find the `gym_name` field area and add:

```python
    place_id: Optional[PydanticObjectId] = Field(None, description="연결된 Place ID")
```

- [ ] **Step 3: Update PATCH /hold-polygons to accept place_id in JSON Patch**

The existing JSON Patch handler in `hold_polygons.py` already applies arbitrary patch operations to the document, so `place_id` will be accepted via `{"op": "replace", "path": "/placeId", "value": "..."}` without code changes.

- [ ] **Step 4: Commit**

```bash
git add services/api/app/models/image.py services/api/app/models/hold_polygon.py
git commit -m "feat(api): add place_id field to Image and HoldPolygon models"
```

---

## Task 7: Frontend — Add Flutter packages

**Files:**
- Modify: `apps/mobile/pubspec.yaml`

- [ ] **Step 1: Add dependencies**

```bash
cd apps/mobile && flutter pub add flutter_map latlong2 exif
```

- [ ] **Step 2: Verify**

```bash
cd apps/mobile && flutter analyze
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock
git commit -m "feat(mobile): add flutter_map, latlong2, exif packages"
```

---

## Task 8: Frontend — Place model & API service

**Files:**
- Create: `apps/mobile/lib/models/place_data.dart`
- Create: `apps/mobile/lib/services/place_service.dart`

- [ ] **Step 1: Create PlaceData model**

```dart
// apps/mobile/lib/models/place_data.dart

class PlaceData {
  final String id;
  final String name;
  final String type; // "gym" | "private-gym"
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final String? thumbnailUrl;
  final String createdBy;
  final double? distance;

  PlaceData({
    required this.id,
    required this.name,
    required this.type,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.thumbnailUrl,
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
      imageUrl: json['imageUrl'],
      thumbnailUrl: json['thumbnailUrl'],
      createdBy: json['createdBy'],
      distance: json['distance']?.toDouble(),
    );
  }
}
```

- [ ] **Step 2: Create PlaceService**

```dart
// apps/mobile/lib/services/place_service.dart

import 'dart:convert';
import 'dart:io';
import '../models/place_data.dart';
import 'http_client.dart';

class PlaceService {
  static Future<List<PlaceData>> getNearbyPlaces({
    required double latitude,
    required double longitude,
    double radius = 100,
  }) async {
    final response = await AuthorizedHttpClient.get(
      '/places/nearby?latitude=$latitude&longitude=$longitude&radius=$radius',
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((e) => PlaceData.fromJson(e)).toList();
    }
    throw Exception('Failed to load nearby places');
  }

  static Future<List<PlaceData>> instantSearch(String query) async {
    final response = await AuthorizedHttpClient.get(
      '/places/instant-search?query=${Uri.encodeComponent(query)}',
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((e) => PlaceData.fromJson(e)).toList();
    }
    throw Exception('Failed to search places');
  }

  static Future<PlaceData> createPlace({
    required String name,
    double? latitude,
    double? longitude,
    String type = 'gym',
  }) async {
    final response = await AuthorizedHttpClient.post('/places', body: {
      'name': name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'type': type,
    });
    if (response.statusCode == 201) {
      return PlaceData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    }
    throw Exception('Failed to create place');
  }

  static Future<PlaceData> updatePlace(
    String placeId, {
    String? name,
    double? latitude,
    double? longitude,
  }) async {
    final response = await AuthorizedHttpClient.put('/places/$placeId', body: {
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
    if (response.statusCode == 200) {
      return PlaceData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    }
    throw Exception('Failed to update place');
  }

  static Future<void> createSuggestion({
    required String placeId,
    String? name,
    double? latitude,
    double? longitude,
  }) async {
    final response = await AuthorizedHttpClient.post('/places/suggestions', body: {
      'placeId': placeId,
      'changes': {
        if (name != null) 'name': name,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
    });
    if (response.statusCode != 201) {
      throw Exception('Failed to create suggestion');
    }
  }

  static Future<Map<String, String>> uploadImage(String placeId, String filePath) async {
    final response = await AuthorizedHttpClient.multipartPost(
      '/places/$placeId/image',
      filePath,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return {
        'imageUrl': data['imageUrl'],
        'thumbnailUrl': data['thumbnailUrl'],
      };
    }
    throw Exception('Failed to upload image');
  }
}
```

- [ ] **Step 3: Verify**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/models/place_data.dart apps/mobile/lib/services/place_service.dart
git commit -m "feat(mobile): add PlaceData model and PlaceService"
```

---

## Task 9: Frontend — EXIF GPS extraction service

**Files:**
- Create: `apps/mobile/lib/services/exif_service.dart`

- [ ] **Step 1: Create ExifService**

```dart
// apps/mobile/lib/services/exif_service.dart

import 'dart:io';
import 'package:exif/exif.dart';

class GpsCoordinates {
  final double latitude;
  final double longitude;

  GpsCoordinates({required this.latitude, required this.longitude});
}

class ExifService {
  static Future<GpsCoordinates?> extractGpsFromFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final data = await readExifFromBytes(bytes);

      if (data.isEmpty) return null;

      final latTag = data['GPS GPSLatitude'];
      final latRefTag = data['GPS GPSLatitudeRef'];
      final lngTag = data['GPS GPSLongitude'];
      final lngRefTag = data['GPS GPSLongitudeRef'];

      if (latTag == null || lngTag == null) return null;

      final lat = _convertToDecimal(latTag.values, latRefTag?.printable ?? 'N');
      final lng = _convertToDecimal(lngTag.values, lngRefTag?.printable ?? 'E');

      if (lat == null || lng == null) return null;
      if (lat == 0.0 && lng == 0.0) return null;

      return GpsCoordinates(latitude: lat, longitude: lng);
    } catch (e) {
      return null;
    }
  }

  static double? _convertToDecimal(dynamic values, String ref) {
    try {
      final ratios = values.toList();
      if (ratios.length < 3) return null;

      final degrees = ratios[0].numerator / ratios[0].denominator;
      final minutes = ratios[1].numerator / ratios[1].denominator;
      final seconds = ratios[2].numerator / ratios[2].denominator;

      double decimal = degrees + (minutes / 60) + (seconds / 3600);

      if (ref == 'S' || ref == 'W') {
        decimal = -decimal;
      }

      return decimal;
    } catch (e) {
      return null;
    }
  }
}
```

- [ ] **Step 2: Verify**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/services/exif_service.dart
git commit -m "feat(mobile): add EXIF GPS extraction service"
```

---

## Task 10: Frontend — Place selection bottom sheet

**Files:**
- Create: `apps/mobile/lib/widgets/editors/place_selection_sheet.dart`

- [ ] **Step 1: Create PlaceSelectionSheet widget**

```dart
// apps/mobile/lib/widgets/editors/place_selection_sheet.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../models/place_data.dart';
import '../../services/place_service.dart';
import 'place_registration_sheet.dart';
import 'place_suggestion_sheet.dart';

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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => PlaceSelectionSheet(
          latitude: latitude,
          longitude: longitude,
          currentPlace: currentPlace,
        ),
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
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNearbyPlaces() async {
    if (widget.latitude == null || widget.longitude == null) return;
    setState(() => _isLoading = true);
    try {
      final places = await PlaceService.getNearbyPlaces(
        latitude: widget.latitude!,
        longitude: widget.longitude!,
      );
      if (mounted) setState(() => _places = places);
    } catch (e) {
      // silently fail — user can still search or register
    } finally {
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
    setState(() => _isSearchMode = true);
    _debounce = Timer(const Duration(seconds: 1), () async {
      setState(() => _isLoading = true);
      try {
        final results = await PlaceService.instantSearch(query);
        if (mounted) setState(() => _places = results);
      } catch (e) {
        // silently fail
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  Future<void> _onNewRegistration() async {
    final place = await PlaceRegistrationSheet.show(
      context,
      latitude: widget.latitude,
      longitude: widget.longitude,
    );
    if (place != null && mounted) {
      Navigator.pop(context, place);
    }
  }

  Future<void> _onSuggestEdit(PlaceData place) async {
    await PlaceSuggestionSheet.show(context, place: place);
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.currentPlace != null;

    return Column(
      children: [
        // Handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '암장 선택', // TODO: localize
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: '암장 이름으로 검색', // TODO: localize
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: const Color(0xFFF7F8FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (!_isSearchMode && _places.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '📍 근처 암장',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ..._places.map((place) => _buildPlaceItem(place)),
                    if (_places.isEmpty && !_isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            _isSearchMode ? '검색 결과가 없습니다' : '근처에 등록된 암장이 없습니다',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        // Divider + New registration button
        const Divider(height: 1),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: InkWell(
              onTap: _onNewRegistration,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey[400]!,
                    style: BorderStyle.solid,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text(
                    '+ 새 암장 등록하기', // TODO: localize
                    style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceItem(PlaceData place) {
    final isPrivate = place.type == 'private-gym';
    final isCurrentlySelected = widget.currentPlace?.id == place.id;

    return GestureDetector(
      onTap: () => Navigator.pop(context, place),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isCurrentlySelected
              ? const Color(0xFFEDE7F6)
              : isPrivate
                  ? const Color(0xFFFFF8E1)
                  : const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(10),
          border: isCurrentlySelected
              ? Border.all(color: const Color(0xFF6750A4), width: 1.5)
              : isPrivate
                  ? Border.all(color: const Color(0xFFFFE082))
                  : null,
        ),
        child: Column(
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
                            placeholder: (_, __) => Container(color: Colors.grey[200]),
                            errorWidget: (_, __, ___) => _buildDefaultIcon(isPrivate),
                          )
                        : _buildDefaultIcon(isPrivate),
                  ),
                ),
                const SizedBox(width: 10),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${place.name}${isPrivate ? ' 🔒' : ''}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrentlySelected) ...[
                            const SizedBox(width: 4),
                            Text(
                              '선택됨',
                              style: TextStyle(fontSize: 11, color: const Color(0xFF6750A4)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (place.distance != null) '${place.distance!.round()}m',
                          if (isPrivate) '나만 보임',
                        ].join(' · '),
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPrivate ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isPrivate ? 'private' : 'gym',
                    style: TextStyle(
                      fontSize: 10,
                      color: isPrivate ? const Color(0xFFF57C00) : const Color(0xFF4CAF50),
                    ),
                  ),
                ),
              ],
            ),
            // Edit suggestion link for selected items
            if (isCurrentlySelected) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: const Color(0xFF6750A4).withOpacity(0.2))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () => _onSuggestEdit(place),
                      child: Text(
                        '✏️ 정보 수정 제안',
                        style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFF6750A4),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultIcon(bool isPrivate) {
    return Container(
      color: Colors.grey[200],
      child: Icon(
        isPrivate ? Icons.home : Icons.terrain,
        color: Colors.grey[400],
        size: 24,
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/editors/place_selection_sheet.dart
git commit -m "feat(mobile): add place selection bottom sheet widget"
```

---

## Task 11: Frontend — Place registration bottom sheet (with OSM map)

**Files:**
- Create: `apps/mobile/lib/widgets/editors/place_registration_sheet.dart`

- [ ] **Step 1: Create PlaceRegistrationSheet**

```dart
// apps/mobile/lib/widgets/editors/place_registration_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/place_data.dart';
import '../../services/place_service.dart';

class PlaceRegistrationSheet extends StatefulWidget {
  final double? latitude;
  final double? longitude;

  const PlaceRegistrationSheet({super.key, this.latitude, this.longitude});

  static Future<PlaceData?> show(
    BuildContext context, {
    double? latitude,
    double? longitude,
  }) {
    return showModalBottomSheet<PlaceData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: PlaceRegistrationSheet(latitude: latitude, longitude: longitude),
        ),
      ),
    );
  }

  @override
  State<PlaceRegistrationSheet> createState() => _PlaceRegistrationSheetState();
}

class _PlaceRegistrationSheetState extends State<PlaceRegistrationSheet> {
  final TextEditingController _nameController = TextEditingController();
  late LatLng _pinPosition;
  bool _isPrivate = false;
  bool _isSaving = false;
  bool _hasCoordinates = false;

  @override
  void initState() {
    super.initState();
    _hasCoordinates = widget.latitude != null && widget.longitude != null;
    _pinPosition = _hasCoordinates
        ? LatLng(widget.latitude!, widget.longitude!)
        : const LatLng(37.5665, 126.9780); // Seoul default
  }

  Future<void> _onRegister() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final type = _isPrivate ? 'private-gym' : 'gym';
      final place = await PlaceService.createPlace(
        name: name,
        latitude: (!_isPrivate || _hasCoordinates) ? _pinPosition.latitude : null,
        longitude: (!_isPrivate || _hasCoordinates) ? _pinPosition.longitude : null,
        type: type,
      );
      if (mounted) Navigator.pop(context, place);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('등록에 실패했습니다')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
        ),
        // Title
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('새 암장 등록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('등록한 암장은 다른 유저도 검색할 수 있어요',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name input
                Text('암장 이름 *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '암장 이름을 입력하세요',
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                // Map
                if (_hasCoordinates || !_isPrivate) ...[
                  Row(
                    children: [
                      Text('위치', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                      const SizedBox(width: 4),
                      Text('탭하여 핀 이동', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 180,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _pinPosition,
                          initialZoom: 16,
                          onTap: (tapPosition, point) {
                            setState(() => _pinPosition = point);
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.besetter.app',
                          ),
                          MarkerLayer(markers: [
                            Marker(
                              point: _pinPosition,
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                            ),
                          ]),
                          const RichAttributionWidget(attributions: [
                            TextSourceAttribution('OpenStreetMap contributors'),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Private toggle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('개인 암장', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text('나만 볼 수 있는 암장', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                        ],
                      ),
                      Switch(
                        value: _isPrivate,
                        onChanged: (v) => setState(() => _isPrivate = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Register button
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _isSaving ? null : _onRegister,
                child: _isSaving
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('등록하기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/editors/place_registration_sheet.dart
git commit -m "feat(mobile): add place registration sheet with OSM map"
```

---

## Task 12: Frontend — Place suggestion/edit bottom sheet

**Files:**
- Create: `apps/mobile/lib/widgets/editors/place_suggestion_sheet.dart`

- [ ] **Step 1: Create PlaceSuggestionSheet**

```dart
// apps/mobile/lib/widgets/editors/place_suggestion_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/place_data.dart';
import '../../services/place_service.dart';

class PlaceSuggestionSheet extends StatefulWidget {
  final PlaceData place;

  const PlaceSuggestionSheet({super.key, required this.place});

  static Future<void> show(BuildContext context, {required PlaceData place}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: PlaceSuggestionSheet(place: place),
        ),
      ),
    );
  }

  @override
  State<PlaceSuggestionSheet> createState() => _PlaceSuggestionSheetState();
}

class _PlaceSuggestionSheetState extends State<PlaceSuggestionSheet> {
  late TextEditingController _nameController;
  late LatLng _newPin;
  late LatLng _oldPin;
  bool _isSaving = false;
  bool _hasCoordinates = false;

  bool get _isPrivate => widget.place.type == 'private-gym';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.place.name);
    _hasCoordinates = widget.place.latitude != null && widget.place.longitude != null;
    final lat = widget.place.latitude ?? 37.5665;
    final lng = widget.place.longitude ?? 126.9780;
    _oldPin = LatLng(lat, lng);
    _newPin = LatLng(lat, lng);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    setState(() => _isSaving = true);
    try {
      final newName = _nameController.text.trim();
      final nameChanged = newName != widget.place.name && newName.isNotEmpty;
      final locationChanged = _hasCoordinates && (_newPin.latitude != _oldPin.latitude || _newPin.longitude != _oldPin.longitude);

      if (!nameChanged && !locationChanged) {
        Navigator.pop(context);
        return;
      }

      if (_isPrivate) {
        // Direct update
        await PlaceService.updatePlace(
          widget.place.id,
          name: nameChanged ? newName : null,
          latitude: locationChanged ? _newPin.latitude : null,
          longitude: locationChanged ? _newPin.longitude : null,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('수정되었습니다')),
          );
          Navigator.pop(context);
        }
      } else {
        // Submit suggestion
        await PlaceService.createSuggestion(
          placeId: widget.place.id,
          name: nameChanged ? newName : null,
          latitude: locationChanged ? _newPin.latitude : null,
          longitude: locationChanged ? _newPin.longitude : null,
        );
        if (mounted) {
          Navigator.pop(context);
          _showSuccessDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('요청에 실패했습니다')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Color(0xFF4CAF50), size: 32),
            ),
            const SizedBox(height: 16),
            const Text('제안이 접수되었습니다', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('운영자 검수 후 반영됩니다.', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _isPrivate ? const Color(0xFFF57C00) : const Color(0xFF6750A4);

    return Column(
      children: [
        // Handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
        ),
        // Title
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPrivate ? '암장 정보 수정' : '정보 수정 제안',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _isPrivate ? '🔒 개인 암장 · 즉시 반영됩니다' : '검수 후 반영됩니다',
                  style: TextStyle(fontSize: 12, color: _isPrivate ? const Color(0xFFF57C00) : Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                Text('암장 이름', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                const SizedBox(height: 6),
                if (!_isPrivate) ...[
                  // Show current value for gym type
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFFFAFAFA),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(widget.place.name, style: TextStyle(fontSize: 14, color: Colors.grey[500], decoration: TextDecoration.lineThrough)),
                        Text('현재', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                  const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Icon(Icons.arrow_downward, size: 16, color: Colors.grey))),
                ],
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentColor, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                // Map
                if (_hasCoordinates) ...[
                  Row(
                    children: [
                      Text('위치', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                      const SizedBox(width: 4),
                      Text('탭하여 새 위치 지정', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 180,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _oldPin,
                          initialZoom: 16,
                          onTap: (_, point) => setState(() => _newPin = point),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.besetter.app',
                          ),
                          MarkerLayer(markers: [
                            // Old pin (grey)
                            if (_newPin != _oldPin)
                              Marker(
                                point: _oldPin,
                                width: 30, height: 30,
                                child: Icon(Icons.location_pin, color: Colors.grey[400], size: 30),
                              ),
                            // New pin
                            Marker(
                              point: _newPin,
                              width: 40, height: 40,
                              child: Icon(Icons.location_pin, color: accentColor, size: 40),
                            ),
                          ]),
                          const RichAttributionWidget(attributions: [
                            TextSourceAttribution('OpenStreetMap contributors'),
                          ]),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _isSaving ? null : _onSubmit,
                style: FilledButton.styleFrom(backgroundColor: accentColor),
                child: _isSaving
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _isPrivate ? '수정하기' : '수정 제안하기',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/editors/place_suggestion_sheet.dart
git commit -m "feat(mobile): add place suggestion/edit bottom sheet"
```

---

## Task 13: Frontend — Integrate into SprayWallEditor

**Files:**
- Modify: `apps/mobile/lib/widgets/editors/spray_wall_information_input_widget.dart`
- Modify: `apps/mobile/lib/pages/editors/spray_wall_editor_page.dart`

- [ ] **Step 1: Update SprayWallInformationInput to accept placeId + placeName**

Replace the `_showGymInfoModal` method in `spray_wall_information_input_widget.dart` to open `PlaceSelectionSheet` instead of a text input modal. Add new parameters:

```dart
// New parameters to add to SprayWallInformationInput:
final PlaceData? selectedPlace;
final Function(PlaceData?) onPlaceChanged;
```

Remove `gymNameController`, `onGymNameChanged`, `gymNameError` parameters. Keep `wallNameController`, `onWallNameChanged`, `wallNameError` as-is.

Replace the gym info ListTile to show selected place name (or "선택하여 입력하세요"), and open `PlaceSelectionSheet` on tap.

- [ ] **Step 2: Update SprayWallEditorPage state**

In `spray_wall_editor_page.dart`:

Replace:
```dart
final TextEditingController _gymNameController = TextEditingController();
```

With:
```dart
PlaceData? _selectedPlace;
```

Update `initState` to load existing place if `placeId` exists.

Update `_saveChanges()` to send `placeId` instead of `gymName` in JSON Patch:
```dart
// Replace gymName patch with:
if (_selectedPlace != null) {
  _jsonPatchOperations.add({
    "op": "replace",
    "path": "/placeId",
    "value": _selectedPlace!.id,
  });
}
```

Add EXIF extraction when image is loaded:
```dart
// In _loadImage() or initState, for new images (imageFile != null):
if (widget.imageFile != null) {
  final gps = await ExifService.extractGpsFromFile(widget.imageFile!);
  if (gps != null) {
    _exifLatitude = gps.latitude;
    _exifLongitude = gps.longitude;
  }
}
```

- [ ] **Step 3: Wire up PlaceSelectionSheet opening**

When "클라이밍 암장 정보" ListTile is tapped, open the selection sheet and pass EXIF coordinates:

```dart
final place = await PlaceSelectionSheet.show(
  context,
  latitude: _exifLatitude,
  longitude: _exifLongitude,
  currentPlace: _selectedPlace,
);
if (place != null) {
  setState(() => _selectedPlace = place);
}
```

- [ ] **Step 4: Verify**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/editors/spray_wall_information_input_widget.dart apps/mobile/lib/pages/editors/spray_wall_editor_page.dart
git commit -m "feat(mobile): integrate place selection into spray wall editor"
```

---

## Task 14: Atlas Search nGram Index Setup

**Files:** None (MongoDB Atlas console configuration)

- [ ] **Step 1: Create Atlas Search index on places collection**

In MongoDB Atlas console → Database → Search Indexes → Create Index:

```json
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "normalizedName": {
        "type": "autocomplete",
        "tokenization": "nGram",
        "minGrams": 2,
        "maxGrams": 15,
        "foldDiacritics": true
      }
    }
  }
}
```

Index name: `places_name_ngram`

- [ ] **Step 2: Update instant-search endpoint to use Atlas Search**

When the Atlas Search index is ready, replace the regex query in `instant_search_places` with:

```python
@router.get("/instant-search", response_model=List[PlaceView])
async def instant_search_places(
    query: str,
    current_user: User = Depends(get_current_user),
):
    normalized_query = normalize_name(query)
    if len(normalized_query) < 2:
        return []

    pipeline = [
        {
            "$search": {
                "index": "places_name_ngram",
                "autocomplete": {
                    "query": normalized_query,
                    "path": "normalizedName",
                },
            }
        },
        {"$limit": 20},
    ]

    collection = Place.get_motor_collection()
    cursor = collection.aggregate(pipeline)
    docs = await cursor.to_list(length=20)

    results = []
    for doc in docs:
        p_type = doc.get("type", "gym")
        if p_type == "private-gym" and str(doc.get("createdBy")) != str(current_user.id):
            continue
        results.append(PlaceView(
            id=doc["_id"],
            name=doc["name"],
            type=p_type,
            latitude=doc.get("latitude"),
            longitude=doc.get("longitude"),
            image_url=doc.get("imageUrl"),
            thumbnail_url=doc.get("thumbnailUrl"),
            created_by=doc["createdBy"],
        ))

    return results
```

- [ ] **Step 3: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): use Atlas Search nGram index for instant-search"
```
