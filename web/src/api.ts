// Shapes returned by `ledger serve` (src/Server/API.hs). The server owns every
// computation: money arrives pre-formatted, matching and validation happen in
// Haskell, and this module only moves JSON.

export type Money = { cents: number; magnitude: string; direction: "in" | "out" };

export type Row = {
  id: string;
  account: string;
  date: string; // YYYY-MM-DD
  amount: Money;
  merchant: string; // as the bank printed it
  key: string; // normalized merchant, as the server groups and matches it
  category: string;
};

export type Group = { key: string; count: number; total: Money; rows: Row[] };

export type Category = { id: string; label: string; key: number };

export type Decision = { id: number; needle: string; category: string; rows: number };

export type LedgerState = {
  demo: boolean;
  categories: Category[];
  queue: Group[];
  totals: { items: number; filed: number; openItems: number; openMerchants: number };
  period: { from: string | null; to: string | null };
  lastDecision: Decision | null;
  accounts: Account[];
};

export type Account = { name: string; type: "asset" | "liability" };

export type ImportReport = {
  account: string;
  type: "asset" | "liability";
  created: boolean;
  inserted: number;
  skipped: number;
  malformed: { line: number; problem: string }[];
  byRules: number;
  newOpen: number;
};

export type MerchantHit = { key: string; count: number; total: Money };

export type Preview =
  | {
      ok: true;
      needle: string;
      wouldFile: Row[];
      merchants: MerchantHit[];
      leftAlone: Row[];
      shadowed: Row[];
    }
  | { ok: false; error: { code: "empty" | "all-digits"; message: string; pattern: string } };

export class ApiError extends Error {}

async function call<T>(
  method: "GET" | "POST",
  path: string,
  body?: unknown,
  signal?: AbortSignal,
): Promise<T> {
  let res: Response;
  try {
    res = await fetch(path, {
      method,
      headers: body === undefined ? undefined : { "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    });
  } catch (e) {
    if ((e as Error).name === "AbortError") throw e;
    throw new ApiError("The ledger server isn't answering.");
  }
  if (!res.ok) {
    const detail = await res.json().catch(() => null);
    throw new ApiError(detail?.error ?? `The server refused the request (${res.status}).`);
  }
  return res.json() as Promise<T>;
}

export const api = {
  state: () => call<LedgerState>("GET", "/api/state"),
  preview: (pattern: string, signal?: AbortSignal) =>
    call<Preview>("POST", "/api/preview", { pattern }, signal),
  decide: (pattern: string, category: string) =>
    call<{ decision: Decision; state: LedgerState }>("POST", "/api/decisions", {
      pattern,
      category,
    }),
  undo: () =>
    call<{ undone: Decision | null; reverted: number; state: LedgerState }>("POST", "/api/undo"),
  reset: () => call<LedgerState>("POST", "/api/demo/reset"),
  importCsv: (account: string, file: File) =>
    upload<{ report: ImportReport; state: LedgerState }>(
      `/api/import/${encodeURIComponent(account)}`,
      file,
    ),
};

/** Send a file as the raw request body; the server parses it. */
async function upload<T>(path: string, file: File): Promise<T> {
  let res: Response;
  try {
    res = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/octet-stream" },
      body: file,
    });
  } catch {
    throw new ApiError("The ledger server isn't answering.");
  }
  if (!res.ok) {
    const detail = await res.json().catch(() => null);
    throw new ApiError(detail?.error ?? `The server refused the file (${res.status}).`);
  }
  return res.json() as Promise<T>;
}
