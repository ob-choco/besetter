import { MongoClient, ObjectId } from "mongodb";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

vi.mock("@/lib/notifications", () => ({
  notify: vi.fn(async () => {}),
}));

import { failPlace, getMergeCandidates, getPendingPlaces, getPlaceDetail, passPlace } from "@/lib/place-ops";
import type { PlaceDoc } from "@/lib/db-types";
import { notify } from "@/lib/notifications";

const DB = "besetter_test";
let client: MongoClient;

beforeEach(async () => {
  client = new MongoClient(process.env.MONGODB_URI!);
  await client.connect();
  const db = client.db(DB);
  await Promise.all([
    db.collection("places").deleteMany({}),
    db.collection("users").deleteMany({}),
  ]);
});
afterEach(async () => { await client.close(); });

describe("getPendingPlaces", () => {
  test("returns only type=gym and status=pending, oldest first", async () => {
    const db = client.db(DB);
    const now = Date.now();
    const user = { _id: new ObjectId(), profileId: "climber", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);

    const older = {
      _id: new ObjectId(),
      name: "Older",
      normalizedName: "older",
      type: "gym",
      status: "pending",
      createdBy: user._id,
      createdAt: new Date(now - 60_000),
    };
    const newer = {
      _id: new ObjectId(),
      name: "Newer",
      normalizedName: "newer",
      type: "gym",
      status: "pending",
      createdBy: user._id,
      createdAt: new Date(now),
    };
    const approved = {
      _id: new ObjectId(),
      name: "Approved",
      normalizedName: "approved",
      type: "gym",
      status: "approved",
      createdBy: user._id,
      createdAt: new Date(now - 120_000),
    };
    const privateGym = {
      _id: new ObjectId(),
      name: "MyWall",
      normalizedName: "mywall",
      type: "private-gym",
      status: "pending",
      createdBy: user._id,
      createdAt: new Date(now - 30_000),
    };
    await db.collection("places").insertMany([older, newer, approved, privateGym] as any);

    const result = await getPendingPlaces();
    expect(result.map((r) => r.name)).toEqual(["Older", "Newer"]);
    expect(result[0]!.creator?.profileId).toBe("climber");
  });
});

describe("getPlaceDetail", () => {
  test("returns place + counts + nearby approved", async () => {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "climber", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const source = {
      _id: new ObjectId(),
      name: "New Gym",
      normalizedName: "newgym",
      type: "gym",
      status: "pending",
      createdBy: user._id,
      createdAt: new Date(),
      location: { type: "Point", coordinates: [127.0276, 37.4981] },
    };
    const nearby = {
      _id: new ObjectId(),
      name: "Existing Gym",
      normalizedName: "existinggym",
      type: "gym",
      status: "approved",
      createdBy: user._id,
      createdAt: new Date(),
      location: { type: "Point", coordinates: [127.0275, 37.4983] },
    };
    await db.collection("places").insertMany([source, nearby] as any);
    await db.collection("places").createIndex({ location: "2dsphere" });

    const imageId = new ObjectId();
    await db.collection("images").insertOne({
      _id: imageId,
      url: "https://example/x.jpg",
      filename: "x.jpg",
      userId: user._id,
      placeId: source._id,
      isDeleted: false,
      uploadedAt: new Date(),
    } as any);
    await db.collection("routes").insertOne({
      _id: new ObjectId(),
      imageId,
      userId: user._id,
    } as any);
    await db.collection("activities").insertOne({
      _id: new ObjectId(),
      routeId: new ObjectId(),
      userId: user._id,
      routeSnapshot: { gradeType: "v", grade: "v3", placeId: source._id, placeName: "New Gym" },
    } as any);

    const detail = await getPlaceDetail(source._id);
    expect(detail).not.toBeNull();
    expect(detail!.place.name).toBe("New Gym");
    expect(detail!.counts).toEqual({ imageCount: 1, routeCount: 1, activityCount: 1 });
    expect(detail!.nearbyApproved).toHaveLength(1);
    expect(detail!.nearbyApproved[0]!.name).toBe("Existing Gym");
    expect(detail!.nearbyApproved[0]!.distanceMeters).toBeGreaterThanOrEqual(0);
  });

  test("returns null for unknown id", async () => {
    const detail = await getPlaceDetail(new ObjectId());
    expect(detail).toBeNull();
  });
});

describe("getMergeCandidates", () => {
  test("nearby 1km returns approved gyms sorted by distance, excludes pending/merged/rejected/private", async () => {
    const db = client.db(DB);
    await db.collection("places").createIndex({ location: "2dsphere" });
    const mkPlace = (
      name: string,
      coords: [number, number],
      over: Partial<PlaceDoc> = {},
    ): PlaceDoc =>
      ({
        _id: new ObjectId(),
        name,
        normalizedName: name.toLowerCase(),
        type: "gym",
        status: "approved",
        location: { type: "Point", coordinates: coords },
        createdBy: new ObjectId(),
        createdAt: new Date(),
        ...over,
      }) as PlaceDoc;
    const approved = mkPlace("A", [127.0275, 37.4983]);
    const farAway = mkPlace("Far", [128.0, 37.0]);
    const pending = mkPlace("P", [127.028, 37.498], { status: "pending" });
    const privateGym = mkPlace("PG", [127.028, 37.498], { type: "private-gym" });
    await db.collection("places").insertMany([approved, farAway, pending, privateGym] as any);

    const results = await getMergeCandidates({ lat: 37.4981, lng: 127.0276 });
    const names = results.map((r) => r.name);
    expect(names).toContain("A");
    expect(names).not.toContain("Far");
    expect(names).not.toContain("P");
    expect(names).not.toContain("PG");
    expect(results[0]!.distanceMeters).toBeDefined();
  });

  test("name search returns approved gyms by normalizedName regex", async () => {
    const db = client.db(DB);
    await db.collection("places").insertMany([
      {
        _id: new ObjectId(),
        name: "강남 클라이밍 파크",
        normalizedName: "강남클라이밍파크",
        type: "gym",
        status: "approved",
        createdBy: new ObjectId(),
        createdAt: new Date(),
      },
      {
        _id: new ObjectId(),
        name: "Seoul Bouldering",
        normalizedName: "seoulbouldering",
        type: "gym",
        status: "approved",
        createdBy: new ObjectId(),
        createdAt: new Date(),
      },
    ] as any);

    const results = await getMergeCandidates({ lat: 0, lng: 0, q: "클라이밍" });
    expect(results.map((r) => r.name)).toEqual(["강남 클라이밍 파크"]);
  });
});

describe("passPlace", () => {
  test("pending → approved, emits place_review_passed", async () => {
    vi.mocked(notify).mockClear();
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "c", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(),
      name: "P",
      normalizedName: "p",
      type: "gym",
      status: "pending",
      createdBy: user._id,
      createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);

    await passPlace(place._id);

    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.status).toBe("approved");
    expect(notify).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: user._id,
        type: "place_review_passed",
        params: expect.objectContaining({ place_name: "P" }),
      }),
    );
  });

  test("throws ConflictError when place is already approved", async () => {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "c", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(),
      name: "P",
      normalizedName: "p",
      type: "gym",
      status: "approved",
      createdBy: user._id,
      createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);

    await expect(passPlace(place._id)).rejects.toMatchObject({ code: "CONFLICT" });
  });
});

describe("failPlace", () => {
  test("pending → rejected, stores reason when provided, notifies with reason_suffix", async () => {
    vi.mocked(notify).mockClear();
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "c", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(), name: "P", normalizedName: "p",
      type: "gym", status: "pending", createdBy: user._id, createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);

    await failPlace(place._id, "중복 등록");

    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.status).toBe("rejected");
    expect(updated!.rejectedReason).toBe("중복 등록");
    expect(notify).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: user._id,
        type: "place_review_failed",
        params: { place_name: "P", reason_suffix: " 사유: 중복 등록" },
      }),
    );
  });

  test("omits reason_suffix when no reason provided, does not set rejectedReason", async () => {
    vi.mocked(notify).mockClear();
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "c", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(), name: "Q", normalizedName: "q",
      type: "gym", status: "pending", createdBy: user._id, createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);

    await failPlace(place._id);

    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.rejectedReason ?? null).toBeNull();
    expect(notify).toHaveBeenCalledWith(
      expect.objectContaining({
        params: { place_name: "Q", reason_suffix: "" },
      }),
    );
  });

  test("conflict when not pending", async () => {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "c", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(), name: "R", normalizedName: "r",
      type: "gym", status: "approved", createdBy: user._id, createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);
    await expect(failPlace(place._id, "any")).rejects.toMatchObject({ code: "CONFLICT" });
  });
});
