import { MongoClient, type Db } from "mongodb";
import { get as getConfig } from "@/lib/config";

let clientPromise: Promise<MongoClient> | null = null;

export function getMongoClient(): Promise<MongoClient> {
  if (clientPromise) return clientPromise;
  clientPromise = (async () => {
    const uri = await getConfig("mongodb.url");
    return new MongoClient(uri).connect();
  })().catch((err) => {
    clientPromise = null;
    throw err;
  });
  return clientPromise;
}

export async function getDb(): Promise<Db> {
  const client = await getMongoClient();
  const dbName = await getConfig("mongodb.name");
  return client.db(dbName);
}
