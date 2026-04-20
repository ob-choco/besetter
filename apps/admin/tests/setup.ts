import { MongoMemoryReplSet } from "mongodb-memory-server";
import { afterAll, beforeAll } from "vitest";

let replSet: MongoMemoryReplSet | null = null;

beforeAll(async () => {
  replSet = await MongoMemoryReplSet.create({
    replSet: { count: 1 },
  });
  process.env.MONGODB_URI = replSet.getUri();
  process.env.MONGODB_DB = "besetter_test";
});

afterAll(async () => {
  await replSet?.stop();
});
