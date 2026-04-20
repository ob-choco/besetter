import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { getPendingSuggestions } from "@/lib/suggestion-ops";

export async function GET() {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  const suggestions = await getPendingSuggestions();
  return NextResponse.json({ suggestions });
}
