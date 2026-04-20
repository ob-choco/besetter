"use client";
import type { ReactNode } from "react";

export function QueueList({
  title,
  items,
  selectedId,
  onSelect,
  renderItem,
}: {
  title: string;
  items: Array<{ id: string }>;
  selectedId: string | null;
  onSelect: (id: string) => void;
  renderItem: (item: { id: string }) => ReactNode;
}) {
  return (
    <div style={{ width: 320, borderRight: "1px solid #262b38", background: "#12151d", overflow: "auto" }}>
      <div style={{ padding: "12px 14px", borderBottom: "1px solid #262b38", color: "#fff", fontWeight: 600 }}>
        {title}
      </div>
      {items.length === 0 ? (
        <div style={{ padding: "24px 14px", color: "#6b7388", fontSize: 12, textAlign: "center" }}>대기 중인 항목이 없습니다</div>
      ) : (
        items.map((it) => {
          const active = selectedId === it.id;
          return (
            <button
              key={it.id}
              onClick={() => onSelect(it.id)}
              style={{
                display: "block",
                width: "100%",
                textAlign: "left",
                padding: "10px 14px",
                background: active ? "#1a1f2b" : "transparent",
                borderLeft: active ? "3px solid #6495ff" : "3px solid transparent",
                borderTop: "1px solid #1f2432",
                color: active ? "#fff" : "#c5c9d4",
                cursor: "pointer",
                font: "inherit",
              }}
            >
              {renderItem(it)}
            </button>
          );
        })
      )}
    </div>
  );
}
