import type { ObjectId } from "mongodb";
import { getDb } from "@/lib/mongo";
import type { NotificationDoc, UserDoc } from "@/lib/db-types";
import { sendPush } from "@/lib/push";

type AdminNotificationType = Extract<
  NotificationDoc["type"],
  "place_review_passed" | "place_review_failed" | "place_merged" | "place_suggestion_approved" | "place_suggestion_rejected"
>;

export async function notify(input: {
  userId: ObjectId;
  type: AdminNotificationType;
  params: Record<string, string>;
  link?: string | null;
}): Promise<void> {
  const db = await getDb();
  const doc: NotificationDoc = {
    userId: input.userId,
    type: input.type,
    title: "",
    body: "",
    params: input.params,
    link: input.link ?? null,
    createdAt: new Date(),
  };
  const res = await db.collection<NotificationDoc>("notifications").insertOne(doc);
  await db.collection<UserDoc>("users").updateOne(
    { _id: input.userId },
    { $inc: { unreadNotificationCount: 1 } },
  );
  try {
    await sendPush({
      userId: input.userId,
      type: input.type,
      notificationId: res.insertedId,
      params: input.params,
      link: input.link ?? null,
    });
  } catch (err) {
    console.warn("[notify] sendPush failed", err);
  }
}
