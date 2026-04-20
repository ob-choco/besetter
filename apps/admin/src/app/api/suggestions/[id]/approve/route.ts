import { ObjectId } from "mongodb";
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { approveSuggestion } from "@/lib/suggestion-ops";
import { AdminOpError } from "@/lib/place-ops";

export async function POST(_req: Request, { params }: { params: { id: string } }) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  if (!ObjectId.isValid(params.id)) {
    return NextResponse.json({ error: "invalid id" }, { status: 422 });
  }
  try {
    await approveSuggestion(new ObjectId(params.id));
    console.log("[admin] suggestion.approve", { actor: auth.admin.email, suggestionId: params.id });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminOpError) {
      const statusCode = err.code === "BAD_REQUEST" ? 400 : 409;
      return NextResponse.json({ error: err.message }, { status: statusCode });
    }
    throw err;
  }
}
