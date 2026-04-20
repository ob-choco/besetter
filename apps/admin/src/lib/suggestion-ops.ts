import type { ObjectId } from "mongodb";
import { getDb, getMongoClient } from "@/lib/mongo";
import { get as getConfig } from "@/lib/config";
import type {
  PlaceDoc,
  PlaceSuggestionDoc,
  UserDoc,
} from "@/lib/db-types";
import { notify } from "@/lib/notifications";
import { normalizeName } from "@/lib/normalize";
import { AdminOpError } from "@/lib/place-ops";

export type SuggestionListItem = PlaceSuggestionDoc & {
  place: {
    _id: PlaceDoc["_id"];
    name: string;
    normalizedName: string;
    status: PlaceDoc["status"];
    type: PlaceDoc["type"];
    coverImageUrl: string | null;
  };
  requester: { profileId: string; profileImageUrl: string | null } | null;
};

export async function getPendingSuggestions(): Promise<SuggestionListItem[]> {
  const db = await getDb();
  const pending = await db
    .collection<PlaceSuggestionDoc>("placeSuggestions")
    .find({ status: "pending" })
    .sort({ createdAt: 1 })
    .toArray();
  if (pending.length === 0) return [];
  const placeIds = pending.map((s) => s.placeId);
  const userIds = pending.map((s) => s.requestedBy);
  const [places, users] = await Promise.all([
    db.collection<PlaceDoc>("places").find({ _id: { $in: placeIds } }).toArray(),
    db.collection<UserDoc>("users").find({ _id: { $in: userIds } }).toArray(),
  ]);
  const placeById = new Map(places.map((p) => [p._id.toString(), p]));
  const userById = new Map(users.map((u) => [u._id.toString(), u]));
  return pending
    .map((s) => {
      const p = placeById.get(s.placeId.toString());
      if (!p) return null;
      const u = userById.get(s.requestedBy.toString());
      return {
        ...s,
        place: {
          _id: p._id,
          name: p.name,
          normalizedName: p.normalizedName,
          status: p.status,
          type: p.type,
          coverImageUrl: p.coverImageUrl ?? null,
        },
        requester: u
          ? { profileId: u.profileId, profileImageUrl: u.profileImageUrl ?? null }
          : null,
      } satisfies SuggestionListItem;
    })
    .filter((x): x is SuggestionListItem => x !== null);
}

export type SuggestionDetail = SuggestionListItem & {
  currentPlace: PlaceDoc;
};

export async function getSuggestionDetail(id: ObjectId): Promise<SuggestionDetail | null> {
  const db = await getDb();
  const s = await db.collection<PlaceSuggestionDoc>("placeSuggestions").findOne({ _id: id });
  if (!s) return null;
  const place = await db.collection<PlaceDoc>("places").findOne({ _id: s.placeId });
  if (!place) return null;
  const user = await db.collection<UserDoc>("users").findOne({ _id: s.requestedBy });
  return {
    ...s,
    place: {
      _id: place._id,
      name: place.name,
      normalizedName: place.normalizedName,
      status: place.status,
      type: place.type,
      coverImageUrl: place.coverImageUrl ?? null,
    },
    requester: user
      ? { profileId: user.profileId, profileImageUrl: user.profileImageUrl ?? null }
      : null,
    currentPlace: place,
  };
}

export async function approveSuggestion(suggestionId: ObjectId): Promise<void> {
  const client = await getMongoClient();
  const db = client.db(await getConfig("mongodb.name"));
  const session = client.startSession();
  let createdPlaceName = "";
  let requestedBy: ObjectId | null = null;
  try {
    await session.withTransaction(async () => {
      const s = await db
        .collection<PlaceSuggestionDoc>("placeSuggestions")
        .findOne({ _id: suggestionId, status: "pending" }, { session });
      if (!s) throw new AdminOpError("CONFLICT", "suggestion is not pending");
      const place = await db
        .collection<PlaceDoc>("places")
        .findOne({ _id: s.placeId, status: "approved" }, { session });
      if (!place) throw new AdminOpError("CONFLICT", "target place is not approved");

      const changes = s.changes ?? {};
      const set: Record<string, unknown> = {};
      if (changes.name != null) {
        set.name = changes.name;
        set.normalizedName = normalizeName(changes.name);
      }
      if (changes.latitude != null && changes.longitude != null) {
        set.location = {
          type: "Point",
          coordinates: [changes.longitude, changes.latitude],
        };
      }
      if (changes.coverImageUrl != null) {
        set.coverImageUrl = changes.coverImageUrl;
      }
      if (Object.keys(set).length === 0) {
        throw new AdminOpError("BAD_REQUEST", "suggestion has no changes");
      }
      await db.collection<PlaceDoc>("places").updateOne({ _id: place._id }, { $set: set }, { session });
      await db.collection<PlaceSuggestionDoc>("placeSuggestions").updateOne(
        { _id: suggestionId, status: "pending" },
        { $set: { status: "approved", reviewedAt: new Date() } },
        { session },
      );
      createdPlaceName = (set.name as string | undefined) ?? place.name;
      requestedBy = s.requestedBy;
    });
  } finally {
    await session.endSession();
  }

  if (!requestedBy) return;
  await notify({
    userId: requestedBy,
    type: "place_suggestion_approved",
    params: { place_name: createdPlaceName },
    link: null,
  });
}

export async function rejectSuggestion(
  suggestionId: ObjectId,
  reason?: string,
): Promise<void> {
  const db = await getDb();
  const result = await db
    .collection<PlaceSuggestionDoc>("placeSuggestions")
    .findOneAndUpdate(
      { _id: suggestionId, status: "pending" },
      { $set: { status: "rejected", reviewedAt: new Date() } },
      { returnDocument: "before" },
    );
  if (!result) throw new AdminOpError("CONFLICT", "suggestion is not pending");
  const place = await db.collection<PlaceDoc>("places").findOne({ _id: result.placeId });
  await notify({
    userId: result.requestedBy,
    type: "place_suggestion_rejected",
    params: {
      place_name: place?.name ?? "",
      reason_suffix: reason ? ` 사유: ${reason}` : "",
    },
    link: null,
  });
}
