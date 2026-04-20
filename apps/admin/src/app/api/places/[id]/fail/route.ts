import { ObjectId } from "mongodb";
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { failPlace, AdminOpError } from "@/lib/place-ops";
import { FailBody } from "@/lib/zod-schemas";

export async function POST(req: Request, { params }: { params: { id: string } }) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  if (!ObjectId.isValid(params.id)) {
    return NextResponse.json({ error: "invalid id" }, { status: 422 });
  }
  const body = await req.json().catch(() => ({}));
  const parsed = FailBody.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid body", details: parsed.error.flatten() }, { status: 422 });
  }
  try {
    await failPlace(new ObjectId(params.id), parsed.data.reason);
    console.log("[admin] fail", { actor: auth.admin.email, placeId: params.id, reason: parsed.data.reason ?? null });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminOpError && err.code === "CONFLICT") {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    throw err;
  }
}
