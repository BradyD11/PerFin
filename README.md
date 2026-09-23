# ledger-cli

A personal finance tracker in Haskell. Ingests CSV statement exports,
persists them to SQLite, and reports balances and net worth.

The design goal is narrow and specific: **a corrupted CSV row should never
silently become a wrong dollar amount in a report.** Most of the choices below
follow from that.

## Status

Milestones 1–3 are complete and tested end to end against a real 339-row
credit card export. Categorization (milestone 4) and reporting (milestone 5)
are not built yet; every transaction currently imports as `Uncategorized`.

## Quick start

```bash
cabal build all
cabal test
```

```bash
cabal run ledger -- account init --name credit-card --type credit-card --balance 0.00
cabal run ledger -- import --account credit-card data/creditcard-sample.csv
cabal run ledger -- account list
cabal run ledger -- report net-worth
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

Verified against the real file:

```
first import        339 new,   0 skipped
second import         0 new, 339 skipped
partial then full   199 new, then 140 new / 199 skipped  → 339 total
```

Row count and cent-level sum both match the source CSV exactly, with zero
duplicate ids.

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

## Not yet built

- **Checking CSV format.** `checkingSpec` is a placeholder — the real export
  has not been seen. Verify the column order and especially `csSign` against
  a real file before trusting a checking import.
- Categorization rules and the interactive review prompt (milestone 4).
- Net worth over time and spending-by-category reports (milestone 5). The
  current `report net-worth` prints only a single current figure.
