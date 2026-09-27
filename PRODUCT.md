# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Delegated. Chosen: a Servant JSON API exposed as `ledger serve` in the existing
Haskell executable, over the existing library, plus a React + TypeScript
frontend built with Vite.

Why: it mirrors the stack of the role this project targets (Haskell backend,
React/TypeScript frontend), and it keeps the Haskell domain the single source of
truth. The frontend never reimplements money arithmetic, merchant
normalization, or rule matching; it asks the API.

Undecided: where the public demo is hosted.

## Users

One primary user in two situations:

- **Owner, locally.** The person whose money this is, working through their own
  `ledger.db` after importing a month's checking and credit card statements.
  The job: turn a pile of raw bank descriptors
  (`SQ *TACO BOYS (S MILL AVETempe AZ`) into categories they trust, fast, once.
- **Hiring reviewer, via the public demo.** An engineer or recruiter evaluating
  the project as a portfolio piece (the target is a fintech backend internship).
  They click through on synthetic data and judge whether the engineering holds
  up.

## Product Purpose

ledger-cli replaces a manual spreadsheet: it ingests bank CSV exports,
categorizes transactions, and reports net worth and spending. Its reason to
exist is correctness: a corrupted CSV row should never silently become a wrong
dollar amount in a report.

The frontend's current purpose is narrow: it replaces the terminal
`ledger review` loop for categorizing uncategorized merchants. Success is
reaching zero uncategorized transactions quickly, with every decision stored as
a rule, and without a single wrong category written by accident.

## Positioning

A personal finance tool whose numbers can be checked against the bank's own:
integer-cent money, idempotent imports proven against overlapping real
exports, and reconciliation against printed statement balances. Categorization
follows the same rules: it never guesses on the user's behalf, never overwrites
a category the user chose, and remembers every answer so no merchant is asked
about twice.

## Operating Context

- A monthly routine: download statements, `ledger import` each one, then
  categorize whatever the rules did not catch.
- The first review of a new ledger is large: on real data, about 150 distinct
  uncategorized merchants covering a few hundred transactions. Later months are
  small, since most merchants already have rules.
- Merchants are grouped by their normalized form (uppercased, digits stripped),
  ordered by transaction count, so the highest-impact decisions come first.
- One decision per merchant creates a rule and applies it to every matching
  uncategorized row, including rows imported later.
- The owner is keyboard-fluent and already uses the CLI; the terminal flow
  accepts a category name, a unique prefix, or a menu number.

## Capabilities and Constraints

**In scope for the frontend now:** reviewing and categorizing uncategorized
merchants, and creating the rules those decisions produce.

**Out of scope for now (CLI only):** reports (net worth, spending), reconcile,
CSV import, and account setup. Not a rejection; not yet requested.

**Domain facts the frontend must respect:**

- Categories are a closed set: groceries, dining, monthly, travel + transit,
  transfer, income, fees, and uncategorized. `monthly` absorbed the former
  rent and subscriptions (stored rows are migrated; the old names still parse).
  `uncategorized` is the absence of a decision and is never selectable.
- Money is signed integer cents: negative is an outflow, positive an inflow,
  for every account type.
- Rules match a normalized substring. Longer needles win over shorter ones
  regardless of creation order. All-digit patterns are rejected because they
  would match everything.
- Applying rules only touches rows that are still uncategorized.
- Ambiguous input is rejected, never resolved by guessing.
- Accounts are typed asset or liability.

**Rules are editable before saving.** Review starts each rule as the full
normalized merchant; the owner can trim it (by editing or by selecting text in
a descriptor) and sees every line it would file, across all merchants, before
it is saved. Every decision is logged, and the most recent can be undone,
reverting the rule and exactly the rows it changed.

## Brand Commitments

The project name is `ledger-cli` and the command is `ledger`. No visual
identity, logo, or product name for the web frontend exists yet.

## Evidence on Hand

- Real bank exports and a checking statement exist on the owner's machine only
  (`data/`, gitignored). They must never be published, embedded in the demo,
  or used as fixtures. The demo runs on synthetic data exclusively.
- Verified engineering results, documented in `README.md`: 124 passing tests;
  imports reconcile to the cent against real exports and a real statement;
  overlapping exports dedupe identically in either import order.
- No users, testimonials, metrics, or adoption claims exist. Do not invent any.

## Product Principles

1. **Never show a number the system can't vouch for.** Unknowns are labeled as
   unknown, not smoothed over.
2. **One decision, remembered.** Every categorization becomes a rule; no
   merchant is asked about twice.
3. **Never guess for the user.** Suggestions may be offered, but nothing is
   written without an explicit choice.
4. **The Haskell domain is the source of truth.** The frontend presents and
   collects decisions; it does not recompute them.
5. **Real data stays home.** The public demo runs only on synthetic data.
