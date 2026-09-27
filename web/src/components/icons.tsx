// Authored marks, one stroke weight. The tick is the annotation mark set
// beside a filed line, the way a reconciled statement gets ticked in pencil.

type Props = { className?: string; title?: string };

export function Tick({ className }: Props) {
  return (
    <svg className={className} viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
      <path d="M2.5 8.8 L6.2 12.2 L13.6 3.6" fill="none" stroke="currentColor"
        strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" pathLength="1" />
    </svg>
  );
}

export function UndoMark({ className }: Props) {
  return (
    <svg className={className} viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
      <path d="M5.5 3.5 L2.5 6.5 L5.5 9.5" fill="none" stroke="currentColor"
        strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M2.8 6.5 H9.5 a3.6 3.6 0 0 1 0 7.2 H6.5" fill="none" stroke="currentColor"
        strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

export function Caution({ className }: Props) {
  return (
    <svg className={className} viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
      <path d="M8 2.2 L14.2 13.4 H1.8 Z" fill="none" stroke="currentColor"
        strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M8 6.4 V9.6" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <circle cx="8" cy="11.6" r="0.95" fill="currentColor" />
    </svg>
  );
}

export function Chevron({ className }: Props) {
  return (
    <svg className={className} viewBox="0 0 16 16" width="12" height="12" aria-hidden="true">
      <path d="M6 3.5 L10.5 8 L6 12.5" fill="none" stroke="currentColor"
        strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** The annotation arrow: "filed as". Same stroke family as the tick. */
export function ArrowMark({ className }: Props) {
  return (
    <svg className={className} viewBox="0 0 16 16" width="14" height="14" aria-hidden="true">
      <path d="M2.5 8 H12.5 M9 4.5 L12.5 8 L9 11.5" fill="none" stroke="currentColor"
        strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
