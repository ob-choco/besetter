# Place Registration Request Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `gym` place registration from instant creation to a review-gated "request" flow (status = pending → approved / rejected / merged). Admin transitions live in a separate tool; this plan implements the requester-facing flow, defensive handling of stale place references, and mobile UX for pending places.

**Architecture:** Add a `status` field (and placeholder `mergedIntoPlaceId`) to the existing `Place` model. Filter queries by status with a "own pending is visible" rule. Image/route place_id operations call a new `resolve_place_for_use` helper that transparently redirects `merged` and 409s `rejected` / foreign-pending. Mobile shows a "검수중" badge, a guide banner on pending edit, and a non-destructive popup on 409.

**Tech Stack:** FastAPI + Beanie ODM (MongoDB Atlas), Flutter + Riverpod, Jinja2 templates for share page.

**Reference Spec:** `docs/superpowers/specs/2026-04-18-place-registration-request-design.md`

---

## File Structure

**Modify (API):**
- `services/api/app/models/place.py` — add `status`, `merged_into_place_id`
- `services/api/app/routers/places.py` — `PlaceView`, create/update/delete/list/suggestions endpoints
- `services/api/app/routers/images.py` — wire `resolve_place_for_use` on place_id set/change
- `services/api/app/routers/routes.py` — wire `resolve_place_for_use` on route create/update (via image)
- `services/api/app/routers/share.py` — pass `place_status` to template
- `services/api/app/templates/share_route.html` — render pending badge
- `services/api/tests/routers/test_places.py` — schema + helper tests

**Create (API):**
- `services/api/app/services/place_status.py` — `resolve_place_for_use` helper
- `services/api/tests/services/__init__.py` — package marker (if missing)
- `services/api/tests/services/test_place_status.py` — helper unit tests

**Modify (Mobile):**
- `apps/mobile/lib/models/place_data.dart` — add `status`
- `apps/mobile/lib/services/place_service.dart` — add `deletePlace`, 409 exception type
- `apps/mobile/lib/widgets/editors/place_selection_sheet.dart` — badge, register CTA/banner/toast, edit/delete buttons on pending items
- `apps/mobile/lib/widgets/editors/place_edit_pane.dart` — guide banner for pending gym
- Wherever ImageData/RouteData are uploaded/updated (identified in Task M7)

**Create (Mobile):**
- `apps/mobile/lib/widgets/place_pending_badge.dart` — reusable badge
- `apps/mobile/lib/widgets/place_not_usable_dialog.dart` — reusable 409 popup

---

## Conventions

- Commit after every completed task. Commit message format: `feat(api): …` or `feat(mobile): …` etc.
- Python tests live next to the existing `services/api/tests/**` tree. Use `pytest services/api/tests/...` from the repo root, or `cd services/api && pytest`.
- Mobile verification uses `flutter analyze` (primary) and `flutter test` (when unit tests exist). `cd apps/mobile && flutter analyze` must be clean after each mobile task.
- DO NOT introduce admin-role endpoints in this plan. Status transitions (approve/reject/merge) stay out of scope.

---

## Task A1: Add `status` and `merged_into_place_id` to Place model

**Files:**
- Modify: `services/api/app/models/place.py:29-66`

- [ ] **Step 1: Add fields to the Place document**

Replace the Place class body (after the existing `created_at` line, before `set_location_from`) by adding two new fields. Edit `services/api/app/models/place.py` so the Place class reads:

```python
class Place(Document):
    model_config = model_config

    name: str = Field(..., description="장소 이름")
    normalized_name: str = Field(..., description="정규화된 장소 이름 (공백/기호 제거, 소문자)")
    type: Literal["gym", "private-gym"] = Field(..., description="장소 유형")
    location: Optional[GeoJsonPoint] = Field(None, description="GeoJSON Point [lng, lat]")
    cover_image_url: Optional[str] = Field(None, description="대표 이미지 URL")
    created_by: PydanticObjectId = Field(..., description="생성한 사용자의 ID")
    created_at: datetime = Field(..., description="생성 시간")
    status: Literal["pending", "approved", "rejected", "merged"] = Field(
        default="approved",
        description="장소 상태. gym 최초 생성은 pending, private-gym은 approved.",
    )
    merged_into_place_id: Optional[PydanticObjectId] = Field(
        default=None,
        description="merged 상태일 때 병합 대상 place의 ID. 검수 툴이 설정.",
    )

    def set_location_from(self, latitude: Optional[float], longitude: Optional[float]):
        # ...existing body unchanged...
```

(Keep `set_location_from`, the `latitude`/`longitude` properties, and the `Settings` class unchanged.)

- [ ] **Step 2: Add `(type, status)` compound index to Settings.indexes**

Modify the Settings.indexes list (currently at lines ~61-65) so it reads:

```python
    class Settings:
        name = "places"
        indexes = [
            IndexModel([("location", GEOSPHERE)], sparse=True),
            IndexModel([("createdBy", ASCENDING)]),
            IndexModel([("normalizedName", ASCENDING)]),
            IndexModel([("type", ASCENDING), ("status", ASCENDING)]),
        ]
        keep_nulls = True
```

- [ ] **Step 3: Write schema test for default status**

Create a new test in `services/api/tests/routers/test_places.py` (append to end of file):

```python
def test_place_defaults_to_approved_status():
    """Place() without explicit status defaults to approved — preserves backward
    compatibility when Pydantic hydrates legacy documents that lack the field."""
    from datetime import datetime, timezone
    from bson import ObjectId
    from app.models.place import Place

    p = Place(
        name="Foo",
        normalized_name="foo",
        type="private-gym",
        created_by=ObjectId(),
        created_at=datetime.now(tz=timezone.utc),
    )
    assert p.status == "approved"
    assert p.merged_into_place_id is None
```

- [ ] **Step 4: Run the test**

```bash
cd services/api && pytest tests/routers/test_places.py::test_place_defaults_to_approved_status -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/models/place.py services/api/tests/routers/test_places.py
git commit -m "feat(api): add status and mergedIntoPlaceId to Place model"
```

---

## Task A2: Add `status` to `PlaceView` and include in `place_to_view`

**Files:**
- Modify: `services/api/app/routers/places.py:51-85`

- [ ] **Step 1: Add `status` field to `PlaceView`**

Edit `services/api/app/routers/places.py` — find the `PlaceView` class (around line 51-61) and change it to:

```python
class PlaceView(BaseModel):
    model_config = model_config

    id: PydanticObjectId
    name: str
    type: str
    status: Literal["pending", "approved", "rejected", "merged"]
    latitude: Optional[float]
    longitude: Optional[float]
    cover_image_url: Optional[str]
    created_by: PydanticObjectId
    distance: Optional[float] = None
```

Make sure `Literal` is imported (add to the `from typing import ...` line at the top: `from typing import List, Literal, Optional`).

- [ ] **Step 2: Update `place_to_view` helper**

Edit the helper (around line 75-85) to pass `status`:

```python
def place_to_view(place: Place, distance: Optional[float] = None) -> PlaceView:
    return PlaceView(
        id=place.id,
        name=place.name,
        type=place.type,
        status=place.status,
        latitude=place.latitude,
        longitude=place.longitude,
        cover_image_url=place.cover_image_url,
        created_by=place.created_by,
        distance=round(distance, 2) if distance is not None else None,
    )
```

Note: I also normalized the `distance` rounding which was duplicated at call sites. Verify the call site at line 180 still reads `distance=haversine_distance(...)` (not pre-rounded); if it was already rounded there, keep the old shape and just add `status=place.status` instead — the important change is adding `status`.

- [ ] **Step 3: Schema test for PlaceView serialization**

Append to `services/api/tests/routers/test_places.py`:

```python
def test_place_view_serializes_status_camelcase():
    from bson import ObjectId
    from app.routers.places import PlaceView

    v = PlaceView(
        id=ObjectId(),
        name="Foo",
        type="gym",
        status="pending",
        latitude=37.5,
        longitude=127.0,
        cover_image_url=None,
        created_by=ObjectId(),
    )
    dumped = v.model_dump(by_alias=True)
    assert dumped["status"] == "pending"
    assert "coverImageUrl" in dumped  # sanity: camelCase alias still in effect
```

- [ ] **Step 4: Run the test**

```bash
cd services/api && pytest tests/routers/test_places.py -v
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/places.py services/api/tests/routers/test_places.py
git commit -m "feat(api): include status in PlaceView responses"
```

---

## Task A3: `POST /places` sets status by type

**Files:**
- Modify: `services/api/app/routers/places.py:102-146`

- [ ] **Step 1: Set status in create_place**

Find the `create_place` function (starting around line 102). After the existing line that creates the `Place(...)` instance (around line 135-142), add `status=...` via a small calc:

```python
    place = Place(
        name=name,
        normalized_name=normalize_name(name),
        type=type,
        status="pending" if type == "gym" else "approved",
        cover_image_url=cover_image_url,
        created_by=current_user.id,
        created_at=datetime.now(tz=timezone.utc),
    )
    place.set_location_from(latitude, longitude)

    created = await place.save()
    return place_to_view(created)
```

(merged_into_place_id default is `None` — omit.)

- [ ] **Step 2: Add a unit test that creates Place with explicit type and checks status**

This is testable without DB by constructing a Place object and checking that the calculation is correct. Append to `services/api/tests/routers/test_places.py`:

```python
def test_place_construction_gym_vs_private_gym_status():
    """Sanity-check the branching logic used by POST /places."""
    from datetime import datetime, timezone
    from bson import ObjectId
    from app.models.place import Place

    common = dict(
        name="X",
        normalized_name="x",
        created_by=ObjectId(),
        created_at=datetime.now(tz=timezone.utc),
    )
    gym = Place(type="gym", status="pending" if "gym" == "gym" else "approved", **common)
    private = Place(type="private-gym", status="pending" if "private-gym" == "gym" else "approved", **common)
    assert gym.status == "pending"
    assert private.status == "approved"
```

- [ ] **Step 3: Run it**

```bash
cd services/api && pytest tests/routers/test_places.py::test_place_construction_gym_vs_private_gym_status -v
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add services/api/app/routers/places.py services/api/tests/routers/test_places.py
git commit -m "feat(api): gym create starts pending, private-gym starts approved"
```

---

## Task A4: Emit `place_registration_ack` notification on gym creation

**Files:**
- Modify: `services/api/app/routers/places.py:102-146` (create_place)

Reference the existing `place_suggestion_ack` block at lines 316-341 — we copy its shape.

- [ ] **Step 1: Add best-effort notification for gym creation**

In `create_place`, after the `created = await place.save()` line and before `return place_to_view(created)`, insert:

```python
    if place.type == "gym":
        try:
            notif = Notification(
                user_id=current_user.id,
                type="place_registration_ack",
                title="암장 등록 요청이 접수되었습니다",
                body=(
                    f"{place.name} 등록을 요청해주신 소중한 제보 감사합니다 🙌 "
                    "서비스에 반영될 수 있도록 빠르게 처리해서 알려드리겠습니다."
                ),
                link=f"/places/{place.id}",
                created_at=datetime.now(tz=timezone.utc),
            )
            await notif.save()
            await User.get_pymongo_collection().update_one(
                {"_id": current_user.id},
                {"$inc": {"unreadNotificationCount": 1}},
            )
        except Exception as exc:
            logger.warning(
                "registration_ack notification failed for place %s: %s",
                place.id,
                exc,
                exc_info=True,
            )
```

`Notification` and `User` are already imported at the top of the file. Keep the try/except wide — per the existing pattern, best-effort.

- [ ] **Step 2: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): notify requester on gym registration request"
```

---

## Task A5: Update `place_suggestion_ack` body text

**Files:**
- Modify: `services/api/app/routers/places.py:322-326`

- [ ] **Step 1: Replace the body string**

Find the existing notification construction inside `create_place_suggestion` (around line 319-330). Change the `body=(...)` expression so it reads:

```python
            notif = Notification(
                user_id=current_user.id,
                type="place_suggestion_ack",
                title="정보 수정 제안이 접수되었습니다",
                body=(
                    f"{place_name_snapshot}에 대한 소중한 제보 감사합니다 🙌 "
                    "서비스에 반영될 수 있도록 빠르게 처리해서 알려드리겠습니다."
                ),
                link=f"/places/{place.id}",
                created_at=datetime.now(tz=timezone.utc),
            )
```

`type`, `title`, `link` stay the same. Only the body string changes.

- [ ] **Step 2: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "refactor(api): align suggestion-ack body with registration-ack phrasing"
```

---

## Task A6: Reject non-approved places in `POST /places/suggestions`

**Files:**
- Modify: `services/api/app/routers/places.py:262-282` (create_place_suggestion)

- [ ] **Step 1: Add a status check after the `private-gym` check**

Locate the existing guard (around line 275-279):

```python
    if place.type == "private-gym":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Suggestions are not allowed for private-gym places",
        )
```

Immediately after it, insert:

```python
    if place.status != "approved":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Suggestions are only allowed for approved places",
        )
```

- [ ] **Step 2: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): block suggestions for non-approved places"
```

---

## Task A7: Filter `GET /places/nearby` by status

**Files:**
- Modify: `services/api/app/routers/places.py:149-183`

- [ ] **Step 1: Update the nearby query_filter**

Find `get_nearby_places` (around line 149). Change the `query_filter` dict to include the status `$or`:

```python
    query_filter = {
        "type": "gym",
        "$or": [
            {"status": "approved"},
            {"status": "pending", "createdBy": current_user.id},
        ],
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
```

Note: `createdBy` is the MongoDB field name (Beanie auto-aliases from `created_by`). Verify this convention in the existing router — if other places in this file already use `createdBy` in raw Mongo queries, follow suit; if they use `created_by`, use that instead. As of this plan, the existing PlaceSuggestion query uses snake_case field names via Beanie's expression builder, but raw dict queries here use camelCase (see `"normalizedName"` at line 198). So `createdBy` is correct.

- [ ] **Step 2: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): include own pending gyms in nearby results"
```

---

## Task A8: Filter `GET /places/instant-search` by status

**Files:**
- Modify: `services/api/app/routers/places.py:186-205`

- [ ] **Step 1: Update the instant_search_places query**

Find `instant_search_places` (around line 186). Change the Mongo filter:

```python
    candidates = await Place.find(
        {
            "type": "gym",
            "$or": [
                {"status": "approved"},
                {"status": "pending", "createdBy": current_user.id},
            ],
            "normalizedName": {
                "$regex": re.escape(normalized_query),
                "$options": "i",
            },
        }
    ).limit(20).to_list()
```

- [ ] **Step 2: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): include own pending gyms in instant-search results"
```

---

## Task A9: Extend `PUT /places/{id}` to allow owner's pending gym

**Files:**
- Modify: `services/api/app/routers/places.py:221-259` (update_place)

- [ ] **Step 1: Replace the permission guard**

In `update_place`, find the current permission check (around line 234-238):

```python
    if place.type != "private-gym" or str(place.created_by) != str(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not allowed to update this place",
        )
```

Replace with:

```python
    is_owner = str(place.created_by) == str(current_user.id)
    is_own_private = place.type == "private-gym" and is_owner
    is_own_pending_gym = (
        place.type == "gym" and place.status == "pending" and is_owner
    )
    if not (is_own_private or is_own_pending_gym):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not allowed to update this place",
        )
```

- [ ] **Step 2: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): allow owner to update their pending gym place"
```

---

## Task A10: `DELETE /places/{id}` with cascade

**Files:**
- Modify: `services/api/app/routers/places.py` (add new endpoint near PUT)
- Need imports: `from app.models.image import Image`, `from app.models.route import Route`, `from fastapi import Response`

- [ ] **Step 1: Verify available imports / helpers**

Open `services/api/app/routers/places.py`. At the top, confirm which of these are already imported: `Image`, `Route`, `Response`. If any is missing:
- Add `from app.models.image import Image`
- Add `from app.models.route import Route`
- Include `Response` in the fastapi import line: `from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile`

- [ ] **Step 2: Add a GCS blob-path extraction helper (or use existing)**

The codebase may already have a helper to extract a blob path from a GCS URL (look in `app.core.gcs` or routes.py `extract_blob_path_from_url`). If one exists, import it: `from app.services.route_overlay import extract_blob_path_from_url` (or wherever it lives). If none exists, add a small local helper after `_upload_place_image`:

```python
def _extract_place_image_blob_name(url: str) -> Optional[str]:
    """Given a place_images/<uuid>.<ext> URL, return the blob name for GCS."""
    if not url:
        return None
    marker = "place_images/"
    idx = url.find(marker)
    if idx == -1:
        return None
    return url[idx:]
```

- [ ] **Step 3: Add the DELETE endpoint**

Insert this endpoint after `update_place` and before `create_place_suggestion`:

```python
@router.delete("/{place_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_place(
    place_id: str,
    current_user: User = Depends(get_current_user),
):
    place = await Place.get(place_id)
    if place is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Place not found",
        )

    is_owner = str(place.created_by) == str(current_user.id)
    if not (place.type == "gym" and place.status == "pending" and is_owner):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only your own pending gym place can be deleted",
        )

    # Collect images belonging to this place.
    images = await Image.find(Image.place_id == place.id).to_list()
    image_ids = [img.id for img in images]

    # 1) Hard-delete routes attached to those images.
    if image_ids:
        try:
            await Route.find({"imageId": {"$in": image_ids}}).delete()
        except Exception as exc:
            logger.warning("delete_place: route cleanup failed for place %s: %s", place.id, exc, exc_info=True)

    # 2) Hard-delete images + their GCS blobs (best-effort per image).
    for img in images:
        try:
            await img.delete()
        except Exception as exc:
            logger.warning("delete_place: image %s delete failed: %s", img.id, exc, exc_info=True)
        try:
            blob_name = _extract_place_image_blob_name(str(img.url)) if img.url else None
            if blob_name:
                bucket.blob(blob_name).delete()
        except Exception as exc:
            logger.warning("delete_place: image %s GCS delete failed: %s", img.id, exc, exc_info=True)

    # 3) Delete the place cover blob (best-effort).
    try:
        cover_blob = _extract_place_image_blob_name(place.cover_image_url or "")
        if cover_blob:
            bucket.blob(cover_blob).delete()
    except Exception as exc:
        logger.warning("delete_place: cover GCS delete failed for place %s: %s", place.id, exc, exc_info=True)

    # 4) Finally delete the Place itself.
    await place.delete()

    return Response(status_code=status.HTTP_204_NO_CONTENT)
```

Notes:
- If `Image.url` is not a plain string attribute (it might be `HttpUrl`), casting with `str()` is safe.
- `Image.find(Image.place_id == place.id)` uses Beanie's expression. If that causes typing issues, fall back to raw: `Image.find({"placeId": place.id})`.
- This is Python — the `Route.find({"imageId": ...}).delete()` uses raw field name. Confirm the Beanie-aliased camelCase `imageId` by scanning routes.py for any existing raw-dict Route query; if not found, use the typed API: `Route.find(In(Route.image_id, image_ids)).delete()` with `from beanie.operators import In`.

- [ ] **Step 4: Commit**

```bash
git add services/api/app/routers/places.py
git commit -m "feat(api): DELETE /places/{id} with cascade for owner pending gym"
```

---

## Task A11: Create `resolve_place_for_use` helper + unit tests

**Files:**
- Create: `services/api/app/services/place_status.py`
- Create: `services/api/tests/services/__init__.py` (empty if missing)
- Create: `services/api/tests/services/test_place_status.py`

- [ ] **Step 1: Ensure services tests package exists**

```bash
mkdir -p services/api/tests/services
[ -f services/api/tests/services/__init__.py ] || : > services/api/tests/services/__init__.py
```

Also ensure `services/api/app/services/__init__.py` exists (it should, since `services/route_overlay.py` is in that tree — verify with `ls services/api/app/services/`).

- [ ] **Step 2: Write the failing test**

Create `services/api/tests/services/test_place_status.py`:

```python
import pytest
from unittest.mock import AsyncMock, MagicMock

from bson import ObjectId
from fastapi import HTTPException


@pytest.mark.asyncio
async def test_approved_place_returns_itself():
    from app.services.place_status import resolve_place_for_use

    place = MagicMock(id=ObjectId(), name="X", status="approved",
                     created_by=ObjectId(), merged_into_place_id=None)
    user = MagicMock(id=ObjectId())
    result = await resolve_place_for_use(place, user)
    assert result is place


@pytest.mark.asyncio
async def test_own_pending_place_returns_itself():
    from app.services.place_status import resolve_place_for_use

    uid = ObjectId()
    place = MagicMock(id=ObjectId(), name="X", status="pending",
                     created_by=uid, merged_into_place_id=None)
    user = MagicMock(id=uid)
    result = await resolve_place_for_use(place, user)
    assert result is place


@pytest.mark.asyncio
async def test_foreign_pending_raises_409():
    from app.services.place_status import resolve_place_for_use

    place = MagicMock(id=ObjectId(), name="X", status="pending",
                     created_by=ObjectId(), merged_into_place_id=None)
    user = MagicMock(id=ObjectId())
    with pytest.raises(HTTPException) as exc:
        await resolve_place_for_use(place, user)
    assert exc.value.status_code == 409
    assert exc.value.detail["code"] == "PLACE_NOT_USABLE"
    assert exc.value.detail["place_status"] == "pending"


@pytest.mark.asyncio
async def test_rejected_raises_409():
    from app.services.place_status import resolve_place_for_use

    place = MagicMock(id=ObjectId(), name="X", status="rejected",
                     created_by=ObjectId(), merged_into_place_id=None)
    user = MagicMock(id=ObjectId())
    with pytest.raises(HTTPException) as exc:
        await resolve_place_for_use(place, user)
    assert exc.value.status_code == 409
    assert exc.value.detail["place_status"] == "rejected"


@pytest.mark.asyncio
async def test_merged_redirects_to_target(monkeypatch):
    from app.services import place_status as mod

    target_id = ObjectId()
    target = MagicMock(id=target_id, name="Target", status="approved",
                       created_by=ObjectId(), merged_into_place_id=None)
    get_mock = AsyncMock(return_value=target)
    monkeypatch.setattr(mod.Place, "get", get_mock)

    place = MagicMock(id=ObjectId(), name="Old", status="merged",
                     created_by=ObjectId(), merged_into_place_id=target_id)
    user = MagicMock(id=ObjectId())
    result = await mod.resolve_place_for_use(place, user)
    assert result is target
    get_mock.assert_awaited_once_with(target_id)


@pytest.mark.asyncio
async def test_merged_without_target_id_raises_409():
    from app.services.place_status import resolve_place_for_use

    place = MagicMock(id=ObjectId(), name="X", status="merged",
                     created_by=ObjectId(), merged_into_place_id=None)
    user = MagicMock(id=ObjectId())
    with pytest.raises(HTTPException) as exc:
        await resolve_place_for_use(place, user)
    assert exc.value.status_code == 409


@pytest.mark.asyncio
async def test_merged_chain_stops_at_one_hop(monkeypatch):
    """A→B where B is also merged: single-hop follow, then 409 (chain not followed)."""
    from app.services import place_status as mod

    b_id = ObjectId()
    b = MagicMock(id=b_id, name="B", status="merged",
                  created_by=ObjectId(), merged_into_place_id=ObjectId())
    monkeypatch.setattr(mod.Place, "get", AsyncMock(return_value=b))

    a = MagicMock(id=ObjectId(), name="A", status="merged",
                  created_by=ObjectId(), merged_into_place_id=b_id)
    user = MagicMock(id=ObjectId())
    with pytest.raises(HTTPException) as exc:
        await mod.resolve_place_for_use(a, user)
    assert exc.value.status_code == 409
```

- [ ] **Step 3: Run the tests — they should fail (module doesn't exist yet)**

```bash
cd services/api && pytest tests/services/test_place_status.py -v
```

Expected: ImportError on `app.services.place_status`.

- [ ] **Step 4: Implement the helper**

Create `services/api/app/services/place_status.py`:

```python
from typing import Optional

from fastapi import HTTPException, status

from app.models.place import Place
from app.models.user import User


async def resolve_place_for_use(place: Place, user: User) -> Place:
    """Return the place that should be used for an operation referencing `place`.

    Behavior:
    - `approved`: returned as-is.
    - `pending` created by the same user: returned as-is.
    - `merged` with a `merged_into_place_id`: follows a single hop to the target;
      if the target itself is not approved or not the user's own pending, raises
      409. Does not follow chains.
    - Anything else (rejected, foreign pending, merged-without-target,
      merged-chain-mid-hop): raises HTTP 409 with code `PLACE_NOT_USABLE`.
    """
    effective = place
    if effective.status == "merged" and effective.merged_into_place_id:
        target = await Place.get(effective.merged_into_place_id)
        if target is not None:
            effective = target

    if effective.status == "approved":
        return effective
    if effective.status == "pending" and str(effective.created_by) == str(user.id):
        return effective

    raise HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail={
            "code": "PLACE_NOT_USABLE",
            "place_id": str(effective.id),
            "place_name": effective.name,
            "place_status": effective.status,
        },
    )
```

- [ ] **Step 5: Run the tests — they should pass**

```bash
cd services/api && pytest tests/services/test_place_status.py -v
```

Expected: all PASS. If `pytest-asyncio` isn't installed or the tests are skipped, add the marker config to `services/api/pytest.ini` (or equivalent) — this codebase likely already supports async tests since other routers use them; verify by running `pytest -v` once and inspecting the output.

- [ ] **Step 6: Commit**

```bash
git add services/api/app/services/place_status.py services/api/tests/services/
git commit -m "feat(api): add resolve_place_for_use helper for stale-place defense"
```

---

## Task A12: Wire `resolve_place_for_use` into image endpoints

**Files:**
- Modify: `services/api/app/routers/images.py` — all places where `place_id` is assigned from user input

- [ ] **Step 1: Find every place_id set-or-change location**

Run:

```bash
cd services/api && grep -n "place_id" app/routers/images.py
```

For each location where the code reads an incoming `place_id` (from request body/form) and stores it on an `Image`, you will insert a `resolve_place_for_use` call. Typical shapes:

- **Upload / create**: right before saving the Image, if `request.place_id` (or form `place_id`) is set, resolve and use the returned place's id.
- **Update**: if a request updates `place_id`, resolve before assigning.

- [ ] **Step 2: Add the import at the top**

Add:

```python
from app.models.place import Place
from app.services.place_status import resolve_place_for_use
```

(if not already present).

- [ ] **Step 3: Wrap each place_id assignment**

For each assignment, replace:

```python
image.place_id = incoming_place_id
```

with:

```python
if incoming_place_id:
    place = await Place.get(incoming_place_id)
    if place is None:
        raise HTTPException(status_code=404, detail="Place not found")
    effective = await resolve_place_for_use(place, current_user)
    image.place_id = effective.id
```

Adapt the shape to match the surrounding variable names. If the endpoint allows clearing place_id (setting to None), branch explicitly — don't call resolve on a None value.

- [ ] **Step 4: Sanity-check with the existing test suite**

```bash
cd services/api && pytest tests/ -v
```

Expected: no regressions. The new helper's unit tests still pass.

- [ ] **Step 5: Commit**

```bash
git add services/api/app/routers/images.py
git commit -m "feat(api): images endpoint rejects stale places and auto-redirects merged"
```

---

## Task A13: Wire `resolve_place_for_use` into route endpoints

**Files:**
- Modify: `services/api/app/routers/routes.py` — `create_route` and `update_route` (or equivalents) where place is dereferenced via the image

- [ ] **Step 1: Find where routes touch place**

Run:

```bash
cd services/api && grep -n "place" app/routers/routes.py
```

Routes attach to images, not directly to places. The "place a route belongs to" is `route.image.place_id`. The spec requires blocking "new route on an image whose place is not usable." So in `create_route` and `update_route` (any endpoint that creates a Route), after fetching the image, if `image.place_id` is set, resolve it:

```python
if image.place_id:
    place = await Place.get(image.place_id)
    if place is not None:
        effective = await resolve_place_for_use(place, current_user)
        if effective.id != image.place_id:
            # Opportunistic lazy-migration: correct the image's place_id to the merged target.
            image.place_id = effective.id
            await image.save()
```

- [ ] **Step 2: Add imports**

```python
from app.models.place import Place
from app.services.place_status import resolve_place_for_use
```

- [ ] **Step 3: Insert the check in `create_route`**

Right after the image is loaded and validated (around line 96-102 — `image = await Image.find_one(...)`), add the block above before proceeding to construct the Route.

- [ ] **Step 4: Insert the check in update-route endpoint(s)**

If the update endpoint doesn't reload the image, load it first. Any route create/update that could introduce new content tied to a stale place must run this check.

- [ ] **Step 5: Run tests to catch regressions**

```bash
cd services/api && pytest tests/ -v
```

- [ ] **Step 6: Commit**

```bash
git add services/api/app/routers/routes.py
git commit -m "feat(api): route create/update guards against stale place"
```

---

## Task A14: Share page — pass `place_status` to template

**Files:**
- Modify: `services/api/app/routers/share.py:66-99`

- [ ] **Step 1: Collect `place_status` alongside `place.name`**

In `share_route`, modify the description-building block (currently lines 74-80) to also capture `place.status`:

```python
    # 설명 생성
    description_parts = [route.grade]
    place_status: Optional[str] = None
    if image and image.place_id:
        place = await Place.get(image.place_id)
        if place:
            description_parts.append(place.name)
            place_status = place.status
    description = " · ".join(description_parts)
```

Ensure `Optional` is imported at top (`from typing import Optional`).

- [ ] **Step 2: Pass `place_status` into the template context**

Change the final `templates.TemplateResponse(...)` call (lines 85-99) to include `place_status`:

```python
    return templates.TemplateResponse(
        "share_route.html",
        {
            "request": request,
            "title": title,
            "description": description,
            "image_url": str(route.image_url).replace(
                "storage.cloud.google.com", "storage.googleapis.com"
            ),
            "share_url": share_url,
            "deep_link_url": deep_link_url,
            "app_store_url": APP_STORE_URL,
            "play_store_url": PLAY_STORE_URL,
            "place_status": place_status,
        },
    )
```

- [ ] **Step 3: Commit**

```bash
git add services/api/app/routers/share.py
git commit -m "feat(api): pass place_status to share route template"
```

---

## Task A15: Share template — render pending badge

**Files:**
- Modify: `services/api/app/templates/share_route.html`

- [ ] **Step 1: Add badge CSS**

Inside the existing `<style>` block in `share_route.html`, append:

```css
        .pending-badge {
            display: inline-block;
            margin-left: 8px;
            padding: 2px 10px;
            font-size: 12px;
            font-weight: 600;
            color: #333;
            background: rgba(255,255,255,0.85);
            border-radius: 999px;
            vertical-align: middle;
        }
```

- [ ] **Step 2: Render the badge next to the title when pending**

Replace the existing `<h1>{{ title }}</h1>` line with:

```html
        <h1>{{ title }}{% if place_status == "pending" %}<span class="pending-badge">검수중</span>{% endif %}</h1>
```

- [ ] **Step 3: Manual smoke (optional at this step)**

After deploy: visit a share URL for a route whose image's place is `pending` — verify "검수중" pill visible next to the title.

- [ ] **Step 4: Commit**

```bash
git add services/api/app/templates/share_route.html
git commit -m "feat(api): show 검수중 badge on share page for pending places"
```

---

## Task M1: Mobile — add `status` to `PlaceData`

**Files:**
- Modify: `apps/mobile/lib/models/place_data.dart`

- [ ] **Step 1: Add the field and parse it**

Replace the file contents with:

```dart
class PlaceData {
  final String id;
  final String name;
  final String type; // "gym" | "private-gym"
  final String status; // "pending" | "approved" | "rejected" | "merged"
  final double? latitude;
  final double? longitude;
  final String? coverImageUrl;
  final String createdBy;
  final double? distance;

  PlaceData({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
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
      status: (json['status'] as String?) ?? 'approved',
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      coverImageUrl: json['coverImageUrl'],
      createdBy: json['createdBy'],
      distance: json['distance']?.toDouble(),
    );
  }

  bool get isPending => status == 'pending';
}
```

The default `"approved"` lets the app keep working even if the server deploy is delayed (backwards-tolerant on the client side only — the server still requires the field going forward).

- [ ] **Step 2: Run analyzer**

```bash
cd apps/mobile && flutter analyze
```

Expected: passes. (Some call sites may need `status: ...` added — fix as analyzer reports.)

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/models/place_data.dart
git commit -m "feat(mobile): parse status field on PlaceData"
```

---

## Task M2: Mobile — `PlacePendingBadge` widget

**Files:**
- Create: `apps/mobile/lib/widgets/place_pending_badge.dart`

- [ ] **Step 1: Create the widget**

```dart
import 'package:flutter/material.dart';

class PlacePendingBadge extends StatelessWidget {
  const PlacePendingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        '검수중',
        style: TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyzer**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/place_pending_badge.dart
git commit -m "feat(mobile): add PlacePendingBadge reusable widget"
```

---

## Task M3: Mobile — badge in `place_selection_sheet` list items and chip

**Files:**
- Modify: `apps/mobile/lib/widgets/editors/place_selection_sheet.dart`

- [ ] **Step 1: Import the badge**

Add `import '../place_pending_badge.dart';` near the top.

- [ ] **Step 2: Wrap place name with badge in list item builders**

Locate where list item tile text is built for nearby/instant-search results. The rendering typically looks like:

```dart
Text(place.name, ...)
```

Wrap in a Row:

```dart
Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Flexible(child: Text(place.name, overflow: TextOverflow.ellipsis)),
    if (place.isPending) const SizedBox(width: 6),
    if (place.isPending) const PlacePendingBadge(),
  ],
)
```

Do this for each place list rendering path (nearby, private, search). Use grep in the file to find each `Text(...name...)` occurrence tied to a PlaceData render.

- [ ] **Step 3: Badge in the selected-place chip**

If the sheet (or a parent/caller surface) renders a chip preview of the currently-selected PlaceData, apply the same Row-with-badge pattern. Start from the call sites of `PlaceSelectionSheet.show` and trace where the returned PlaceData is displayed to the user.

- [ ] **Step 4: Run analyzer**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/editors/place_selection_sheet.dart
git commit -m "feat(mobile): show 검수중 badge for pending places in selection sheet"
```

---

## Task M4: Mobile — register mode CTA / banner / toast

**Files:**
- Modify: `apps/mobile/lib/widgets/editors/place_selection_sheet.dart`

- [ ] **Step 1: Update the CTA label**

Find the register-mode submit button (the one currently labeled "등록"). Change the label to "등록 요청".

- [ ] **Step 2: Add the top banner on register mode**

At the top of the register mode's scrollable body (before the name input), insert a banner:

```dart
Container(
  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: Colors.blue.shade50,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.blue.shade100),
  ),
  child: const Text(
    '등록 요청 후에도 바로 이 장소에 벽 사진과 루트를 올릴 수 있어요. '
    '운영진 검수를 통과하면 다른 분들에게도 노출됩니다. '
    '기존 장소와 중복되면 병합되고, 정책에 맞지 않으면 반려될 수 있어요.',
    style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.45),
  ),
)
```

Show this banner only when the registration type is `gym` (not `private-gym`). Tie to the existing `_isPrivate` state (at line 77) — wrap with `if (!_isPrivate) Container(...)`.

- [ ] **Step 3: Show the success toast**

In the submit handler (where `PlaceService.createPlace` is awaited), after a successful creation and before closing the sheet, for `type == "gym"` show a `SnackBar`:

```dart
if (type == 'gym' && mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('등록 요청이 접수됐어요. 검수 후 다른 분들에게도 노출돼요.'),
      duration: Duration(seconds: 4),
    ),
  );
}
```

- [ ] **Step 4: Run analyzer**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/editors/place_selection_sheet.dart
git commit -m "feat(mobile): register-as-request CTA, top banner, and ack toast"
```

---

## Task M5: Mobile — `deletePlace` service + 409 exception type

**Files:**
- Modify: `apps/mobile/lib/services/place_service.dart`

- [ ] **Step 1: Add a typed exception class**

At the top of the file (after imports, before the class), add:

```dart
class PlaceNotUsableException implements Exception {
  final String placeId;
  final String placeName;
  final String placeStatus;
  PlaceNotUsableException({
    required this.placeId,
    required this.placeName,
    required this.placeStatus,
  });

  @override
  String toString() =>
      'PlaceNotUsableException(placeId=$placeId, status=$placeStatus)';
}
```

Exported for use by image/route upload callers.

- [ ] **Step 2: Add `deletePlace` method to `PlaceService`**

Inside the class (after `updatePlace`):

```dart
  static Future<void> deletePlace(String placeId) async {
    final response = await AuthorizedHttpClient.delete('/places/$placeId');
    if (response.statusCode != 204) {
      throw Exception('Failed to delete place. Status: ${response.statusCode}');
    }
  }
```

If `AuthorizedHttpClient` doesn't have a `delete` method, add one following the same pattern as `get`. Check `apps/mobile/lib/services/http_client.dart` first.

- [ ] **Step 3: Run analyzer**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/services/place_service.dart apps/mobile/lib/services/http_client.dart
git commit -m "feat(mobile): deletePlace service + PlaceNotUsableException type"
```

---

## Task M6: Mobile — edit & delete buttons on own pending place

**Files:**
- Modify: `apps/mobile/lib/widgets/editors/place_selection_sheet.dart`
- Possibly: `apps/mobile/lib/widgets/editors/place_edit_pane.dart`

- [ ] **Step 1: Identify the current "정보 수정 제안" button location**

Find the row/footer currently rendered below a gym place item (the existing "정보 수정 제안" trigger). It likely conditional-renders based on the place being selected.

- [ ] **Step 2: Add a branch for own pending**

For each list-item render of `PlaceData`, check:
- `place.isPending && place.createdBy == currentUser.id` → show **정보 수정** (direct edit)
- `!place.isPending && place.type == 'gym'` → show existing **정보 수정 제안**

Layout: "정보 수정" button on the left, **삭제** icon (🗑) on the far right with at least 24-32 px horizontal spacing (enforce via `Expanded` or `Spacer` between them).

```dart
Row(
  children: [
    TextButton.icon(
      icon: const Icon(Icons.edit_outlined, size: 16),
      label: const Text('정보 수정'),
      onPressed: () => _openDirectEdit(place),
    ),
    const Spacer(),
    IconButton(
      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
      tooltip: '등록 요청 취소',
      onPressed: () => _confirmDelete(place),
    ),
  ],
)
```

- [ ] **Step 3: Implement `_openDirectEdit`**

This opens the existing `PlaceEditPane` (or equivalent edit page) in "direct edit" mode that calls `PlaceService.updatePlace` — not the suggestion flow. Pass a flag like `isDirectEdit: true` so the pane knows to call update vs. suggestion.

- [ ] **Step 4: Implement `_confirmDelete`**

```dart
Future<void> _confirmDelete(PlaceData place) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('등록 요청 취소'),
      content: const Text(
        '등록 요청을 취소하고 지금까지 이 장소에 올린 이미지와 루트를 모두 삭제할까요?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('삭제', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await PlaceService.deletePlace(place.id);
    // refresh current list tab (nearby/search)
    if (mounted) {
      setState(() {
        _nearbyPlaces.removeWhere((p) => p.id == place.id);
        _privatePlaces.removeWhere((p) => p.id == place.id);
        _searchResults.removeWhere((p) => p.id == place.id);
      });
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    }
  }
}
```

- [ ] **Step 5: Notify callers that selected place was deleted**

If the `currentPlace` passed to the sheet was just deleted, ensure downstream (caller) clears its selection. A clean way: `PlaceSelectionSheet.show` resolves with `null` when the caller's current place was deleted. Add a signal (e.g. `Navigator.pop(context, null)` on delete of the current selection), and document in the sheet's return contract.

- [ ] **Step 6: Run analyzer**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/widgets/editors/
git commit -m "feat(mobile): direct edit and delete actions on own pending place"
```

---

## Task M7: Mobile — edit pane guide banner for pending gyms

**Files:**
- Modify: `apps/mobile/lib/widgets/editors/place_edit_pane.dart`

- [ ] **Step 1: Add a guide banner at the top when in direct-edit mode for a pending gym**

Near the top of the pane's body, conditionally insert:

```dart
if (place.isPending && place.type == 'gym')
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
```

- [ ] **Step 2: Ensure direct-edit mode calls `updatePlace`, not the suggestion endpoint**

Inside the save handler, branch on whether the pane was opened for a pending-owner gym vs. an approved gym. If pending-owner → `PlaceService.updatePlace(...)`. If approved → `PlaceService.createSuggestion(...)` (existing behavior).

- [ ] **Step 3: Run analyzer**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/widgets/editors/place_edit_pane.dart
git commit -m "feat(mobile): guide banner and direct-update path on pending edit"
```

---

## Task M8: Mobile — `PlaceNotUsableDialog` + 409 handling at upload/edit call sites

**Files:**
- Create: `apps/mobile/lib/widgets/place_not_usable_dialog.dart`
- Modify: each call site that uploads/edits an image or route (identified below)

- [ ] **Step 1: Create the dialog widget**

`apps/mobile/lib/widgets/place_not_usable_dialog.dart`:

```dart
import 'package:flutter/material.dart';

Future<void> showPlaceNotUsableDialog(
  BuildContext context, {
  required String placeName,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(
        '해당 $placeName는 쓸 수 없는 상태입니다.\n다른 장소를 선택해주세요.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 2: Parse 409 responses into `PlaceNotUsableException`**

In `apps/mobile/lib/services/`, find every service method that uploads or updates an image/route. Wherever the code currently does `throw Exception('Failed…')` on non-2xx status, enhance to:

```dart
if (response.statusCode == 409) {
  try {
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final detail = body['detail'];
    if (detail is Map && detail['code'] == 'PLACE_NOT_USABLE') {
      throw PlaceNotUsableException(
        placeId: detail['place_id'] as String? ?? '',
        placeName: detail['place_name'] as String? ?? '',
        placeStatus: detail['place_status'] as String? ?? '',
      );
    }
  } catch (e) {
    if (e is PlaceNotUsableException) rethrow;
    // fall through to generic handling
  }
}
```

Services to update (identify with grep):

```bash
cd apps/mobile && grep -rln "multipartPost\|multipartRequest" lib/services/
```

Apply to the image-upload service and route-create/update service. Keep `PlaceNotUsableException` imported from `place_service.dart`.

- [ ] **Step 3: Catch in the UI layers that trigger uploads/edits**

In every widget/screen that calls these services, wrap the call:

```dart
try {
  await ImageService.upload(/* … */);
} on PlaceNotUsableException catch (e) {
  if (!context.mounted) return;
  await showPlaceNotUsableDialog(context, placeName: e.placeName);
  // DO NOT clear local work state (image file, polygons, form fields).
}
```

Identify the call sites:

```bash
cd apps/mobile && grep -rln "ImageService\|RouteService\|createRoute\|uploadImage" lib/
```

For each, add the try/on block around the service call and ensure local state is preserved (no `setState` resets, no file cleanup).

- [ ] **Step 4: Run analyzer**

```bash
cd apps/mobile && flutter analyze
```

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/
git commit -m "feat(mobile): 409 PLACE_NOT_USABLE dialog preserving in-progress work"
```

---

## Task Z1: Deploy prep — backfill and index notes

This task has no code changes. It captures the operational work for the deployer.

- [ ] **Step 1: Write deploy notes file**

Create `docs/superpowers/plans/2026-04-18-place-registration-request-deploy.md`:

```markdown
# Place Registration Request — Deploy Notes

## Pre-deploy (run BEFORE API deploy)

MongoDB Atlas shell:

```
db.places.updateMany(
  { status: { $exists: false } },
  { $set: { status: "approved" } }
)
```

Reason: the new API filters by `status: "approved"` with exact-match; without this
backfill, existing approved gyms disappear from nearby/instant-search until the
field is present.

## Pre-deploy (optional)

```
db.places.createIndex({ type: 1, status: 1 })
```

Supports the new compound filter.

## Deploy order

1. Run backfill (above).
2. (Optional) Create compound index.
3. Deploy API (`services/api/deploy.sh`).
4. Deploy mobile binaries.

## Smoke checklist (post-deploy)

- [ ] Register a new gym → status=pending, ack notification received.
- [ ] Own pending place visible on nearby / instant-search with "검수중" badge.
- [ ] Pending place "정보 수정" works; guide banner visible.
- [ ] Pending place delete removes place + linked images + routes.
- [ ] DB-flip a place to rejected → upload image with its id → 409 popup, local work preserved.
- [ ] DB-flip a place to merged with a valid target → upload image with its id → success, saved image shows target place.
- [ ] Share URL for a pending place's route → "검수중" badge visible.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/2026-04-18-place-registration-request-deploy.md
git commit -m "docs: deploy notes and smoke checklist for place registration flow"
```

---

## Spec Coverage Map

| Spec section | Covered by |
|---|---|
| §1 Data model — `status` default | A1 |
| §1 Data model — `merged_into_place_id` | A1 |
| §1 Data model — index | A1 |
| §1 Data model — no migration code | (no task; DB shell command in Z1) |
| §2-1 POST /places | A3, A4 |
| §2-2 GET /places/nearby filter | A7 |
| §2-2 GET /places/instant-search filter | A8 |
| §2-3 PUT /places/{id} permission | A9 |
| §2-4 DELETE /places/{id} | A10 |
| §2-5 POST /places/suggestions policy + body | A5, A6 |
| §2-6 PlaceView.status | A2 |
| §3 resolve_place_for_use | A11 |
| §3 Image endpoints wired | A12 |
| §3 Route endpoints wired | A13 |
| §4-1 Register CTA / banner / toast | M4 |
| §4-2 PlacePendingBadge | M2, M3 |
| §4-3 Pending edit + delete buttons | M6 |
| §4-4 Edit guide banner | M7 |
| §4-5 409 popup preserving work | M8 |
| §4-6 rejected/merged client — no-op | (implicit: we pass through status, no extra UI) |
| §5 Share page badge | A14, A15 |
| §6 Tests | A1, A2, A11 (unit); smoke list in Z1 |
| §7 Deploy checklist | Z1 |
| §8 Future work notes | (spec; no task) |
