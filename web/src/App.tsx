import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api, type LedgerState } from "./api";
import { plural } from "./format";
import { Header, type Session } from "./components/Header";
import { Ledger, type FiledRun, type Reach } from "./components/Ledger";
import { Margin, type Fileable, type PreviewState } from "./components/Margin";
import { Caution, Tick, UndoMark } from "./components/icons";

type Shown = { key: string; pattern: string; version: number; result: PreviewState };
type Notice = { kind: "ok" | "err"; text: string; undoable?: boolean };

const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function App() {
  const [state, setState] = useState<LedgerState | null>(null);
  // Bumped on every server state, so a preview computed against older data
  // is recognizably stale.
  const [version, setVersion] = useState(0);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [focusKey, setFocusKey] = useState<string | null>(null);
  const [patterns, setPatterns] = useState<Record<string, string>>({});
  const [shown, setShown] = useState<Shown | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  // Decisions made on this page, oldest first. Undone ones are removed: their
  // lines are back in the queue, so the annotation is erased.
  const [filed, setFiled] = useState<FiledRun[]>([]);
  // Scroll the open merchant into view only after the user moves focus, never
  // on first load, where it would push the header (and on the demo, its
  // synthetic-data disclosure) off a phone screen.
  const userMoved = useRef(false);
  const [busy, setBusy] = useState(false);
  const [filingKey, setFilingKey] = useState<string | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const applyState = useCallback((s: LedgerState, prefer?: string | null) => {
    setState(s);
    setVersion((v) => v + 1);
    setFocusKey((current) => {
      const want = prefer ?? current;
      return want && s.queue.some((g) => g.key === want) ? want : s.queue[0]?.key ?? null;
    });
  }, []);

  const load = useCallback(() => {
    setLoadError(null);
    api.state().then(
      (s) => {
        applyState(s);
        setSession((prev) => prev ?? { beginning: s.totals.openItems, filed: 0, returned: 0 });
      },
      (e: Error) => setLoadError(e.message),
    );
  }, [applyState]);

  useEffect(load, [load]);

  const group = state?.queue.find((g) => g.key === focusKey) ?? null;
  const pattern = group ? patterns[group.key] ?? group.key : "";

  // Preview the rule as it is typed. The previous preview stays on screen
  // while the next one is fetched, so the reach never blinks empty; filing
  // is locked until the preview on screen is for exactly this rule.
  useEffect(() => {
    if (!group) return;
    const ctrl = new AbortController();
    const key = group.key;
    const t = setTimeout(() => {
      api.preview(pattern, ctrl.signal).then(
        (p) => setShown({ key, pattern, version, result: { status: "ready", preview: p } }),
        (e: Error) => {
          if (e.name !== "AbortError")
            setShown({ key, pattern, version, result: { status: "failed", message: e.message } });
        },
      );
    }, 110);
    return () => {
      clearTimeout(t);
      ctrl.abort();
    };
  }, [group?.key, pattern, version]);

  const preview: PreviewState =
    shown && group && shown.key === group.key ? shown.result : { status: "loading" };
  const fresh = !!shown && !!group && shown.key === group.key && shown.pattern === pattern
    && shown.version === version;

  const labelFor = useCallback(
    (id: string) => state?.categories.find((c) => c.id === id)?.label ?? id,
    [state],
  );

  const fileable: Fileable = useMemo(() => {
    if (!group) return { ok: false, reason: "Nothing to file." };
    if (!fresh || preview.status === "loading")
      return { ok: false, reason: "Checking what this rule catches…" };
    if (preview.status === "failed") return { ok: false, reason: preview.message };
    const p = preview.preview;
    if (!p.ok) return { ok: false, reason: "Fix the rule before filing." };
    if (p.wouldFile.length === 0)
      return { ok: false, reason: "This rule doesn't catch any uncategorized line." };
    if (!p.merchants.some((m) => m.key === group.key))
      return { ok: false, reason: "This rule doesn't reach the merchant you're filing. Adjust it, or use the full description." };
    return { ok: true };
  }, [group, fresh, preview]);

  const reach: Reach | null = useMemo(() => {
    if (preview.status !== "ready" || !preview.preview.ok) return null;
    const p = preview.preview;
    return {
      needle: p.needle,
      files: new Set(p.wouldFile.map((r) => r.id)),
      shadowed: new Set(p.shadowed.map((r) => r.id)),
      byMerchant: new Map(p.merchants.map((m) => [m.key, m.count])),
    };
  }, [preview]);

  const say = useCallback((n: Notice) => setNotice(n), []);
  useEffect(() => {
    if (!notice) return;
    // A filing notice carries its undo, so it stays until the next action;
    // plain notices clear themselves.
    if (notice.undoable) return;
    const t = setTimeout(() => setNotice(null), 5000);
    return () => clearTimeout(t);
  }, [notice]);

  const file = useCallback(async (categoryId: string) => {
    if (!state || !group || !fileable.ok || busy) return;
    const order = state.queue.map((g) => g.key);
    const at = order.indexOf(group.key);
    const hits = preview.status === "ready" && preview.preview.ok ? preview.preview.merchants : [];
    setBusy(true);
    setFilingKey(group.key);
    try {
      // The ticks are set while the request is in flight; neither waits
      // longer than it has to.
      const [res] = await Promise.all([
        api.decide(pattern, categoryId),
        wait(reducedMotion() ? 0 : 380),
      ]);
      const label = labelFor(res.decision.category);
      setFiled((f) => [...f, {
        decision: res.decision,
        label,
        groupKey: group.key,
        total: hits.length === 1 ? hits[0].total : null,
        merchants: hits.length,
      }]);
      userMoved.current = true;
      setSession((s) => s && { ...s, filed: s.filed + res.decision.rows });
      const next = order.slice(at + 1).find((k) => res.state.queue.some((g) => g.key === k));
      applyState(res.state, next ?? null);
      say({ kind: "ok", text: `Filed ${plural(res.decision.rows, "line")} under ${label}.`, undoable: true });
    } catch (e) {
      say({ kind: "err", text: (e as Error).message });
    } finally {
      setBusy(false);
      setFilingKey(null);
    }
  }, [state, group, fileable, busy, pattern, preview, labelFor, applyState, say]);

  const undo = useCallback(async () => {
    if (busy || !state?.lastDecision) return;
    setBusy(true);
    try {
      const res = await api.undo();
      if (!res.undone) {
        say({ kind: "err", text: "Nothing to undo." });
        applyState(res.state);
        return;
      }
      const undone = res.undone;
      const entry = filed.find((f) => f.decision.id === undone.id);
      setFiled((f) => f.filter((x) => x.decision.id !== undone.id));
      userMoved.current = true;
      setSession((s) => s && { ...s, returned: s.returned + res.reverted });
      applyState(res.state, entry?.groupKey ?? null);
      say({ kind: "ok", text: `Undid ${undone.needle}. ${plural(res.reverted, "line")} back to uncategorized.` });
    } catch (e) {
      say({ kind: "err", text: (e as Error).message });
    } finally {
      setBusy(false);
    }
  }, [busy, state, filed, applyState, say]);

  const reset = useCallback(async () => {
    try {
      const s = await api.reset();
      setFiled([]);
      setPatterns({});
      setSession({ beginning: s.totals.openItems, filed: 0, returned: 0 });
      applyState(s, null);
    } catch (e) {
      say({ kind: "err", text: (e as Error).message });
    }
  }, [applyState, say]);

  const move = useCallback((delta: number) => {
    if (!state || state.queue.length === 0) return;
    const i = state.queue.findIndex((g) => g.key === focusKey);
    const j = Math.min(state.queue.length - 1, Math.max(0, (i < 0 ? 0 : i) + delta));
    userMoved.current = true;
    setFocusKey(state.queue[j].key);
  }, [state, focusKey]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      if (t && (t.closest("input, textarea, select, [contenteditable='true']"))) return;
      const mod = e.metaKey || e.ctrlKey;
      if (mod && e.key.toLowerCase() === "z") {
        e.preventDefault();
        void undo();
        return;
      }
      if (mod || e.altKey) return;
      const cat = state?.categories.find((c) => String(c.key) === e.key);
      if (cat) {
        e.preventDefault();
        void file(cat.id);
      } else if (e.key === "j" || e.key === "ArrowDown") {
        e.preventDefault();
        move(1);
      } else if (e.key === "k" || e.key === "ArrowUp") {
        e.preventDefault();
        move(-1);
      } else if (e.key === "/" || e.key === "e") {
        e.preventDefault();
        inputRef.current?.focus();
        inputRef.current?.select();
      } else if (e.key === "z") {
        e.preventDefault();
        void undo();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [state, file, undo, move]);

  // Keep the open merchant in view as the user moves through the queue.
  useEffect(() => {
    if (!userMoved.current) return;
    userMoved.current = false;
    document.querySelector(".group.is-focused")?.scrollIntoView({
      block: "nearest",
      behavior: reducedMotion() ? "auto" : "smooth",
    });
  }, [focusKey, version]);

  const selectText = useCallback((key: string, text: string) => {
    setFocusKey(key);
    setPatterns((p) => ({ ...p, [key]: text }));
  }, []);

  if (loadError && !state) {
    return (
      <main className="page page-error">
        <div className="closing">
          <p className="closing-line reach-bad"><Caution className="i" /> {loadError}</p>
          <p>Start it with <code>ledger serve</code> (or <code>ledger serve --demo</code>), then try again.</p>
          <button type="button" className="btn" onClick={load}>Try again</button>
        </div>
      </main>
    );
  }

  return (
    <div className="page">
      <Header state={state} session={session} />
      <div className={`status ${notice ? `is-${notice.kind}` : ""}`}>
        <p role="status" aria-live="polite">
          {notice && (notice.kind === "ok" ? <Tick className="i" /> : <Caution className="i" />)}
          {notice?.text}
        </p>
        {notice?.undoable && state?.lastDecision && (
          <button type="button" className="btn btn-quiet" onClick={undo} disabled={busy}
            aria-keyshortcuts="z">
            <UndoMark className="i" /> Undo <kbd>Z</kbd>
          </button>
        )}
      </div>
      <main className="sheet">
        <Ledger
          queue={state?.queue ?? null}
          focusKey={focusKey}
          reach={reach}
          filingKey={filingKey}
          demo={state?.demo ?? false}
          filed={filed}
          earlier={
            state?.lastDecision && !filed.some((f) => f.decision.id === state.lastDecision!.id)
              ? state.lastDecision
              : null
          }
          undoId={state?.lastDecision?.id ?? null}
          busy={busy}
          labelFor={labelFor}
          onUndo={undo}
          onFocus={setFocusKey}
          onSelectText={selectText}
          onReset={reset}
        />
        {state && (
          <Margin
            ref={inputRef}
            group={group}
            pattern={pattern}
            preview={preview}
            fileable={fileable}
            categories={state.categories}
            busy={busy}
            labelFor={labelFor}
            onPattern={(v) => group && setPatterns((p) => ({ ...p, [group.key]: v }))}
            onResetPattern={() =>
              group && setPatterns((p) => {
                const { [group.key]: _, ...rest } = p;
                return rest;
              })}
            onFile={file}
          />
        )}
      </main>
    </div>
  );
}
