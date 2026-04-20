import { SecretManagerServiceClient } from "@google-cloud/secret-manager";
import { parse as parseYaml } from "yaml";

const SECRET_NAME = "projects/371038003203/secrets/api-secret/versions/latest";

let settingsPromise: Promise<Record<string, unknown>> | null = null;

async function getSettings(): Promise<Record<string, unknown>> {
  if (settingsPromise) return settingsPromise;
  settingsPromise = (async () => {
    const client = new SecretManagerServiceClient();
    const [response] = await client.accessSecretVersion({ name: SECRET_NAME });
    const payload = response.payload?.data;
    if (!payload) throw new Error("Secret Manager payload is empty");
    const text = typeof payload === "string" ? payload : Buffer.from(payload).toString("utf8");
    return parseYaml(text) as Record<string, unknown>;
  })().catch((err) => {
    settingsPromise = null;
    throw err;
  });
  return settingsPromise;
}

export async function get(key: string): Promise<string> {
  const settings = await getSettings();
  const parts = key.split(".");
  let value: unknown = settings;
  for (const part of parts) {
    if (value != null && typeof value === "object" && part in (value as Record<string, unknown>)) {
      value = (value as Record<string, unknown>)[part];
    } else {
      value = undefined;
      break;
    }
  }
  if (value === undefined || value === null) {
    throw new Error(`Could not find key '${key}' in settings.`);
  }
  return value as string;
}
