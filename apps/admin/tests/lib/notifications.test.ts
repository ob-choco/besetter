import { MongoClient, ObjectId } from "mongodb";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { notify } from "@/lib/notifications";

vi.mock("@/lib/push", () => ({
  sendPush: vi.fn(async () => {}),
}));

import { sendPush } from "@/lib/push";

let client: MongoClient;
const DB = "besetter_test";

beforeEach(async () => {
  client = new MongoClient(process.env.MONGODB_URI!);
  await client.connect();
  const db = client.db(DB);
  await Promise.all([
    db.collection("notifications").deleteMany({}),
    db.collection("users").deleteMany({}),
    db.collection("deviceTokens").deleteMany({}),
  ]);
  vi.mocked(sendPush).mockClear();
});

afterEach(async () => {
  await client.close();
});

describe("notify", () => {
  test("inserts notification, increments unread count, and calls sendPush", async () => {
    const userId = new ObjectId();
    const db = client.db(DB);
    await db.collection("users").insertOne({
      _id: userId,
      profileId: "u1",
      unreadNotificationCount: 0,
    } as any);

    await notify({
      userId,
      type: "place_review_passed",
      params: { place_name: "X짐" },
      link: `/places/${new ObjectId().toString()}`,
    });

    const notifs = await db.collection("notifications").find({ userId }).toArray();
    expect(notifs).toHaveLength(1);
    expect(notifs[0]!.type).toBe("place_review_passed");
    expect(notifs[0]!.title).toBe("");
    expect(notifs[0]!.body).toBe("");
    expect(notifs[0]!.params.place_name).toBe("X짐");

    const user = await db.collection("users").findOne({ _id: userId });
    expect(user!.unreadNotificationCount).toBe(1);

    expect(sendPush).toHaveBeenCalledTimes(1);
    expect(vi.mocked(sendPush).mock.calls[0]![0]!.type).toBe("place_review_passed");
  });
});
