import { useCallback, useState } from "react";
import type { Decision, Group, Money, Row } from "../api";
import { locate, plural, shortDate } from "../format";
import { ArrowMark, Tick, UndoMark } from "./icons";

/** A decision made this session, written back onto the statement. */
export type FiledRun = {
  decision: Decision;
  label: string;
  /** The merchant that was open when it was filed. */
  groupKey: string;
  /** Server-computed total, when the rule filed exactly one merchant. */
  total: Money | null;
  merchants: number;
};

export type Reach = {
  needle: string;
  /** Row ids the rule would file. */
  files: Set<string>;
  /** Row ids a longer existing rule claims instead. */
  shadowed: Set<string>;
  /** Merchant key -> rows the rule would file there. */
  byMerchant: Map<string, number>;
};

type Props = {
  queue: Group[] | null;
  focusKey: string | null;
  reach: Reach | null;
  /** The group whose lines are being ticked off right now. */
  filingKey: string | null;
  demo: boolean;
  filed: FiledRun[];
  /** The newest decision, if it predates this page (made in the CLI, say). */
  earlier: Decision | null;
  undoId: number | null;
  busy: boolean;
  labelFor: (id: string) => string;
  onFocus: (key: string) => void;
  onSelectText: (key: string, text: string) => void;
  onReset: () => void;
  onUndo: () => void;
};

const FILED_SHOWN = 4;

export function Ledger({
  queue, focusKey, reach, filingKey, demo, filed, earlier, undoId, busy, labelFor,
  onFocus, onSelectText, onReset, onUndo,
}: Props) {
  const [allFiled, setAllFiled] = useState(false);
  // Selecting text inside a description sets the rule for that merchant.
  // Only a selection that stays within one description counts; anything
  // wider is an ordinary copy gesture and is left alone.
  const handleMouseUp = useCallback(() => {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed) return;
    const within = (n: Node | null) =>
      (n instanceof Element ? n : n?.parentElement)?.closest<HTMLElement>("[data-desc]");
    const a = within(sel.anchorNode);
    const b = within(sel.focusNode);
    if (!a || a !== b) return;
    const text = sel.toString().replace(/\s+/g, " ").trim();
    if (text) onSelectText(a.dataset.desc!, text);
  }, [onSelectText]);

  const index = queue && focusKey ? queue.findIndex((g) => g.key === focusKey) : -1;

  return (
    <section className="history" aria-labelledby="history-title">
      <div className="history-head">
        <h2 id="history-title">Transaction history</h2>
        {queue && queue.length > 0 && (
          <span className="pager num" aria-live="polite">
            Merchant {Math.max(index, 0) + 1} of {queue.length}
          </span>
        )}
      </div>

      <table className="lines" onMouseUp={handleMouseUp}>
        <colgroup>
          <col className="w-gutter" />
          <col className="w-date" />
          <col className="w-acct" />
          <col />
          <col className="w-amt" />
          <col className="w-amt" />
        </colgroup>
        <thead>
          <tr>
            <th scope="col"><span className="sr-only">Mark</span></th>
            <th scope="col">Date</th>
            <th scope="col" className="c-acct">Account</th>
            <th scope="col">Description</th>
            <th scope="col" className="c-num">Additions</th>
            <th scope="col" className="c-num">Subtractions</th>
          </tr>
        </thead>

        {queue === null && <Skeleton />}

        {(filed.length > 0 || earlier) && (
          <tbody className="filed-band">
            {earlier && (
              <tr className="filed">
                <td className="c-gutter"><Tick className="tick-set" /></td>
                <td className="c-count num" colSpan={2}>Earlier</td>
                <td className="c-desc" colSpan={3}>
                  <div className="filed-line">
                    <span className="filed-name">{earlier.needle}</span>
                    <span className="annot-note">
                      <ArrowMark className="arrow" />
                      <span className="sr-only">filed as</span>
                      {labelFor(earlier.category)} · {plural(earlier.rows, "line")}
                    </span>
                    <UndoButton busy={busy} onUndo={onUndo} />
                  </div>
                </td>
              </tr>
            )}
            {filed.length > FILED_SHOWN && !allFiled && (
              <tr className="filed filed-more">
                <td className="c-gutter" />
                <td colSpan={5}>
                  <button type="button" className="btn btn-quiet" onClick={() => setAllFiled(true)}>
                    Show {plural(filed.length - FILED_SHOWN, "earlier filed run")}
                  </button>
                </td>
              </tr>
            )}
            {(allFiled ? filed : filed.slice(-FILED_SHOWN)).map((f) => {
              const inflow = f.total?.direction === "in";
              // An outflow leaves Additions empty and the description can
              // absorb it; with no single total, it absorbs both columns.
              const span = !f.total ? 3 : inflow ? 1 : 2;
              return (
              <tr key={f.decision.id} className="filed">
                <td className="c-gutter"><Tick className="tick-set" /></td>
                <td className="c-count num" colSpan={2}>{plural(f.decision.rows, "line")}</td>
                <td className="c-desc" colSpan={span}>
                  <div className="filed-line">
                    <span className="filed-name" title={f.groupKey}>{f.groupKey}</span>
                    <span className="annot-note">
                      <ArrowMark className="arrow" />
                      <span className="sr-only">filed as</span>
                      {f.label} · rule “{f.decision.needle}”
                      {f.merchants > 1 && ` · ${f.merchants} merchants`}
                    </span>
                    {undoId === f.decision.id && <UndoButton busy={busy} onUndo={onUndo} />}
                  </div>
                </td>
                {f.total && inflow && (
                  <>
                    <td className="c-num c-add num">{f.total.magnitude}</td>
                    <td className="c-num c-sub" />
                  </>
                )}
                {f.total && !inflow && (
                  <td className="c-num c-sub num">{f.total.magnitude}</td>
                )}
              </tr>
              );
            })}
          </tbody>
        )}

        {queue?.map((g) => (
          <GroupRows
            key={g.key}
            group={g}
            focused={g.key === focusKey}
            filing={g.key === filingKey}
            reach={reach}
            onFocus={onFocus}
          />
        ))}
      </table>

      {queue && queue.length === 0 && (
        <div className="closing">
          <p className="closing-line">
            <span>Uncategorized ending balance</span>
            <span className="num">0 lines</span>
          </p>
          <p>Every line on this ledger carries a category.</p>
          {demo ? (
            <button type="button" className="btn" onClick={onReset}>
              Reprint the specimen
            </button>
          ) : (
            <p className="muted">
              New lines arrive with the next <code>ledger import</code>.
            </p>
          )}
        </div>
      )}
    </section>
  );
}

function GroupRows({
  group, focused, filing, reach, onFocus,
}: {
  group: Group;
  focused: boolean;
  filing: boolean;
  reach: Reach | null;
  onFocus: (key: string) => void;
}) {
  const caught = reach?.byMerchant.get(group.key) ?? 0;
  const keyMark = reach && caught > 0 ? locateExact(group.key, reach.needle) : null;

  return (
    <tbody className={["group", focused && "is-focused", filing && "is-filing"].filter(Boolean).join(" ")}>
      <tr className="group-head">
        <td className="c-gutter" />
        <td className="c-count num" colSpan={2}>{plural(group.count, "line")}</td>
        <td className="c-desc">
          <button
            type="button"
            className="group-name"
            aria-expanded={focused}
            onClick={() => onFocus(group.key)}
          >
            {keyMark ? (
              <>
                {group.key.slice(0, keyMark[0])}
                <mark className="hl">{group.key.slice(keyMark[0], keyMark[1])}</mark>
                {group.key.slice(keyMark[1])}
              </>
            ) : (
              group.key
            )}
          </button>
          <span className="c-amt-inline num">
            {group.total.direction === "in" ? "+" : "−"}{group.total.magnitude}
          </span>
          {!focused && caught > 0 && (
            <span className="caught num">
              Rule catches {caught === group.count ? `all ${caught}` : `${caught} of ${group.count}`}
            </span>
          )}
        </td>
        <Amounts row={{ amount: group.total }} />
      </tr>

      {focused &&
        group.rows.map((r, i) => (
          <Line key={r.id} row={r} index={i} groupKey={group.key} reach={reach} />
        ))}
    </tbody>
  );
}

function Line({ row, index, groupKey, reach }: {
  row: Row; index: number; groupKey: string; reach: Reach | null;
}) {
  const files = reach?.files.has(row.id) ?? false;
  const shadowed = reach?.shadowed.has(row.id) ?? false;
  const span = reach && (files || shadowed) ? locate(row.merchant, reach.needle) : null;

  return (
    <tr className="line" style={{ ["--i" as string]: index }}>
      <td className="c-gutter"><Tick className="tick" /></td>
      <td className="c-date num">{shortDate(row.date)}</td>
      <td className="c-acct">{row.account}</td>
      <td className="c-desc">
        <span className="desc-text" data-desc={groupKey}>
          {span ? (
            <>
              {row.merchant.slice(0, span[0])}
              <mark className={shadowed ? "hl hl-shadowed" : "hl"}>
                {row.merchant.slice(span[0], span[1])}
              </mark>
              {row.merchant.slice(span[1])}
            </>
          ) : (
            row.merchant
          )}
        </span>
        <span className="c-amt-inline num">
          {row.amount.direction === "in" ? "+" : "−"}{row.amount.magnitude}
        </span>
      </td>
      <Amounts row={row} />
    </tr>
  );
}

/** Statement grammar: direction is which column the figure sits in. */
function Amounts({ row }: { row: Pick<Row, "amount"> }) {
  const inflow = row.amount.direction === "in";
  return (
    <>
      <td className="c-num c-add num">{inflow ? row.amount.magnitude : ""}</td>
      <td className="c-num c-sub num">{inflow ? "" : row.amount.magnitude}</td>
    </>
  );
}

function UndoButton({ busy, onUndo }: { busy: boolean; onUndo: () => void }) {
  return (
    <button type="button" className="btn btn-quiet undo-inline" onClick={onUndo} disabled={busy}
      aria-keyshortcuts="z">
      <UndoMark className="i" /> Undo <kbd>Z</kbd>
    </button>
  );
}

function locateExact(hay: string, needle: string): [number, number] | null {
  const i = hay.indexOf(needle);
  return i < 0 ? null : [i, i + needle.length];
}

function Skeleton() {
  return (
    <tbody className="skeleton" aria-hidden="true">
      {Array.from({ length: 9 }, (_, i) => (
        <tr key={i}>
          <td />
          <td><span className="bar" style={{ width: "70%" }} /></td>
          <td className="c-acct"><span className="bar" style={{ width: "80%" }} /></td>
          <td><span className="bar" style={{ width: `${38 + ((i * 17) % 40)}%` }} /></td>
          <td />
          <td className="c-num"><span className="bar" style={{ width: "60%" }} /></td>
        </tr>
      ))}
    </tbody>
  );
}
