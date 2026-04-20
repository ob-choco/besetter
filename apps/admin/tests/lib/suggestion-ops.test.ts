import { MongoClient, ObjectId } from "mongodb";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

vi.mock("@/lib/notifications", () => ({ notify: vi.fn(async () => {}) }));

import { approveSuggestion, getPendingSuggestions, getSuggestionDetail } from "@/lib/suggestion-ops";
import { notify } from "@/lib/notifications";

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

describe("approveSuggestion", () => {
  async function seed(changes: Record<string, unknown>) {
    const db = client.db(DB);
    const user = { _id: new ObjectId(), profileId: "s", unreadNotificationCount: 0 };
    await db.collection("users").insertOne(user as any);
    const place = {
      _id: new ObjectId(), name: "Old", normalizedName: "old",
      type: "gym", status: "approved", createdBy: new ObjectId(), createdAt: new Date(),
      location: { type: "Point", coordinates: [127, 37] },
    };
    await db.collection("places").insertOne(place as any);
    const suggestion = {
      _id: new ObjectId(), placeId: place._id, requestedBy: user._id,
      status: "pending", changes, createdAt: new Date(),
    };
    await db.collection("placeSuggestions").insertOne(suggestion as any);
    return { place, suggestion, user };
  }

  test("name change updates name + normalizedName", async () => {
    vi.mocked(notify).mockClear();
    const { place, suggestion } = await seed({ name: "New Name" });
    await approveSuggestion(suggestion._id);
    const db = client.db(DB);
    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.name).toBe("New Name");
    expect(updated!.normalizedName).toBe("newname");
    const s = await db.collection("placeSuggestions").findOne({ _id: suggestion._id });
    expect(s!.status).toBe("approved");
    expect(s!.reviewedAt).toBeInstanceOf(Date);
  });

  test("location change updates coordinates", async () => {
    const { place, suggestion } = await seed({ latitude: 37.5, longitude: 127.1 });
    await approveSuggestion(suggestion._id);
    const db = client.db(DB);
    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.location.coordinates).toEqual([127.1, 37.5]);
  });

  test("cover change updates coverImageUrl", async () => {
    const { place, suggestion } = await seed({ coverImageUrl: "https://example/new.jpg" });
    await approveSuggestion(suggestion._id);
    const db = client.db(DB);
    const updated = await db.collection("places").findOne({ _id: place._id });
    expect(updated!.coverImageUrl).toBe("https://example/new.jpg");
  });

  test("conflict when suggestion not pending", async () => {
    const { suggestion } = await seed({ name: "X" });
    const db = client.db(DB);
    await db.collection("placeSuggestions").updateOne(
      { _id: suggestion._id },
      { $set: { status: "approved" } },
    );
    await expect(approveSuggestion(suggestion._id)).rejects.toMatchObject({ code: "CONFLICT" });
  });

  test("conflict when target place not approved", async () => {
    const { place, suggestion } = await seed({ name: "X" });
    const db = client.db(DB);
    await db.collection("places").updateOne(
      { _id: place._id },
      { $set: { status: "rejected" } },
    );
    await expect(approveSuggestion(suggestion._id)).rejects.toMatchObject({ code: "CONFLICT" });
  });

  test("bad_request when all changes are null", async () => {
    const { suggestion } = await seed({});
    await expect(approveSuggestion(suggestion._id)).rejects.toMatchObject({ code: "BAD_REQUEST" });
  });

  test("notifies requester with place_suggestion_approved", async () => {
    vi.mocked(notify).mockClear();
    const { user, suggestion } = await seed({ name: "Y" });
    await approveSuggestion(suggestion._id);
    expect(notify).toHaveBeenCalledWith(
      expect.objectContaining({ userId: user._id, type: "place_suggestion_approved" }),
    );
  });
});
