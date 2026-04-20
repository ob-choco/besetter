"use client";
import { useEffect, useState } from "react";

type Candidate = {
  _id: string;
  name: string;
  location?: { coordinates: [number, number] } | null;
  distanceMeters?: number;
  imageCount: number;
  routeCount: number;
};

export function MergeDialog({
  source,
  counts,
  onClose,
  onConfirm,
}: {
  source: { _id: string; name: string; location?: { coordinates: [number, number] } | null };
  counts: { imageCount: number; routeCount: number; activityCount: number };
  onClose: () => void;
  onConfirm: (targetPlaceId: string) => void;
}) {
  const [q, setQ] = useState("");
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [selected, setSelected] = useState<string | null>(null);

  useEffect(() => {
    const lat = source.location?.coordinates[1] ?? 0;
    const lng = source.location?.coordinates[0] ?? 0;
    const url = new URL("/api/places/merge-candidates", window.location.origin);
    url.searchParams.set("lat", String(lat));
    url.searchParams.set("lng", String(lng));
    if (q.trim()) url.searchParams.set("q", q.trim());
    fetch(url)
      .then((r) => (r.ok ? r.json() : { candidates: [] }))
      .then((d) => setCandidates(d.candidates ?? []))
      .catch(() => setCandidates([]));
  }, [q, source.location]);

  return (
    <div
      role="dialog"
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,0.55)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: 40,
      }}
    >
      <div style={{ width: 720, background: "#0f1117", border: "1px solid #262b38", borderRadius: 8 }}>
        <div style={{ padding: "14px 18px", borderBottom: "1px solid #262b38", color: "#fff", fontWeight: 600 }}>
          MERGE 타깃 선택
        </div>
        <div style={{ padding: 18, color: "#dde1ea" }}>
          <div style={{ background: "#151821", border: "1px solid #262b38", borderRadius: 6, padding: "12px 14px" }}>
            <div style={{ fontSize: 11, color: "#8b93a7" }}>병합 대상(source)</div>
            <div style={{ fontWeight: 600 }}>{source.name}</div>
            <div style={{ fontSize: 11, color: "#ffb86b", marginTop: 4 }}>
              ⚠ 이미지 {counts.imageCount} · 루트 {counts.routeCount} · 활동 {counts.activityCount} 이관됨
            </div>
          </div>

          <div style={{ margin: "12px 0" }}>
            <input
              placeholder="이름으로 검색 (예: 강남 클라이밍)"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              style={{
                width: "100%",
                background: "#1d2130",
                color: "#c5c9d4",
                border: "1px solid #2c3244",
                borderRadius: 5,
                padding: "9px 10px",
                fontSize: 12,
              }}
            />
          </div>

          <div style={{ border: "1px solid #262b38", borderRadius: 6, overflow: "hidden" }}>
            {candidates.length === 0 ? (
              <div style={{ padding: 24, color: "#8b93a7", fontSize: 12, textAlign: "center" }}>
                1km 반경 내 approved 장소가 없습니다
              </div>
            ) : (
              candidates.map((c) => {
                const active = selected === c._id;
                return (
                  <button
                    key={c._id}
                    onClick={() => setSelected(c._id)}
                    style={{
                      display: "block",
                      width: "100%",
                      textAlign: "left",
                      padding: "10px 14px",
                      background: active ? "#1a1f2b" : "transparent",
                      borderTop: "1px solid #262b38",
                      borderLeft: active ? "3px solid #6495ff" : "3px solid transparent",
                      color: active ? "#fff" : "#c5c9d4",
                      cursor: "pointer",
                      font: "inherit",
                    }}
                  >
                    <div style={{ fontWeight: 600 }}>{c.name}</div>
                    <div style={{ fontSize: 11, color: "#8b93a7", marginTop: 3 }}>
                      이미지 {c.imageCount} · 루트 {c.routeCount}
                      {c.distanceMeters != null ? ` · ${c.distanceMeters}m` : ""}
                    </div>
                  </button>
                );
              })
            )}
          </div>

          <div style={{ marginTop: 18, display: "flex", gap: 10, justifyContent: "flex-end" }}>
            <button onClick={onClose} style={{ background: "#2c3244", color: "#c5c9d4", border: 0, borderRadius: 5, padding: "9px 16px", cursor: "pointer" }}>
              취소
            </button>
            <button
              disabled={!selected}
              onClick={() => selected && onConfirm(selected)}
              style={{
                background: selected ? "#ffb86b" : "#3a4256",
                color: "#1a1308",
                border: 0,
                borderRadius: 5,
                padding: "9px 18px",
                fontWeight: 600,
                cursor: selected ? "pointer" : "not-allowed",
              }}
            >
              선택 장소로 MERGE
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
