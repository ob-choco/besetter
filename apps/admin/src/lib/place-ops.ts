import { getDb } from "@/lib/mongo";
import type { PlaceDoc, UserDoc } from "@/lib/db-types";

export type PendingPlaceView = PlaceDoc & {
  creator?: { profileId: string; profileImageUrl?: string | null } | null;
};

export async function getPendingPlaces(): Promise<PendingPlaceView[]> {
  const db = await getDb();
  const places = await db
    .collection<PlaceDoc>("places")
    .find({ type: "gym", status: "pending" })
    .sort({ createdAt: 1 })
    .toArray();
  if (places.length === 0) return [];
  const userIds = [...new Set(places.map((p) => p.createdBy.toString()))].map(
    (s) => places.find((p) => p.createdBy.toString() === s)!.createdBy,
  );
  const users = await db
    .collection<UserDoc>("users")
    .find({ _id: { $in: userIds } })
    .toArray();
  const byId = new Map<string, UserDoc>(users.map((u) => [u._id.toString(), u]));
  return places.map((p) => {
    const u = byId.get(p.createdBy.toString());
    return {
      ...p,
      creator: u ? { profileId: u.profileId, profileImageUrl: u.profileImageUrl ?? null } : null,
    };
  });
}
