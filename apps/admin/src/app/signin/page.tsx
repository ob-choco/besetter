"use client";
import { signIn } from "next-auth/react";

export default function SigninPage() {
  return (
    <main style={{ display: "flex", alignItems: "center", justifyContent: "center", minHeight: "100vh" }}>
      <button
        onClick={() => signIn("google", { callbackUrl: "/" })}
        style={{
          padding: "12px 22px",
          background: "#6495ff",
          color: "#fff",
          border: 0,
          borderRadius: 6,
          fontWeight: 600,
          cursor: "pointer",
        }}
      >
        Google 계정으로 로그인 (@olivebagel.com)
      </button>
    </main>
  );
}
