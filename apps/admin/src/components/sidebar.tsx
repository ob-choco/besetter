"use client";

export function Sidebar({ email }: { email: string }) {
  return (
    <aside
      style={{
        width: 210,
        background: "#151821",
        borderRight: "1px solid #262b38",
        padding: "16px 0",
        color: "#c5c9d4",
        minHeight: "100vh",
      }}
    >
      <div style={{ padding: "0 16px 14px", borderBottom: "1px solid #262b38", marginBottom: 10 }}>
        <div style={{ fontWeight: 600, color: "#fff" }}>besetter admin</div>
        <div style={{ fontSize: 11, color: "#8b93a7", marginTop: 3 }}>{email}</div>
      </div>
      <div style={{ padding: "8px 16px", color: "#6b7388", fontSize: 12 }}>(tools ↓)</div>
    </aside>
  );
}
