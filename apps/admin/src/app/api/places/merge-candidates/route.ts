import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { getMergeCandidates } from "@/lib/place-ops";
import { MergeCandidatesQuery } from "@/lib/zod-schemas";

export async function GET(req: Request) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  const url = new URL(req.url);
  const parsed = MergeCandidatesQuery.safeParse({
    lat: url.searchParams.get("lat"),
    lng: url.searchParams.get("lng"),
    q: url.searchParams.get("q") ?? undefined,
  });
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid query", details: parsed.error.flatten() }, { status: 422 });
  }
  const candidates = await getMergeCandidates(parsed.data);
  return NextResponse.json({ candidates });
}
