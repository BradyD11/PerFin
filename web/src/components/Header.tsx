import type { LedgerState } from "../api";
import { period, plural } from "../format";

export type Session = {
  /** Uncategorized lines when this page first loaded. */
  beginning: number;
  filed: number;
  returned: number;
};

type Props = { state: LedgerState | null; session: Session | null };

/**
 * The statement header: who and what period on the left, the activity summary
 * on the right. The summary is a real reconciliation, laid out the way a bank
 * lays out a balance: beginning, minus what was filed, plus what undo
 * returned, equals what remains. Each figure has its own source (the first
 * load, the server's decision counts, the server's current total), so if they
 * ever failed to add up the discrepancy would be visible, not hidden.
 */
export function Header({ state, session }: Props) {
  const open = state?.totals.openItems;
  const merchants = state?.totals.openMerchants;
  const balanced =
    session && open !== undefined
      ? session.beginning - session.filed + session.returned === open
      : true;

  return (
    <>
    <div className="microprint" aria-hidden="true">
      {"LEDGER UNCATEGORIZED ITEMS REVIEW ".repeat(60)}
    </div>
    <header className="statement-head">
      <div className="head-id">
        <div className="wordmark">ledger</div>
        <h1>Uncategorized items</h1>
        <div className="head-row">
          <dl className="head-meta">
            <div>
              <dt>Statement period</dt>
              <dd>{state ? period(state.period.from, state.period.to) : "Loading…"}</dd>
            </div>
            <div>
              <dt>Categorized</dt>
              <dd className="num">
                {state ? `${state.totals.filed.toLocaleString("en-US")} of ${plural(state.totals.items, "line")}` : "—"}
              </dd>
            </div>
          </dl>
          {state?.demo && (
            <p className="specimen" role="note">
              <span className="specimen-word">Specimen</span>
              <span>Synthetic data. Not a real account.</span>
            </p>
          )}
        </div>
      </div>

      <section className="summary" aria-labelledby="summary-title">
        <h2 id="summary-title">Review activity summary</h2>
        <table>
          <tbody>
            <tr>
              <th scope="row">Uncategorized at start of session</th>
              <td className="num">{session ? session.beginning.toLocaleString("en-US") : "—"}</td>
            </tr>
            <tr>
              <th scope="row">Filed this session</th>
              <td className="num">{session ? `− ${session.filed.toLocaleString("en-US")}` : "—"}</td>
            </tr>
            <tr>
              <th scope="row">Returned by undo</th>
              <td className="num">{session ? `+ ${session.returned.toLocaleString("en-US")}` : "—"}</td>
            </tr>
            <tr className="summary-total">
              <th scope="row">Uncategorized now</th>
              <td className="num">{open !== undefined ? open.toLocaleString("en-US") : "—"}</td>
            </tr>
          </tbody>
        </table>
        {/* Phones get the same reconciliation on one line, so the statement
            lines still reach the first screen above the filing sheet. */}
        <p className="summary-line num" aria-hidden="true">
          {session && open !== undefined
            ? `${session.beginning} − ${session.filed} + ${session.returned} = ${open} uncategorized`
            : "\u00a0"}
        </p>
        <p className="summary-foot">
          {merchants !== undefined ? `${plural(merchants, "merchant")} left to file` : " "}
          {!balanced && (
            <span className="summary-warn">
              {" "}· Changed outside this page since it loaded
            </span>
          )}
        </p>
      </section>
    </header>
    </>
  );
}
