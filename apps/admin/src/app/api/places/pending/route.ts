import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { getPendingPlaces } from "@/lib/place-ops";

export async function GET() {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  const places = await getPendingPlaces();
  return NextResponse.json({ places });
}
