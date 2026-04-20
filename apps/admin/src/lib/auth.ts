import type { NextAuthOptions } from "next-auth";
import GoogleProvider from "next-auth/providers/google";

function allowlist(): string[] {
  return (process.env.ADMIN_EMAIL_ALLOWLIST ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
}

export const authOptions: NextAuthOptions = {
  providers: [
    GoogleProvider({
      clientId: process.env.GOOGLE_CLIENT_ID ?? "",
      clientSecret: process.env.GOOGLE_CLIENT_SECRET ?? "",
      authorization: {
        params: { hd: "olivebagel.com", prompt: "select_account" },
      },
    }),
  ],
  session: { strategy: "jwt" },
  secret: process.env.NEXTAUTH_SECRET,
  callbacks: {
    async signIn({ profile }) {
      const hd = (profile as { hd?: string } | undefined)?.hd;
      if (hd !== "olivebagel.com") return false;
      const email = profile?.email?.toLowerCase();
      if (!email || !allowlist().includes(email)) return false;
      return true;
    },
    async session({ session, token }) {
      if (token?.email && session.user) {
        session.user.email = token.email;
      }
      return session;
    },
  },
};
