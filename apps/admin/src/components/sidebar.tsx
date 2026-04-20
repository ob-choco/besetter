"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

type Counts = { pendingPlaces: number; pendingSuggestions: number };

export function Sidebar({ email }: { email: string }) {
  const pathname = usePathname();
  const [counts, setCounts] = useState<Counts>({ pendingPlaces: 0, pendingSuggestions: 0 });

  useEffect(() => {
    fetch("/api/counts")
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => data && setCounts(data))
      .catch(() => {});
  }, [pathname]);

  const item = (href: string, label: string, count: number) => {
    const active = pathname?.startsWith(href);
    return (
      <Link
        href={href}
        style={{
          display: "block",
          padding: "8px 16px",
          background: active ? "rgba(100,150,255,0.13)" : "transparent",
          borderLeft: active ? "3px solid #6495ff" : "3px solid transparent",
          color: active ? "#fff" : "#b0b6c6",
          textDecoration: "none",
        }}
      >
        {label}
        <span
          style={{
            float: "right",
            background: "#3a4256",
            color: "#cfd4e0",
            borderRadius: 10,
            padding: "1px 7px",
            fontSize: 11,
          }}
        >
          {count}
        </span>
      </Link>
    );
  };

  return (
    <aside
      style={{
        width: 210,
        background: "#151821",
        borderRight: "1px solid #262b38",
        padding: "16px 0",
        color: "#c5c9d4",
      }}
    >
      <div style={{ padding: "0 16px 14px", borderBottom: "1px solid #262b38", marginBottom: 10 }}>
        <div style={{ fontWeight: 600, color: "#fff" }}>besetter admin</div>
        <div style={{ fontSize: 11, color: "#8b93a7", marginTop: 3 }}>{email}</div>
      </div>
      <div style={{ fontSize: 10, letterSpacing: "0.1em", color: "#6b7388", padding: "8px 16px 6px" }}>
        장소
      </div>
      {item("/places", "장소 검수", counts.pendingPlaces)}
      {item("/suggestions", "수정 제안", counts.pendingSuggestions)}
    </aside>
  );
}
