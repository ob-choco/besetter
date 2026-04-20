"use client";
import { useCallback, useEffect, useState } from "react";
import { QueueList } from "@/components/queue-list";
import { PlaceDetail } from "@/components/place-detail";
import { MergeDialog } from "@/components/merge-dialog";

type PendingPlace = {
  _id: string;
  name: string;
  createdAt: string;
  creator: { profileId: string } | null;
};

export default function PlacesPage() {
  const [items, setItems] = useState<PendingPlace[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<any>(null);
  const [mergeOpen, setMergeOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refreshList = useCallback(async () => {
    const res = await fetch("/api/places/pending");
    if (!res.ok) return;
    const data = await res.json();
    setItems(data.places);
  }, []);

  useEffect(() => { refreshList(); }, [refreshList]);

  useEffect(() => {
    if (!selectedId) { setDetail(null); return; }
    fetch(`/api/places/${selectedId}`)
      .then((r) => (r.ok ? r.json() : null))
      .then(setDetail)
      .catch(() => setDetail(null));
  }, [selectedId]);

  async function runAction(path: string, body: unknown = {}) {
    setError(null);
    const res = await fetch(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      if (res.status === 409) setError("이미 다른 운영자가 처리했습니다. 목록을 새로고침합니다.");
      else setError(`오류: ${res.status}`);
    }
    await refreshList();
    setSelectedId(null);
    setMergeOpen(false);
  }

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <QueueList
        title="신규 gym 큐"
        items={items.map((p) => ({ id: p._id, ...p })) as any}
        selectedId={selectedId}
        onSelect={setSelectedId}
        renderItem={(raw) => {
          const p = raw as unknown as PendingPlace;
          return (
            <>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#8b93a7" }}>
                <span>{new Date(p.createdAt).toLocaleString()}</span>
                <span>by @{p.creator?.profileId ?? "?"}</span>
              </div>
              <div style={{ marginTop: 4, fontWeight: 600 }}>{p.name}</div>
            </>
          );
        }}
      />
      {detail ? (
        <PlaceDetail
          detail={detail}
          onPass={() => runAction(`/api/places/${detail.place._id}/pass`)}
          onFail={(reason) => runAction(`/api/places/${detail.place._id}/fail`, reason ? { reason } : {})}
          onOpenMerge={() => setMergeOpen(true)}
        />
      ) : (
        <div style={{ flex: 1, padding: 24, color: "#6b7388" }}>큐에서 항목을 선택하세요.</div>
      )}
      {mergeOpen && detail ? (
        <MergeDialog
          source={detail.place}
          counts={detail.counts}
          onClose={() => setMergeOpen(false)}
          onConfirm={(targetPlaceId) =>
            runAction(`/api/places/${detail.place._id}/merge`, { targetPlaceId })
          }
        />
      ) : null}
      {error ? (
        <div
          style={{
            position: "fixed",
            bottom: 20,
            right: 20,
            background: "#2b1d1d",
            border: "1px solid #d04848",
            borderRadius: 6,
            padding: "10px 14px",
            color: "#ffb3b3",
          }}
        >
          {error}
        </div>
      ) : null}
    </div>
  );
}
