import { ObjectId } from "mongodb";
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { rejectSuggestion } from "@/lib/suggestion-ops";
import { AdminOpError } from "@/lib/place-ops";
import { RejectBody } from "@/lib/zod-schemas";

export async function POST(req: Request, { params }: { params: { id: string } }) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  if (!ObjectId.isValid(params.id)) {
    return NextResponse.json({ error: "invalid id" }, { status: 422 });
  }
  const body = await req.json().catch(() => ({}));
  const parsed = RejectBody.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid body", details: parsed.error.flatten() }, { status: 422 });
  }
  try {
    await rejectSuggestion(new ObjectId(params.id), parsed.data.reason);
    console.log("[admin] suggestion.reject", {
      actor: auth.admin.email,
      suggestionId: params.id,
      reason: parsed.data.reason ?? null,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminOpError) {
      const statusCode = err.code === "BAD_REQUEST" ? 400 : 409;
      return NextResponse.json({ error: err.message }, { status: statusCode });
    }
    throw err;
  }
}
