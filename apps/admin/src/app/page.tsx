import { getServerSession } from "next-auth/next";
import { redirect } from "next/navigation";
import { authOptions } from "@/lib/auth";

export default async function IndexPage() {
  const session = await getServerSession(authOptions);
  if (!session?.user?.email) redirect("/signin");
  redirect("/places");
}
