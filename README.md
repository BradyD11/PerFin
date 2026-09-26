# ledger-cli

A personal finance tracker in Haskell. Ingests CSV statement exports,
persists them to SQLite, and reports balances and net worth.

The design goal is narrow and specific: **a corrupted CSV row should never
silently become a wrong dollar amount in a report.** Most of the choices below
follow from that.

## Status

Milestones 1–5 are complete and tested end to end against two real credit
card exports (339 and 125 rows, overlapping) and a checking statement: 124
tests, clean under `-Wall`.

## Quick start

```bash
cabal build all
cabal test
```

```bash
cabal run ledger -- account init --name checking --type checking \
                                 --balance 1000.00 --as-of 2026-08-25
cabal run ledger -- account init --name credit-card --type credit-card --balance 0.00
cabal run ledger -- import --account credit-card data/creditcard-sample.csv
cabal run ledger -- reconcile --account checking --date 2026-09-24 --balance 1250.00

cabal run ledger -- rules add --contains "trader joe" --category groceries
cabal run ledger -- review          # interactively categorize the rest

cabal run ledger -- report net-worth
cabal run ledger -- report spending --month 2026-09
```

## What the types prevent

### Money is never a `Double`

```haskell
newtype Cents = Cents Integer
```

Binary floating point cannot represent `0.10` exactly. Summing a few hundred
transactions in `Double` accumulates error, and a financial report that is off
by a cent is a report nobody trusts. `Cents` stores an integral number of
cents, and `centsFromDecimal` parses the digit string directly rather than
routing through `Double`:

```haskell
centsFromDecimal "-12.62"    == Right (Cents (-1262))
centsFromDecimal "$1,234.56" == Right (Cents 123456)
centsFromDecimal "1.234"     == Left "too many decimal places: 1.234"
```

The last case matters. A parser that accepted three decimals by truncating
would turn a malformed row into a plausible-looking wrong number — the exact
failure mode this project is built to rule out. `Integer` rather than `Int`
so summing a lifetime of history cannot overflow.

### Invalid transactions cannot be constructed

`Transaction`, `AccountName`, and `Merchant` do not export their constructors.
The only way to build one is through `Domain.Validation`, which returns
`Either ValidationError`:

```haskell
mkTransaction :: Day -> TransactionId -> AccountName -> Day -> Cents
              -> Text -> Category -> Either ValidationError Transaction
```

It rejects future-dated rows (which catch a swapped `MM/DD` or a mis-parsed
year), zero amounts (no posted transaction moves $0 — in practice that is a
parse failure that produced a `0`), and merchants that are empty once trimmed.

`today` is a parameter rather than a read of the system clock, which keeps
validation pure and therefore property-testable.

### Sign convention is established once, at the boundary

Every amount in the system means **value flow**: negative is money leaving
your control, positive is money arriving. `Import.CSV` is the only place that
converts an institution's convention into this one, via `SignConvention`.

This is load-bearing, and it is where the tempting mistake lives. The instinct
is to negate amounts for liability accounts. That is wrong under a value-flow
convention, and the tests pin it down:

| Event | Card row | Checking row | Correct Δ net worth |
|---|---|---|---|
| $12.62 purchase | `-1262` | — | `-1262` |
| $575 card payment | `+57500` | `-57500` | `0` |

Negating liabilities would report the purchase as making you $12.62 *richer*,
and the payment as a $1,150 loss. So `netWorthDelta` is the identity on the
amount, and `AccountType` deliberately does not enter into it — it earns its
keep by keeping asset and liability *balances* distinct, so a carried card
balance is never mistaken for savings.

## Idempotent imports

Re-importing the same statement must not double-count. That requires a stable
identity derived from the row's content:

```haskell
sha256(account ␟ date ␟ amount ␟ normalized-merchant-prefix ␟ occurrence)
```

**Merchant normalization** uppercases, collapses whitespace, and strips
digits, then truncates to 20 characters. Banks append volatile reference
numbers that change between exports of the same transaction:

```
KLM AIRLINE 0742143148993800-6180104 DC
```

Keying on the raw string would make a re-import look like new spending.

**The occurrence index** is not a refinement — it is required, and the real
data proves it. In the 339-row sample export, **67 rows collide** on
(date, amount, merchant):

```
4x  08/07/2026  -3.00  MTA*NYCT PAYGO NEW YORK NY
2x  08/06/2026  -3.25  PATH TAPP PAYGO CP JERSEY CITY NJ
```

These are genuinely distinct transit fares. Without an occurrence index the
importer would silently discard 20% of the file and under-report spending.
The index is assigned by a deterministic sort over row content, so the same
statement always produces the same ids.

Verified against two real exports that overlap by three days (June 17-20),
including a duplicated PATH fare inside the overlap window:

```
same file twice       339 new, then   0 new / 339 skipped
partial then full     199 new, then 140 new / 199 skipped  → 339 total

later then earlier    339 new, then 115 new /  10 skipped  → 454 total
earlier then later    125 new, then 329 new /  10 skipped  → 454 total
```

Import order does not affect the result: both sequences converge on the same
454 rows and the same cent-level sum, with zero duplicate ids. Row counts and
sums match a multiset union of the two source files exactly.

### Known limitation

If a bank *removes* a row from a later export (a reversed pending charge),
occurrence indices shift and the tail rows of that collision group look new.
Statements are append-only in practice, so this is accepted rather than
solved.

## Layout

```
app/Main.hs              CLI (optparse-applicative)
src/Domain/Types.hs      Cents, TransactionId, AccountType, Category, Transaction
src/Domain/Validation.hs smart constructors, ValidationError
src/Import/CSV.hs        ColumnSpec-driven parsing, sign normalization
src/Import/Dedup.hs      content-derived ids, occurrence indexing
src/Persistence/DB.hs    SQLite schema, migrations, idempotent import
test/                    70 tests (QuickCheck properties + HUnit cases)
```

Adding another institution means adding a `ColumnSpec`, not another parser.

## Error handling

A malformed row is reported with its line number and skipped; the rest of the
file still imports. One bad line in a 339-row statement should not reject the
other 338.

```
skipped 2 malformed row(s):
  line 2: malformed date: nonsense
  line 3: malformed amount: abc
imported 339 new, skipped 0 already present
```

Imports run inside a single SQLite transaction, so a crash mid-import leaves
the database untouched rather than half-written.

## Balances and reconciliation

A balance is only meaningful with a date. `account init --balance B --as-of D`
records that the account held `B` at the end of day `D` — a number read
straight off a statement. Every other balance is derived from that one point:

```
balance(d) = B + sum(tx on or before d) - sum(tx on or before D)
```

The same formula works in both directions. That matters the moment older
history is imported: an undated opening balance already reflects July, so
adding July's rows on top would count them twice. With a dated anchor, rows
before `D` are subtracted back out, and a property test checks that importing
them never moves any balance after the anchor.

`ledger reconcile` compares the ledger to a balance the bank printed:

```
$ ledger reconcile --account checking --date 2026-09-24 --balance 1250.00
checking at end of 2026-09-24
  statement       1250.00
  ledger          1250.00
  reconciled
```

This is where "a corrupted row never silently becomes a wrong number" is
enforced against the bank's own figures instead of only asserted. The same
statement imported with its signs inverted — what a wrong `SignConvention`
would do — is caught:

```
  statement       1250.00
  ledger           750.00
  difference      -500.00
  MISMATCH: a row is missing, doubled, or signed wrong
```

and exits non-zero, so it can gate a script. A dropped or doubled row fails
the same way.

## Categorization

Rules are keyword matches against the same normalized merchant form the dedup
key uses, so a rule written as `trader joe` matches `TRADER JOE'S #123 TEMPE
AZ` without the user thinking about case, spacing, or store numbers.

**Longer needles win.** A specific rule (`TACO BOYS`) beats a general one
(`TACO`) regardless of which was added first, so rule order never has to be
managed by hand. Ties break on the needle text, keeping the result
deterministic.

`mkRule` rejects an all-digit pattern. Normalization strips digits, so `12345`
would normalize to the empty string — and every string contains the empty
string, so such a rule would silently categorize the entire ledger.

Unmatched merchants go to `ledger review`, which asks once per merchant
(highest transaction count first) and persists each answer as a rule, so the
same merchant is never asked about twice. The prompt accepts a name, a unique
prefix, or the menu number; **ambiguous prefixes are rejected rather than
guessed**, since silently picking `groceries` when the user typed `s` and meant
`subscriptions` would write a wrong rule that mis-categorizes every future
import.

A category set by hand is never overwritten by a later rule — `applyRules`
only touches rows that are still `Uncategorized`.

## Reports

```
$ ledger report net-worth
month          net worth        change
2026-06           264.84          0.00
2026-07          -187.14       -451.98
2026-08           691.26       +878.40
2026-09           375.82       -315.44

change over window: 110.98
```

The first month's change is `0.00`, not its full value: there is no previous
month to have moved from, and seeding with zero would report the entire
opening position as a first-month gain. `seriesChange` is correspondingly
`last - first` rather than a sum of deltas, and a property test pins the two
definitions to each other.

`report spending` breaks a month down by category and compares it to the
previous month. The comparison uses the **union** of both months' categories,
not the intersection — a category you spent on last month and not at all this
month is exactly the change worth seeing.

## Not yet built

- **Checking CSV format.** Only a PDF statement has been seen. `checkingSpec`
  assumes the same download format as the credit card export (same bank);
  run `reconcile` after the first real checking import to confirm it.
- **Untracked accounts.** Money moved to an account the ledger does not know
  about (a brokerage, say) reads as a loss in net worth. Tracking it means
  adding that account and importing its activity.
- **Coverage gaps.** A month before an account's first imported transaction
  assumes that account's balance was unchanged. `report net-worth` prints a
  note when this applies rather than presenting the number as known.
- Rules created by `review` use the full merchant string. A shorter, more
  reusable needle has to be added by hand with `rules add`.
