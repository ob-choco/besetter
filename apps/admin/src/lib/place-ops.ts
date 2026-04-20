import type { ObjectId } from "mongodb";
import { getDb } from "@/lib/mongo";
import type { ActivityDoc, ImageDoc, PlaceDoc, UserDoc } from "@/lib/db-types";

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

function haversineMeters(a: [number, number], b: [number, number]): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const R = 6371008.8;
  const [lng1, lat1] = a;
  const [lng2, lat2] = b;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const x =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}

export type PlaceDetail = {
  place: PlaceDoc;
  creator: { profileId: string; profileImageUrl?: string | null } | null;
  counts: { imageCount: number; routeCount: number; activityCount: number };
  nearbyApproved: Array<PlaceDoc & { distanceMeters: number }>;
};

const NEARBY_RADIUS_METERS = 200;

export async function getPlaceDetail(id: ObjectId): Promise<PlaceDetail | null> {
  const db = await getDb();
  const place = await db.collection<PlaceDoc>("places").findOne({ _id: id });
  if (!place) return null;

  const user = await db.collection<UserDoc>("users").findOne({ _id: place.createdBy });

  const images = await db
    .collection<ImageDoc>("images")
    .find({ placeId: id }, { projection: { _id: 1 } })
    .toArray();
  const imageIds = images.map((i) => i._id);
  const routeCount = imageIds.length
    ? await db.collection("routes").countDocuments({ imageId: { $in: imageIds } })
    : 0;
  const activityCount = await db
    .collection<ActivityDoc>("activities")
    .countDocuments({ "routeSnapshot.placeId": id });

  let nearbyApproved: Array<PlaceDoc & { distanceMeters: number }> = [];
  if (place.location) {
    const nearby = await db
      .collection<PlaceDoc>("places")
      .find({
        _id: { $ne: id },
        type: "gym",
        status: "approved",
        location: {
          $nearSphere: {
            $geometry: { type: "Point", coordinates: place.location.coordinates },
            $maxDistance: NEARBY_RADIUS_METERS,
          },
        },
      })
      .limit(10)
      .toArray();
    nearbyApproved = nearby.map((n) => ({
      ...n,
      distanceMeters: n.location
        ? Math.round(haversineMeters(place.location!.coordinates, n.location.coordinates))
        : -1,
    }));
  }

  return {
    place,
    creator: user ? { profileId: user.profileId, profileImageUrl: user.profileImageUrl ?? null } : null,
    counts: { imageCount: images.length, routeCount, activityCount },
    nearbyApproved,
  };
}
