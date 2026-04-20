import { getServerSession } from "next-auth/next";
import { authOptions } from "@/lib/auth";
import { Providers } from "./providers";
import { Sidebar } from "@/components/sidebar";

export const metadata = { title: "besetter admin" };

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const session = await getServerSession(authOptions);
  return (
    <html lang="ko">
      <body style={{ margin: 0, fontFamily: "system-ui, sans-serif", background: "#0f1117", color: "#dde1ea" }}>
        <Providers>
          {session?.user?.email ? (
            <div style={{ display: "flex", minHeight: "100vh" }}>
              <Sidebar email={session.user.email} />
              <div style={{ flex: 1 }}>{children}</div>
            </div>
          ) : (
            children
          )}
        </Providers>
      </body>
    </html>
  );
}
