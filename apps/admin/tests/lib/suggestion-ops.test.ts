import { MongoClient, ObjectId } from "mongodb";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

vi.mock("@/lib/notifications", () => ({ notify: vi.fn(async () => {}) }));

import { getPendingSuggestions, getSuggestionDetail } from "@/lib/suggestion-ops";

const DB = "besetter_test";
let client: MongoClient;

beforeEach(async () => {
  client = new MongoClient(process.env.MONGODB_URI!);
  await client.connect();
  const db = client.db(DB);
  await Promise.all([
    db.collection("placeSuggestions").deleteMany({}),
    db.collection("places").deleteMany({}),
    db.collection("users").deleteMany({}),
  ]);
});
afterEach(async () => { await client.close(); });

describe("getPendingSuggestions", () => {
  test("returns pending only, attaches place snapshot and requester profile", async () => {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "suggester", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(), name: "Existing", normalizedName: "existing",
      type: "gym", status: "approved", createdBy: new ObjectId(), createdAt: new Date(),
    };
    await db.collection("places").insertOne(place as any);
    const pending = {
      _id: new ObjectId(),
      placeId: place._id,
      requestedBy: user._id,
      status: "pending",
      changes: { name: "Existing Updated" },
      createdAt: new Date(),
    };
    const reviewed = { ...pending, _id: new ObjectId(), status: "approved", reviewedAt: new Date() };
    await db.collection("placeSuggestions").insertMany([pending, reviewed] as any);

    const result = await getPendingSuggestions();
    expect(result).toHaveLength(1);
    expect(result[0]!.place.name).toBe("Existing");
    expect(result[0]!.requester?.profileId).toBe("suggester");
    expect(result[0]!.changes.name).toBe("Existing Updated");
  });
});

describe("getSuggestionDetail", () => {
  test("returns null for unknown id", async () => {
    const d = await getSuggestionDetail(new ObjectId());
    expect(d).toBeNull();
  });
});
