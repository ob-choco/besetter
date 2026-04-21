import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { cert, getApps, initializeApp, type ServiceAccount } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import type { ObjectId } from "mongodb";
import { getDb } from "@/lib/mongo";
import type { DeviceTokenDoc, NotificationDoc } from "@/lib/db-types";
import { primaryLocale, renderTemplate, type Locale } from "@/lib/notification-templates";

function fcmEnabled(): boolean {
  return process.env.ADMIN_FCM_ENABLED === "true";
}

function ensureApp() {
  if (getApps().length > 0) return;
  const file = process.env.FIREBASE_SERVICE_ACCOUNT_FILE;
  if (!file) throw new Error("FIREBASE_SERVICE_ACCOUNT_FILE is not set");
  const parsed = JSON.parse(readFileSync(resolve(file), "utf8")) as ServiceAccount;
  initializeApp({
    credential: cert(parsed),
    projectId: process.env.FIREBASE_PROJECT_ID,
  });
}

type AdminNotificationInput = {
  userId: ObjectId;
  type: Extract<
    NotificationDoc["type"],
    "place_review_passed" | "place_review_failed" | "place_merged" | "place_suggestion_approved" | "place_suggestion_rejected"
  >;
  notificationId: ObjectId;
  params: Record<string, string>;
  link?: string | null;
};

export async function sendPush(input: AdminNotificationInput): Promise<void> {
  if (!fcmEnabled()) {
    console.log("[push] ADMIN_FCM_ENABLED=false — skipping fan-out", {
      userId: input.userId.toString(),
      type: input.type,
    });
    return;
  }
  ensureApp();
  const db = await getDb();
  const devices = await db
    .collection<DeviceTokenDoc>("deviceTokens")
    .find({ userId: input.userId })
    .toArray();
  if (devices.length === 0) return;

  const messaging = getMessaging();
  await Promise.all(
    devices.map(async (device) => {
      const loc: Locale = primaryLocale(device.locale);
      const { title, body } = renderTemplate(input.type, loc, input.params);
      const data: Record<string, string> = {
        type: input.type,
        notificationId: input.notificationId.toString(),
      };
      if (input.link) data.link = input.link;
      try {
        await messaging.send({
          token: device.token,
          notification: { title, body },
          data,
        });
      } catch (err) {
        const code = (err as { code?: string }).code ?? "";
        console.warn("[push] send failed", {
          token: device.token.slice(0, 16),
          code,
        });
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token" ||
          code === "messaging/mismatched-credential"
        ) {
          await db.collection<DeviceTokenDoc>("deviceTokens").deleteOne({ token: device.token });
        }
      }
    }),
  );
}
