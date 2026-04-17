# 암장 등록 요청 플로우 설계

**Goal.** 유저가 `gym` 장소를 등록할 때 즉시 생성 대신 "등록 요청"으로 동작하게 하고, 요청자 본인은 pending 상태인 장소를 바로 사용할 수 있게 한다. 관리자가 별도 검수 툴에서 `approved / rejected / merged` 중 하나로 전이시키는 전제를 만들고, 그때까지 클라이언트가 stale한 상태로 동작하지 않도록 방어한다.

**Scope in.**
- `Place` 모델에 `status`, `merged_into_place_id` 필드 추가.
- `POST /places` 동작 변경: `gym`=pending, `private-gym`=approved. gym 생성 시 요청자에게 감사 알림 1건 생성 (type=`place_registration_ack`).
- `GET /places/nearby`, `GET /places/instant-search` 필터에 상태 조건 추가 (본인 pending 포함, 타인의 pending은 제외).
- `PUT /places/{place_id}` 권한 확장: 본인 소유 pending gym도 허용.
- `DELETE /places/{place_id}` 신규: 본인 소유 pending gym만 허용, 연결된 Route/Image/GCS blob을 순차 best-effort cascade로 삭제.
- `POST /places/suggestions` 정책 업데이트: `status != "approved"`는 400. 기존 `place_suggestion_ack` 알림 body 문구 교체.
- 이미지/루트의 place_id를 받는 등록/수정 엔드포인트에 `PLACE_NOT_USABLE` 409 방어.
- 모바일: pending 장소 "검수중" 뱃지, pending 장소 정보 수정 버튼 + 가이드 배너, 삭제 버튼, 409 stale 장소 팝업 (작업 상태 보존).
- `share_route.html` OG 공유 페이지에 pending place의 "검수중" 뱃지 표시.

**Scope out (명시적).**
- 관리자 검수 툴 (별도 Next.js 프로젝트 예정). 이 스펙에는 **admin role을 요구하는 엔드포인트를 일절 추가하지 않음.** 상태 전이는 개발 단계에서 DB 직접 조작, 운영 단계에서 외부 검수 툴이 수행.
- `pending → approved / rejected / merged` 전이 시 부작용 (rejected에서 이미지/루트 soft delete, merged에서 이미지 place_id 업데이트). 전부 검수 툴 스펙에서 다룬다.
- 검수 결과 알림 (approved/rejected/merged 각각). 기존 notification 인프라가 이미 있으므로 메시지만 추가하면 되는 작업이라 별도 후속 스펙에서 다룬다.
- "내 등록 요청" 전용 UI. pending 장소는 본인 검색 결과에 "검수중" 뱃지와 함께 나오므로 충분.
- 409 응답의 `merged_into_place_id`를 이용한 "병합 타겟 바로 이동" 버튼. v1 밖.
- 소프트 삭제 관련 기존 필터 누락 지점 (e.g. `routes.py:285`의 image 조인)의 선제적 보강. 별도 tech-debt 이슈.

---

## 1. 데이터 모델

### 1-1. `Place` 필드 추가

```python
class Place(Document):
    # ...기존 필드 유지...
    status: Literal["pending", "approved", "rejected", "merged"] = "approved"
    merged_into_place_id: Optional[PydanticObjectId] = None
```

- `status` default는 `"approved"` — Pydantic/Beanie가 필드 없는 기존 도큐먼트를 읽을 때는 default로 채워진다. 다만 **MongoDB 쿼리 레벨에서 `status: "approved"` exact match는 필드 없는 기존 도큐먼트와 매칭되지 않는다** — 검색/근처 쿼리가 기존 approved 장소를 누락하지 않도록 배포 시 DB-level backfill 필수 (§7 배포 체크리스트 참고). 코드 차원 마이그레이션 스크립트는 작성하지 않는다.
- `merged_into_place_id`는 모델 정의만 두고 이 스펙에서는 읽지도 쓰지도 않는다. 검수 툴이 merge 실행 시 set.

### 1-2. 생성 시 상태 규칙

| `type` | 생성 시 `status` |
|---|---|
| `gym` | `pending` |
| `private-gym` | `approved` |

### 1-3. 상태 전이 규칙 (참고)

```
pending ──approve (admin, 후속)──▶ approved
pending ──reject  (admin, 후속)──▶ rejected
pending ──merge   (admin, 후속)──▶ merged  (+ merged_into_place_id)
pending ──cancel  (요청자 본인)──▶ [hard delete]
approved ──(이 스펙에서 변경 엔드포인트 없음)──▶ approved
```

`cancelled`는 enum 멤버가 아니다. 본인 취소는 DB에서 레코드와 연결 데이터가 완전히 제거된다.

### 1-4. 인덱스

(기존 `location` 2dsphere 인덱스 유지)

추가 권장:
```
{ "type": 1, "status": 1 }
```

검색 필터의 왼쪽 조건이 `type`, `status`이므로 복합 인덱스가 유용. 배포 시 수동 추가 (별도 migration 코드 없음).

---

## 2. API 변경

### 2-1. `POST /places` (기존 수정)

- 요청 바디/필드 유지 (`name`, `type`, `latitude`, `longitude`, `image`).
- 저장 시 `status` 설정:
  - `type == "gym"` → `status = "pending"`
  - `type == "private-gym"` → `status = "approved"`
- **`type == "gym"`인 경우**, 저장 성공 직후 감사 알림 1건 생성 (기존 `place_suggestion_ack` 패턴을 그대로 복제, best-effort try/except):
  - `type`: `place_registration_ack`
  - `title`: `암장 등록 요청이 접수되었습니다`
  - `body`: `{place_name} 등록을 요청해주신 소중한 제보 감사합니다 🙌 서비스에 반영될 수 있도록 빠르게 처리해서 알려드리겠습니다.`
  - `link`: `/places/{place_id}`
  - 성공 시 `User.unreadNotificationCount`를 `$inc +1`.
- 응답 스키마 `PlaceView`에 `status` 필드 추가.

### 2-2. `GET /places/nearby`, `GET /places/instant-search` (필터 확장)

기존 쿼리의 `{type: "gym"}`에 상태 필터 추가:

```python
{
    "type": "gym",
    "$or": [
        {"status": "approved"},
        {"status": "pending", "createdBy": current_user.id},
    ],
    # nearby: location $nearSphere 등 기존 조건
    # instant-search: normalizedName regex 등 기존 조건
}
```

- `rejected`, `merged`는 필터에 포함 안 되므로 자동 제외.
- 응답 `PlaceView`에 `status` 필드 포함.

### 2-3. `PUT /places/{place_id}` (권한 확장)

현재: `private-gym` 소유자만 허용.

변경: 아래 두 케이스 모두 허용.
```python
is_allowed = (
    (place.type == "private-gym" and place.created_by == current_user.id)
    or (place.type == "gym" and place.status == "pending" and place.created_by == current_user.id)
)
if not is_allowed:
    raise HTTPException(403, ...)
```

- 수정 가능한 필드는 기존과 동일 (`name`, `latitude`, `longitude`, `image`).
- 응답에도 `status` 포함.

### 2-4. `DELETE /places/{place_id}` (신규)

```python
@router.delete("/{place_id}", status_code=204)
async def delete_place(place_id, current_user):
    place = await Place.get(place_id)
    if place is None:
        raise HTTPException(404, ...)
    if not (place.type == "gym"
            and place.status == "pending"
            and place.created_by == current_user.id):
        raise HTTPException(403, "Only your own pending gym place can be deleted")

    # 순차 best-effort cascade (MongoDB 트랜잭션 미도입)
    #   1) 해당 place에 묶인 Route 전부 삭제 (hard delete)
    #   2) 해당 place에 묶인 Image 전부 삭제 (hard delete) + 각 image GCS blob 삭제
    #   3) 루프 중 실패는 로그, 다음 항목 계속
    #   4) Place 커버 이미지 GCS blob 삭제 (있으면)
    #   5) 마지막에 Place 자체 삭제

    # (세부 구현은 plan 단계에서)
    return Response(status_code=204)
```

- Route hard delete: `Route.find(Route.image_id.in_(image_ids_of_place)).delete()` 형태. Route 자체에 place 참조가 없으므로 Image 기준으로 연쇄.
- GCS blob 삭제 실패는 로그만 남김 (고아 blob은 운영 정리).
- Place를 마지막에 지워야 도중 실패해도 유저 눈에는 "일부만 사라진" 상태로 보이지 않고, 다시 시도 가능.

### 2-5. `POST /places/suggestions` (정책 변경 + 문구 교체)

- 기존: `private-gym`만 400.
- 추가: `place.status != "approved"`면 400 (`detail: "Suggestions are only allowed for approved places"`).
- 알림 body 문구 교체 (`places.py:322-326`):
  - Before: `"{place_name}에 대한 소중한 제보 감사합니다 🙌 운영진이 확인하고 반영할게요."`
  - After: `"{place_name}에 대한 소중한 제보 감사합니다 🙌 서비스에 반영될 수 있도록 빠르게 처리해서 알려드리겠습니다."`
  - `type`, `title`, `link`은 기존 유지.

### 2-6. `PlaceView` 스키마 확장

```python
class PlaceView(BaseModel):
    id: PydanticObjectId
    name: str
    type: str
    latitude: Optional[float]
    longitude: Optional[float]
    cover_image_url: Optional[str]
    created_by: PydanticObjectId
    distance: Optional[float] = None
    status: Literal["pending", "approved", "rejected", "merged"]  # 신규
```

`place_to_view` 헬퍼에서 `place.status`를 전달.

이미지/루트 응답에 embedded된 `PlaceView`도 자동으로 `status`를 포함하게 된다 (`images.py:44`의 `place: Optional[PlaceView]`).

---

## 3. 이미지/루트에서의 stale 장소 방어

### 3-1. 공통 헬퍼

```python
def assert_place_usable(place: Place, user: User) -> None:
    if place.status == "approved":
        return
    if place.status == "pending" and place.created_by == user.id:
        return
    raise HTTPException(
        status_code=409,
        detail={
            "code": "PLACE_NOT_USABLE",
            "place_id": str(place.id),
            "place_name": place.name,
            "place_status": place.status,
            "merged_into_place_id": str(place.merged_into_place_id) if place.merged_into_place_id else None,
        },
    )
```

### 3-2. 적용 엔드포인트

- 이미지 업로드: place_id가 요청에 있을 때 호출.
- 이미지 수정 (place_id 변경 포함): 변경 요청된 place_id에 대해 호출.
- 루트 생성 / 수정: 루트는 image를 통해 간접 연결이므로, 루트 생성·수정 시점에 해당 image의 `place_id`에 대해 검증. 이미 같은 이미지에 다른 루트들이 존재하는 상황이라도 "새 루트 추가"는 place 상태에 종속.

실제 적용 위치와 함수 시그니처는 plan 단계에서 라우터별로 식별 (`routes.py`, `images.py`, `hold_polygons.py` 등에서 place_id 경유 지점 전수 조사).

### 3-3. 응답 페이로드

```json
{
  "detail": {
    "code": "PLACE_NOT_USABLE",
    "place_id": "6620...",
    "place_name": "홍대 클라이밍",
    "place_status": "rejected",
    "merged_into_place_id": null
  }
}
```

`place_name`이 응답에 담겨 있어 클라이언트가 보유한 stale한 이름에 의존하지 않는다.

---

## 4. 모바일 UX

### 4-1. 장소 등록 요청 (place_selection_sheet.dart 등록 모드)

- CTA 문구: `등록` → `등록 요청`
- 생성 성공 시 토스트/스낵바 1회: `등록 요청이 접수되었어요. 검수 후 반영됩니다.`
- 응답의 `status`를 저장하여 이후 화면에서 뱃지 판단에 사용.
- 이후 플로우는 기존과 동일 — 요청자 본인은 바로 pending 장소를 선택해서 이미지/루트 업로드 가능.

### 4-2. "검수중" 뱃지

공통 위젯 `PlacePendingBadge` 추출해 재사용.

| 노출 위치 | 조건 |
|---|---|
| `place_selection_sheet` 리스트 아이템 | `place.status == "pending"` |
| 이미지/루트 상세의 place 라벨 | `place.status == "pending"` |
| 업로드 중 선택된 place chip | `place.status == "pending"` |

시각 스타일은 디자인 확정 시 조정. 뱃지 텍스트는 `검수중`.

### 4-3. Pending 장소 정보 수정 / 삭제 (place_selection_sheet)

pending 장소 아이템 풋터에 두 버튼 (요청자 본인에게만):

- **정보 수정** (좌측) — 기존 "정보 수정 제안" 자리에 대체해서 노출. 탭 시 기존 edit 페이지 재사용 (`PUT /places/{id}` 호출).
- **삭제** (우측 끝, 아이콘 형태) — 수정 버튼과 충분히 떨어뜨려 오탭 방지.
  - 탭 시 확인 다이얼로그:
    - `등록 요청을 취소하고 지금까지 이 장소에 올린 이미지와 루트를 모두 삭제할까요?`
    - 버튼: `취소` / `삭제`
  - 확인 시 `DELETE /places/{id}` 호출, 성공 후 목록 리프레시 + 해당 장소를 선택 중인 화면 있으면 place unset.

### 4-4. 정보 수정 페이지 상단 가이드 배너

pending gym 정보 수정 페이지에만 노출:

> 승인되기 전까지는 자유롭게 수정할 수 있어요. 승인된 이후에는 다른 분들도 쓰게 되므로, 그때부터는 "정보 수정 제안"으로 요청해주시면 반영해드립니다.

### 4-5. Stale 장소 409 팝업

이미지/루트 등록·수정 중 `PLACE_NOT_USABLE` 응답을 받은 경우:

```
┌────────────────────────────────────────┐
│ 해당 {place_name}는 쓸 수 없는 상태입니다. │
│ 다른 장소를 선택해주세요.                  │
│                                          │
│                         [ 확인 ]          │
└────────────────────────────────────────┘
```

- 버튼은 **확인 1개**만. 팝업 닫힘.
- 업로드한 이미지 파일, 그린 폴리곤/루트 데이터, 입력한 벽 이름 등 **로컬 작업 상태는 전부 유지**. 사용자가 확인 후 필요 시 스스로 장소 선택 UI를 다시 열어 새 장소 지정.
- `place_name`은 서버 응답의 `detail.place_name`을 사용 (클라이언트 stale 이름에 의존 X).

### 4-6. rejected/merged 장소의 클라이언트 표시

이번 스펙에서는 별도 처리 없음. `status` 필드를 저장만 하고, 뱃지는 `pending`에만 표시.

이유:
- 검수 툴이 rejected 시 연결 이미지/루트를 soft delete하므로 일반 뷰어에는 노출되지 않음.
- merged 시 이미지의 `place_id`가 대상 place로 업데이트되므로 라벨에는 target 장소명이 보임.

방어 코드가 필요한 시점은 검수 툴 스펙에서 같이 다룬다.

---

## 5. 공유 URL (share_route.html)

### 5-1. pending place 뱃지

`share.py`에서 place를 가져온 뒤 `place.status`를 템플릿 컨텍스트로 넘긴다.

```python
# share.py (현재 line 76-80 근처)
place_status = None
if image and image.place_id:
    place = await Place.get(image.place_id)
    if place:
        description_parts.append(place.name)
        place_status = place.status
```

템플릿 컨텍스트에 `place_status`를 추가하고, `share_route.html`에서 `place_status == "pending"`인 경우 제목 또는 설명 옆에 작은 `검수중` 뱃지 블록을 렌더링.

### 5-2. soft-deleted 루트 처리 (기존 유지)

`share.py:43`에서 `route is None or route.is_deleted` 경우 404 + `share_error.html` 노출. 별도 변경 없음.

### 5-3. rejected/merged place 처리

- rejected: 검수 툴이 연결 route까지 cascade soft delete → 기존 `route.is_deleted` 가드에서 404.
- merged: 이미지 `place_id`가 대상 place로 업데이트되므로 공유 페이지는 대상 place 이름을 자연스럽게 보여줌.
- 본 스펙에선 추가 조치 없음.

---

## 6. 테스트

### 6-1. API (pytest)

- `POST /places`
  - `type=gym` → 201, `status=pending`, `place_registration_ack` 알림 1건.
  - `type=private-gym` → 201, `status=approved`, 알림 없음.
- `GET /places/nearby`
  - 다른 유저의 pending 장소 제외.
  - 본인 pending 장소 포함.
  - rejected/merged는 모두 제외.
- `GET /places/instant-search`: 동일.
- `PUT /places/{id}`
  - 본인 pending gym: 200.
  - 본인 private-gym: 200 (기존 동작).
  - 남의 pending gym: 403.
  - 본인이지만 approved gym: 403.
- `DELETE /places/{id}`
  - 본인 pending gym + 연결된 Image/Route: 204, 해당 레코드 모두 사라짐.
  - 본인 approved gym: 403.
  - 남의 pending gym: 403.
- `POST /places/suggestions`
  - pending/rejected/merged place → 400.
  - approved place → 201, 알림 body가 새 문구.
- 이미지/루트 등록·수정
  - rejected place_id 지정 → 409 `PLACE_NOT_USABLE`, detail 포함 필드 검증.
  - merged place_id 지정 → 409, detail의 `merged_into_place_id` 채워짐.
  - 남의 pending place_id 지정 → 409.

### 6-2. 모바일 수동 스모크

- 새 암장 등록 요청 → 토스트 노출 + MY 알림에서 수신 확인.
- 본인 pending 장소가 nearby/instant-search 결과에 "검수중" 뱃지와 함께 노출.
- 본인 pending 장소 정보 수정 → 가이드 배너 보임 → 저장 성공.
- 본인 pending 장소 삭제 → 확인 다이얼로그 → 연결 이미지·루트 함께 사라짐.
- (DB 수동 조작) 장소를 `rejected`로 변경한 뒤 그 장소로 이미지 업로드 시도 → 409 팝업 노출, 팝업 닫힌 뒤에도 업로드할 이미지/입력값 유지.
- 공유 URL 웹 페이지 (pending place의 route): 뱃지 노출.

---

## 7. 배포 체크리스트

순서 중요 — API 배포 **전에** backfill을 반드시 수행한다. 그렇지 않으면 기존 approved 장소들이 `status` 필드가 없어 검색 결과에서 사라진다.

1. **기존 데이터 1회성 backfill (MongoDB shell, API 배포 전)**:
   ```
   db.places.updateMany(
     { status: { $exists: false } },
     { $set: { status: "approved" } }
   )
   ```
2. (옵션, 선제적) 복합 인덱스 추가:
   ```
   db.places.createIndex({ type: 1, status: 1 })
   ```
3. API 배포.
4. 모바일 버전 배포.

---

## 8. 향후 작업 노트 (이 스펙 밖)

- **검수 툴(Next.js) 스펙**이 별도로 작성되면 아래를 포함해야 함:
  - 관리자 인증 / admin 엔드포인트.
  - `pending → approved` 전이: Place.status만 변경.
  - `pending → rejected` 전이: Place.status 변경 + **해당 place의 모든 Image/Route/HoldPolygon을 soft delete (cascade)**.
  - `pending → merged(targetPlaceId)` 전이: Place.status 변경, `merged_into_place_id` 설정, **해당 place의 모든 Image의 place_id를 targetPlaceId로 업데이트**.
  - 각 전이에 대한 요청자 알림 (approved/rejected/merged 각각 메시지 정의).
- **소프트 삭제 필터 누락 지점 보강** (tech debt): `routes.py:285`의 image 조인, `routes.py:380`, `activities.py:179/203`, `hold_polygons.py:204/232`에 `is_deleted != True` 필터 추가 검토.
- 409 `PLACE_NOT_USABLE`의 `merged_into_place_id`를 활용한 "병합 타겟으로 바로 전환" 기능.
