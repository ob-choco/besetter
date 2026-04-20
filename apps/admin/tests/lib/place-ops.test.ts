import { MongoClient, ObjectId } from "mongodb";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { getPendingPlaces } from "@/lib/place-ops";

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
