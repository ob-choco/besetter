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
