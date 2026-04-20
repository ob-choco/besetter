"use client";
import { useState } from "react";

type Detail = {
  place: {
    _id: string;
    name: string;
    status: string;
    type: string;
    coverImageUrl?: string | null;
    location?: { coordinates: [number, number] } | null;
    createdAt: string;
  };
  creator: { profileId: string; profileImageUrl?: string | null } | null;
  counts: { imageCount: number; routeCount: number; activityCount: number };
  nearbyApproved: Array<{ _id: string; name: string; distanceMeters: number }>;
};

export function PlaceDetail({
  detail,
  onPass,
  onFail,
  onOpenMerge,
}: {
  detail: Detail;
  onPass: () => void;
  onFail: (reason: string) => void;
  onOpenMerge: () => void;
}) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

  const act = async (fn: () => Promise<void>) => {
    setBusy(true);
    try { await fn(); } finally { setBusy(false); }
  };

  return (
    <div style={{ flex: 1, background: "#0f1117", color: "#dde1ea", padding: 18, overflow: "auto" }}>
      <div style={{ display: "flex", gap: 16 }}>
        <div
          style={{
            width: 200,
            height: 140,
            background: "#262b38",
            borderRadius: 6,
            overflow: "hidden",
          }}
        >
          {detail.place.coverImageUrl ? (
            <img src={detail.place.coverImageUrl} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
          ) : null}
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 20, fontWeight: 600 }}>{detail.place.name}</div>
          <div style={{ fontSize: 12, color: "#8b93a7", marginTop: 4 }}>
            status: <b style={{ color: "#ffb86b" }}>{detail.place.status}</b> · type: {detail.place.type}
          </div>
          <div style={{ fontSize: 12, color: "#c5c9d4", marginTop: 10 }}>
            {detail.place.location
              ? `좌표 ${detail.place.location.coordinates[1].toFixed(4)}, ${detail.place.location.coordinates[0].toFixed(4)}`
              : "좌표 없음"}
            {detail.creator ? ` · 등록자 @${detail.creator.profileId}` : null}
          </div>
          <div style={{ fontSize: 12, color: "#c5c9d4", marginTop: 4 }}>
            매달린 데이터: 이미지 {detail.counts.imageCount} · 루트 {detail.counts.routeCount} · 활동 {detail.counts.activityCount}
          </div>
        </div>
      </div>

      <div style={{ marginTop: 18, border: "1px solid #262b38", borderRadius: 6, overflow: "hidden" }}>
        <div style={{ padding: "10px 14px", background: "#151821", fontSize: 12, color: "#c5c9d4" }}>
          반경 200m 내 approved 장소
        </div>
        {detail.nearbyApproved.length === 0 ? (
          <div style={{ padding: 12, color: "#6b7388", fontSize: 12 }}>해당 없음</div>
        ) : (
          detail.nearbyApproved.map((n) => (
            <div
              key={n._id}
              style={{
                padding: "8px 14px",
                borderTop: "1px solid #262b38",
                fontSize: 12,
                display: "flex",
                justifyContent: "space-between",
              }}
            >
              <span>
                <b>{n.name}</b> <span style={{ color: "#8b93a7" }}>· {n.distanceMeters}m</span>
              </span>
            </div>
          ))
        )}
      </div>

      <div style={{ marginTop: 14, display: "flex", gap: 10, alignItems: "flex-start" }}>
        <button
          disabled={busy}
          onClick={() => act(async () => onPass())}
          style={btnStyle("#3aa76d", "#fff")}
        >
          PASS
        </button>
        <button
          disabled={busy}
          onClick={() => act(async () => onFail(reason.trim() || ""))}
          style={btnStyle("#d04848", "#fff")}
        >
          FAIL
        </button>
        <button
          disabled={busy}
          onClick={() => act(async () => onOpenMerge())}
          style={btnStyle("#ffb86b", "#1a1308")}
        >
          MERGE
        </button>
        <input
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="FAIL 사유 (선택)"
          style={{
            flex: 1,
            background: "#1d2130",
            color: "#c5c9d4",
            border: "1px solid #2c3244",
            borderRadius: 5,
            padding: "9px 10px",
            fontSize: 12,
          }}
        />
      </div>
    </div>
  );
}

function btnStyle(bg: string, fg: string): React.CSSProperties {
  return {
    background: bg,
    color: fg,
    border: 0,
    borderRadius: 5,
    padding: "9px 18px",
    fontWeight: 600,
    cursor: "pointer",
  };
}
