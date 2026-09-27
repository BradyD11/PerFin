import { forwardRef } from "react";
import type { Category, Group, Preview, Row } from "../api";
import { plural, shortDate } from "../format";
import { Caution, Chevron } from "./icons";

export type PreviewState =
  | { status: "loading" }
  | { status: "ready"; preview: Preview }
  | { status: "failed"; message: string };

export type Fileable = { ok: true } | { ok: false; reason: string };

type Props = {
  group: Group | null;
  pattern: string;
  preview: PreviewState;
  fileable: Fileable;
  categories: Category[];
  busy: boolean;
  labelFor: (id: string) => string;
  onPattern: (value: string) => void;
  onResetPattern: () => void;
  onFile: (categoryId: string) => void;
};

/**
 * The pending annotation for the open merchant: its rule, what the rule
 * reaches, and the keys that file it. Decisions already made are written on
 * the statement itself (see Ledger), not repeated here.
 */
export const Margin = forwardRef<HTMLInputElement, Props>(function Margin(
  { group, pattern, preview, fileable, categories, busy, labelFor,
    onPattern, onResetPattern, onFile },
  inputRef,
) {
  if (!group) {
    return (
      <aside className="margin" aria-label="Annotation">
        <p className="filing-name">Nothing to file</p>
        <p className="filing-sub">Your saved rules will file new lines as they are imported.</p>
      </aside>
    );
  }

  return (
    <aside className="margin" aria-label="Annotation">
      <p className="filing-name" title={group.key}>{group.key}</p>
      <p className="filing-sub num">
        {plural(group.count, "line")} · {group.total.magnitude}{" "}
        {group.total.direction === "in" ? "in" : "out"}
      </p>

      <div className="field">
        <label htmlFor="rule">Rule: description contains</label>
        <div className="field-row">
          <input
            id="rule"
            ref={inputRef}
            value={pattern}
            onChange={(e) => onPattern(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Escape") {
                onResetPattern();
                e.currentTarget.blur();
              }
              if (e.key === "Enter") e.currentTarget.blur();
            }}
            spellCheck={false}
            autoComplete="off"
            aria-describedby="rule-help"
          />
          {pattern !== group.key && (
            <button type="button" className="btn btn-quiet" onClick={onResetPattern}>
              Use full description
            </button>
          )}
        </div>
        <p id="rule-help" className="help">Select text in any description to set this.</p>
      </div>

      <ReachBlock group={group} pattern={pattern} preview={preview} labelFor={labelFor} />

      <div className="keys" role="group" aria-labelledby="keys-title">
        <h3 id="keys-title">File under</h3>
        <div className="key-grid">
          {categories.map((c) => (
            <button
              key={c.id}
              type="button"
              className="key"
              disabled={!fileable.ok || busy}
              aria-keyshortcuts={String(c.key)}
              onClick={() => onFile(c.id)}
            >
              <kbd>{c.key}</kbd>
              <span>{c.label}</span>
            </button>
          ))}
        </div>
        <p className={fileable.ok ? "help" : "help help-block"} aria-live="polite">
          {fileable.ok ? "Press a number to file. The rule is saved with it." : fileable.reason}
        </p>
      </div>

      <p className="shortcuts">
        <kbd>1</kbd>–<kbd>7</kbd> file · <kbd>J</kbd>/<kbd>K</kbd> move · <kbd>/</kbd> edit rule ·{" "}
        <kbd>Z</kbd> undo
      </p>
    </aside>
  );
});

function ReachBlock({ group, pattern, preview, labelFor }: {
  group: Group; pattern: string; preview: PreviewState; labelFor: (id: string) => string;
}) {
  if (preview.status === "loading") {
    return (
      <div className="reach" aria-busy="true">
        <h3>Reach</h3>
        <p className="reach-lead muted">Checking what this rule catches…</p>
      </div>
    );
  }
  if (preview.status === "failed") {
    return (
      <div className="reach">
        <h3>Reach</h3>
        <p className="reach-lead reach-bad"><Caution className="i" /> {preview.message}</p>
      </div>
    );
  }
  const p = preview.preview;
  if (!p.ok) {
    return (
      <div className="reach">
        <h3>Reach</h3>
        <p className="reach-lead reach-bad">
          <Caution className="i" />
          {p.error.code === "empty"
            ? "Type a pattern, or select text in a description."
            : `Digits are ignored when matching, so “${p.error.pattern}” would match every merchant. Keep some letters.`}
        </p>
      </div>
    );
  }

  const merchants = p.merchants.length;
  const reachesFocus = p.merchants.some((m) => m.key === group.key);
  // A list of one merchant, the one already open, would repeat the ledger.
  const onlyThis = merchants === 1 && reachesFocus;

  return (
    <div className="reach">
      <h3>Reach</h3>
      <p className="reach-lead">
        Files <b className="num">{plural(p.wouldFile.length, "line")}</b>
        {onlyThis && <span className="muted">, this merchant only</span>}
        {merchants > 1 && <> across <b className="num">{merchants} merchants</b></>}
      </p>
      {/* Only worth saying when what is saved differs from what was typed. */}
      {p.needle !== pattern && (
        <p className="saved-as">
          Saved as: contains <mark className="hl">{p.needle}</mark>
        </p>
      )}

      {!reachesFocus && p.wouldFile.length > 0 && (
        <p className="reach-bad"><Caution className="i" /> Doesn't reach {group.key}.</p>
      )}

      {!onlyThis && merchants > 0 && (
        <ul className="reach-list">
          {p.merchants.map((m) => (
            <li key={m.key}>
              <details>
                <summary>
                  <Chevron className="chev" />
                  <span className="rl-name">
                    {m.key}
                    {m.key === group.key && <span className="rl-this"> · this merchant</span>}
                  </span>
                  <span className="rl-count num">{m.count}</span>
                </summary>
                <RowList rows={p.wouldFile.filter((r) => r.key === m.key)} />
              </details>
            </li>
          ))}
        </ul>
      )}

      {p.leftAlone.length > 0 && (
        <details className="reach-aside">
          <summary>
            <Chevron className="chev" />
            <span>
              Leaves <span className="num">{plural(p.leftAlone.length, "categorized line")}</span> as they are
            </span>
          </summary>
          <RowList rows={p.leftAlone} note={(r) => labelFor(r.category)} />
        </details>
      )}

      {p.shadowed.length > 0 && (
        <details className="reach-aside">
          <summary>
            <Chevron className="chev" />
            <span>
              <span className="num">{plural(p.shadowed.length, "line")}</span> matched, but a longer rule
              claims {p.shadowed.length === 1 ? "it" : "them"}
            </span>
          </summary>
          <RowList rows={p.shadowed} />
        </details>
      )}
    </div>
  );
}

function RowList({ rows, note }: { rows: Row[]; note?: (r: Row) => string }) {
  return (
    <table className="mini">
      <tbody>
        {rows.map((r) => (
          <tr key={r.id}>
            <td className="num">{shortDate(r.date)}</td>
            <td className="mini-desc">
              {r.merchant}
              {note && <span className="mini-note"> · {note(r)}</span>}
            </td>
            <td className="num c-num">
              {r.amount.direction === "in" ? "+" : "−"}{r.amount.magnitude}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
