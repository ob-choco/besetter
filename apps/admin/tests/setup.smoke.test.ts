import { MongoClient } from "mongodb";
import { expect, test } from "vitest";

test("memory replset is reachable and supports transactions", async () => {
  const client = new MongoClient(process.env.MONGODB_URI!);
  await client.connect();
  const session = client.startSession();
  try {
    await session.withTransaction(async () => {
      await client.db("besetter_test").collection("smoke").insertOne({ ok: 1 }, { session });
    });
    const doc = await client.db("besetter_test").collection("smoke").findOne({ ok: 1 });
    expect(doc).not.toBeNull();
  } finally {
    await session.endSession();
    await client.close();
  }
});
