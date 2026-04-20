"use client";
import { useCallback, useEffect, useState } from "react";
import { QueueList } from "@/components/queue-list";
import { SuggestionDiff } from "@/components/suggestion-diff";

type Item = {
  _id: string;
  createdAt: string;
  place: { name: string };
  requester: { profileId: string } | null;
  changes: { name?: string | null; latitude?: number | null; coverImageUrl?: string | null };
};

export default function SuggestionsPage() {
  const [items, setItems] = useState<Item[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const r = await fetch("/api/suggestions/pending");
    if (!r.ok) return;
    const d = await r.json();
    setItems(d.suggestions);
  }, []);
  useEffect(() => { refresh(); }, [refresh]);

  useEffect(() => {
    if (!selectedId) { setDetail(null); return; }
    fetch(`/api/suggestions/${selectedId}`).then((r) => (r.ok ? r.json() : null)).then(setDetail);
  }, [selectedId]);

  async function runAction(path: string, body: unknown = {}) {
    setError(null);
    const res = await fetch(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      if (res.status === 409) setError("이미 다른 운영자가 처리했습니다.");
      else setError(`오류: ${res.status}`);
    }
    await refresh();
    setSelectedId(null);
  }

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <QueueList
        title="수정 제안 큐"
        items={items.map((s) => ({ id: s._id, ...s })) as any}
        selectedId={selectedId}
        onSelect={setSelectedId}
        renderItem={(raw) => {
          const s = raw as unknown as Item;
          const fields = [
            s.changes.name != null && "이름",
            s.changes.latitude != null && "좌표",
            s.changes.coverImageUrl != null && "커버",
          ].filter(Boolean);
          return (
            <>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#8b93a7" }}>
                <span>{new Date(s.createdAt).toLocaleString()}</span>
                <span>by @{s.requester?.profileId ?? "?"}</span>
              </div>
              <div style={{ marginTop: 4, fontWeight: 600 }}>{s.place.name}</div>
              <div style={{ marginTop: 3, fontSize: 11, color: "#6bb4ff" }}>
                제안: {fields.join(", ") || "—"}
              </div>
            </>
          );
        }}
      />
      {detail ? (
        <SuggestionDiff
          detail={detail}
          onApprove={() => runAction(`/api/suggestions/${detail._id}/approve`)}
          onReject={(reason) => runAction(`/api/suggestions/${detail._id}/reject`, reason ? { reason } : {})}
        />
      ) : (
        <div style={{ flex: 1, padding: 24, color: "#6b7388" }}>큐에서 항목을 선택하세요.</div>
      )}
      {error ? (
        <div style={{ position: "fixed", bottom: 20, right: 20, background: "#2b1d1d", border: "1px solid #d04848", borderRadius: 6, padding: "10px 14px", color: "#ffb3b3" }}>
          {error}
        </div>
      ) : null}
    </div>
  );
}
