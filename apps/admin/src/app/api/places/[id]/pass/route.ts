import { ObjectId } from "mongodb";
import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/authz";
import { passPlace, AdminOpError } from "@/lib/place-ops";

export async function POST(_req: Request, { params }: { params: { id: string } }) {
  const auth = await requireAdmin();
  if (!auth.ok) return auth.response;
  if (!ObjectId.isValid(params.id)) {
    return NextResponse.json({ error: "invalid id" }, { status: 422 });
  }
  try {
    await passPlace(new ObjectId(params.id));
    console.log("[admin] pass", { actor: auth.admin.email, placeId: params.id });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminOpError && err.code === "CONFLICT") {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    throw err;
  }
}
