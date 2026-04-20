"use client";
import { useState } from "react";

type Detail = {
  _id: string;
  requester: { profileId: string } | null;
  createdAt: string;
  changes: { name?: string | null; latitude?: number | null; longitude?: number | null; coverImageUrl?: string | null };
  currentPlace: {
    name: string;
    location?: { coordinates: [number, number] } | null;
    coverImageUrl?: string | null;
  };
};

export function SuggestionDiff({
  detail,
  onApprove,
  onReject,
}: {
  detail: Detail;
  onApprove: () => void;
  onReject: (reason: string) => void;
}) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const act = async (fn: () => Promise<void>) => { setBusy(true); try { await fn(); } finally { setBusy(false); } };

  const nameChanged = detail.changes.name != null;
  const locChanged = detail.changes.latitude != null && detail.changes.longitude != null;
  const coverChanged = detail.changes.coverImageUrl != null;

  return (
    <div style={{ flex: 1, background: "#0f1117", color: "#dde1ea", padding: 18, overflow: "auto" }}>
      <div style={{ fontSize: 20, fontWeight: 600 }}>{detail.currentPlace.name}</div>
      <div style={{ fontSize: 12, color: "#8b93a7", marginTop: 3 }}>
        제안자 @{detail.requester?.profileId ?? "?"} · {new Date(detail.createdAt).toLocaleString()}
      </div>

      <DiffCard label="NAME" changed={nameChanged}>
        <Side which="current">{detail.currentPlace.name}</Side>
        <Side which="proposed">{detail.changes.name ?? "—"}</Side>
      </DiffCard>

      <DiffCard label="LOCATION" changed={locChanged}>
        <Side which="current">
          {detail.currentPlace.location
            ? `${detail.currentPlace.location.coordinates[1]}, ${detail.currentPlace.location.coordinates[0]}`
            : "—"}
        </Side>
        <Side which="proposed">
          {locChanged ? `${detail.changes.latitude}, ${detail.changes.longitude}` : "—"}
        </Side>
      </DiffCard>

      <DiffCard label="COVER IMAGE" changed={coverChanged}>
        <Side which="current">
          {detail.currentPlace.coverImageUrl ? (
            <img src={detail.currentPlace.coverImageUrl} alt="" style={{ width: "100%", maxHeight: 140, objectFit: "cover", borderRadius: 4 }} />
          ) : "—"}
        </Side>
        <Side which="proposed">
          {coverChanged && detail.changes.coverImageUrl ? (
            <img src={detail.changes.coverImageUrl} alt="" style={{ width: "100%", maxHeight: 140, objectFit: "cover", borderRadius: 4 }} />
          ) : "—"}
        </Side>
      </DiffCard>

      <div style={{ marginTop: 16, display: "flex", gap: 10 }}>
        <button disabled={busy} onClick={() => act(async () => onApprove())} style={btn("#3aa76d", "#fff")}>APPROVE</button>
        <button disabled={busy} onClick={() => act(async () => onReject(reason.trim()))} style={btn("#d04848", "#fff")}>REJECT</button>
        <input
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="REJECT 사유 (선택)"
          style={{ flex: 1, background: "#1d2130", color: "#c5c9d4", border: "1px solid #2c3244", borderRadius: 5, padding: "9px 10px", fontSize: 12 }}
        />
      </div>
    </div>
  );
}

function btn(bg: string, fg: string): React.CSSProperties {
  return { background: bg, color: fg, border: 0, borderRadius: 5, padding: "9px 18px", fontWeight: 600, cursor: "pointer" };
}

function DiffCard({ label, changed, children }: { label: string; changed: boolean; children: React.ReactNode }) {
  if (!changed) {
    return (
      <div style={{ marginTop: 10, border: "1px dashed #262b38", borderRadius: 6, padding: "8px 12px", color: "#6b7388", fontSize: 11 }}>
        {label} — 제안 없음
      </div>
    );
  }
  return (
    <div style={{ marginTop: 10, border: "1px solid #262b38", borderRadius: 6, overflow: "hidden" }}>
      <div style={{ padding: "8px 12px", background: "#151821", fontSize: 11, color: "#8b93a7", letterSpacing: "0.05em" }}>{label}</div>
      <div style={{ display: "flex" }}>{children}</div>
    </div>
  );
}

function Side({ which, children }: { which: "current" | "proposed"; children: React.ReactNode }) {
  const bg = which === "current" ? "#1a1417" : "#141a17";
  const border = which === "current" ? "#d04848" : "#3aa76d";
  const fg = which === "current" ? "#d08a8a" : "#8ad0a0";
  return (
    <div style={{ flex: 1, padding: 12, background: bg, borderLeft: `3px solid ${border}`, borderRight: which === "current" ? "1px solid #262b38" : undefined }}>
      <div style={{ fontSize: 10, color: fg, marginBottom: 4 }}>{which === "current" ? "CURRENT" : "PROPOSED"}</div>
      <div style={{ color: "#fff" }}>{children}</div>
    </div>
  );
}
