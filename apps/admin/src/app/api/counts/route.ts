import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { getDb } from "@/lib/mongo";

export async function GET() {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  const db = await getDb();
  const [pendingPlaces, pendingSuggestions] = await Promise.all([
    db.collection("places").countDocuments({ type: "gym", status: "pending" }),
    db.collection("placeSuggestions").countDocuments({ status: "pending" }),
  ]);
  return NextResponse.json({ pendingPlaces, pendingSuggestions });
}
