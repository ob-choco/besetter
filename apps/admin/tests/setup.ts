import { MongoMemoryReplSet } from "mongodb-memory-server";
import { afterAll, beforeAll, vi } from "vitest";

let replSet: MongoMemoryReplSet | null = null;
let mongoUri = "";
const DB_NAME = "besetter_test";

vi.mock("@/lib/config", () => ({
  get: vi.fn(async (key: string) => {
    if (key === "mongodb.url") return mongoUri;
    if (key === "mongodb.name") return DB_NAME;
    throw new Error(`Could not find key '${key}' in settings.`);
  }),
}));

beforeAll(async () => {
  replSet = await MongoMemoryReplSet.create({
    replSet: { count: 1 },
  });
  mongoUri = replSet.getUri();
  process.env.MONGODB_URI = mongoUri;
  process.env.MONGODB_DB = DB_NAME;
});

afterAll(async () => {
  await replSet?.stop();
});
