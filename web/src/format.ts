// Presentation only: dates and labels. Money is formatted by the server.

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function parts(iso: string): [number, number, number] {
  const [y, m, d] = iso.split("-").map(Number);
  return [y, m, d];
}

/** "2026-09-12" -> "Sep 12" (statement line style). */
export function shortDate(iso: string): string {
  const [, m, d] = parts(iso);
  return `${MONTHS[m - 1]} ${d}`;
}

/** "Aug 13 – Sep 25, 2026", collapsing a shared year. */
export function period(from: string | null, to: string | null): string {
  if (!from || !to) return "No transactions";
  const [fy] = parts(from);
  const [ty] = parts(to);
  return fy === ty
    ? `${shortDate(from)} – ${shortDate(to)}, ${ty}`
    : `${shortDate(from)}, ${fy} – ${shortDate(to)}, ${ty}`;
}

export function plural(n: number, one: string, many = `${one}s`): string {
  return `${n.toLocaleString("en-US")} ${n === 1 ? one : many}`;
}

/**
 * Locate a normalized rule needle inside a raw bank descriptor, for
 * highlighting only. Which rows match is decided by the server; this just
 * finds where to draw the mark. Normalization uppercases and turns digits into
 * spaces, so a space in the needle stands for any run of spaces or digits.
 */
export function locate(raw: string, needle: string): [number, number] | null {
  if (!needle) return null;
  const escaped = needle
    .split(" ")
    .map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
    .join("[\\s\\d]+");
  const m = new RegExp(escaped, "i").exec(raw);
  return m ? [m.index, m.index + m[0].length] : null;
}
