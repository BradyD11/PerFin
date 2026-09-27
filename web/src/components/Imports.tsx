import { useRef } from "react";
import type { Account, ImportReport } from "../api";
import { plural } from "../format";
import { Caution, Tick, UploadMark } from "./icons";

export type ImportOutcome =
  | { kind: "ok"; file: string; report: ImportReport }
  | { kind: "err"; file: string; account: string; message: string };

type Target = { account: string; label: string };

/**
 * Which upload buttons to show. Every existing account gets one; if there is
 * no liability or no asset account yet, the canonical credit-card / checking
 * account is offered, and the server creates it on first upload.
 */
export function uploadTargets(accounts: Account[]): Target[] {
  const label = (a: Account) =>
    a.name === "credit-card" ? "Credit card CSV" : a.name === "checking" ? "Checking CSV" : `${a.name} CSV`;
  const ordered = [...accounts].sort((a, b) =>
    a.type === b.type ? a.name.localeCompare(b.name) : a.type === "liability" ? -1 : 1);
  const targets = ordered.map((a) => ({ account: a.name, label: label(a) }));
  if (!accounts.some((a) => a.type === "liability"))
    targets.unshift({ account: "credit-card", label: "Credit card CSV" });
  if (!accounts.some((a) => a.type === "asset"))
    targets.push({ account: "checking", label: "Checking CSV" });
  return targets;
}

type Props = {
  accounts: Account[];
  demo: boolean;
  busyAccount: string | null;
  onUpload: (account: string, file: File) => void;
};

export function Imports({ accounts, demo, busyAccount, onUpload }: Props) {
  const inputs = useRef<Record<string, HTMLInputElement | null>>({});
  const targets = uploadTargets(accounts);

  return (
    <div className="imports" role="group" aria-labelledby="imports-title">
      <h2 id="imports-title" className="imports-title">Import a statement</h2>
      <div className="imports-row">
        {targets.map((t) => (
          <span key={t.account}>
            <button
              type="button"
              className="btn"
              disabled={demo || busyAccount !== null}
              onClick={() => inputs.current[t.account]?.click()}
            >
              <UploadMark className="i" />
              {busyAccount === t.account ? "Importing…" : t.label}
            </button>
            <input
              ref={(el) => { inputs.current[t.account] = el; }}
              type="file"
              accept=".csv,text/csv"
              className="sr-only"
              tabIndex={-1}
              aria-hidden="true"
              onChange={(e) => {
                const f = e.target.files?.[0];
                e.target.value = ""; // the same file can be chosen again
                if (f) onUpload(t.account, f);
              }}
            />
          </span>
        ))}
      </div>
      <p className="help">
        {demo
          ? "Uploads are off in the specimen, so real statements never mix with its synthetic data. Run `ledger serve --db ledger.db` to import your own."
          : "Re-importing a statement is safe: lines already on the ledger are recognized and skipped."}
      </p>
    </div>
  );
}

/** The import slip: what the upload did, line by line, in the statement's voice. */
export function ImportSlip({ outcome, onDismiss }: { outcome: ImportOutcome; onDismiss: () => void }) {
  if (outcome.kind === "err") {
    return (
      <section className="slip slip-bad" aria-live="polite">
        <div className="slip-head">
          <p className="slip-title"><Caution className="i" /> Couldn’t import {outcome.file} into {outcome.account}</p>
          <button type="button" className="btn btn-quiet" onClick={onDismiss}>Dismiss</button>
        </div>
        {outcome.message.split("\n").map((line, i) => <p key={i} className="slip-line">{line}</p>)}
      </section>
    );
  }
  const r = outcome.report;
  return (
    <section className="slip" aria-live="polite">
      <div className="slip-head">
        <p className="slip-title"><Tick className="i" /> Imported {outcome.file} into {r.account}</p>
        <button type="button" className="btn btn-quiet" onClick={onDismiss}>Dismiss</button>
      </div>
      <table className="slip-table">
        <tbody>
          <tr><th scope="row">New lines</th><td className="num">{r.inserted.toLocaleString("en-US")}</td></tr>
          <tr><th scope="row">Already on the ledger, skipped</th><td className="num">{r.skipped.toLocaleString("en-US")}</td></tr>
          <tr><th scope="row">Filed by your rules</th><td className="num">{r.byRules.toLocaleString("en-US")}</td></tr>
          <tr className="slip-total"><th scope="row">Added to review</th><td className="num">{r.newOpen.toLocaleString("en-US")}</td></tr>
        </tbody>
      </table>
      {r.malformed.length > 0 && (
        <details className="slip-aside">
          <summary>{plural(r.malformed.length, "row")} couldn’t be read and {r.malformed.length === 1 ? "was" : "were"} left out</summary>
          <ul>
            {r.malformed.map((m) => <li key={m.line}><span className="num">Line {m.line}</span>: {m.problem}</li>)}
          </ul>
        </details>
      )}
      {r.created && (
        <p className="slip-note">
          Created the <b>{r.account}</b> account ({r.type}) with no opening balance. Categorizing doesn’t need one;
          for net worth, set it from a statement with{" "}
          <code>ledger account init --name {r.account} --type {r.type} --balance … --as-of …</code>.
        </p>
      )}
      {r.type === "asset" && r.inserted > 0 && (
        <p className="slip-note">
          This checking layout hasn’t been confirmed against your bank’s export yet. Check it once with{" "}
          <code>ledger reconcile --account {r.account} --date … --balance …</code> using a balance printed on the
          statement.
        </p>
      )}
    </section>
  );
}
