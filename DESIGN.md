---
name: ledger
description: Categorization review for ledger-cli, done on the bank statement itself.
colors:
  paper: "#ffffff"
  ink: "#16202b"
  ink-2: "#44515d"
  ink-3: "#5f6b76"
  rule: "#cfd8de"
  rule-soft: "#e6ecef"
  tint: "#e2eeef"
  tint-ink: "#b1cccf"
  tint-2: "#f1f7f7"
  annot: "#1f5f8b"
  annot-wash: "#d9e7f0"
  hl: "#ffe97a"
  hl-soft: "#fff5bf"
  bad: "#9b2b2c"
typography:
  display:
    fontFamily: "Archivo Variable, Archivo, system-ui, sans-serif"
    fontSize: "30px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.012em"
    fontVariation: "'wdth' 87.5"
  headline:
    fontFamily: "Archivo Variable, Archivo, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 700
    lineHeight: 1.25
    fontVariation: "'wdth' 87.5"
  title:
    fontFamily: "Archivo Variable, Archivo, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 700
    fontVariation: "'wdth' 87.5"
  column-head:
    fontFamily: "Archivo Variable, Archivo, system-ui, sans-serif"
    fontSize: "12.5px"
    fontWeight: 700
    fontVariation: "'wdth' 75"
  body:
    fontFamily: "Archivo Variable, Archivo, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.45
    fontVariation: "'wdth' 100"
  line:
    fontFamily: "Archivo Variable, Archivo, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
    fontFeature: "'tnum', 'lnum'"
  label:
    fontFamily: "Archivo Variable, Archivo, system-ui, sans-serif"
    fontSize: "12.5px"
    fontWeight: 400
  wordmark:
    fontFamily: "Archivo Variable, Archivo, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "0.01em"
    fontVariation: "'wdth' 125"
  stamp:
    fontFamily: "Archivo Variable, Archivo, system-ui, sans-serif"
    fontSize: "11.5px"
    fontWeight: 800
    letterSpacing: "0.14em"
    fontVariation: "'wdth' 125"
rounded:
  none: "0px"
  sm: "2px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  gutter: "40px"
  column-gap: "48px"
  margin-width: "384px"
components:
  button:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    padding: "7px 12px"
  button-hover:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  button-quiet:
    textColor: "{colors.annot}"
    rounded: "{rounded.sm}"
    padding: "4px 6px"
  button-quiet-hover:
    backgroundColor: "{colors.annot}"
    textColor: "{colors.paper}"
  category-key:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: "5px 6px"
    height: "36px"
  category-key-hover:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  category-key-active:
    backgroundColor: "{colors.annot}"
    textColor: "{colors.paper}"
  rule-input:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: "8px 10px"
  activity-summary:
    backgroundColor: "{colors.tint}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: "14px 18px 12px"
  specimen-stamp:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.stamp}"
    padding: "2px 8px"
  caught-tag:
    backgroundColor: "{colors.hl-soft}"
    textColor: "{colors.ink}"
    padding: "0 6px"
  focused-merchant:
    backgroundColor: "{colors.tint-2}"
    textColor: "{colors.ink}"
---

# Design System: ledger

## Overview

**Creative North Star: "The Annotated Statement"**

The interface is a printed bank statement that someone is working through with two pens. The paper is white stock with navy-black ink, figures sit in Additions and Subtractions columns, and the only panel is the activity summary, printed on a pale teal security tint with a guilloche. Nothing is a card, a chip board or a swipe queue. The work happens on the statement: each merchant is a run of lines, the rule being written is shown as highlighter on the descriptors it would catch, and each decision is written back onto the statement in annotation blue, with a pencil tick.

The density is high because a statement is dense. Rows are 14px type with 7px vertical padding, the right-hand margin holds the pending annotation (rule, reach, keys), and hierarchy comes from rules and type width instead of boxes and shadows. The system is light-only. Nothing is decorative unless it comes from security printing: microprint, tint, guilloche and the Specimen stamp.

The build refuses the one-card-at-a-time review queue and the dashboard of category chips. Categories are ruled rows of keys, and a decision persists as an annotation on the statement instead of a toast or a separate log.

**Key Characteristics:**
- White statement stock, navy-black ink, one security-tint panel.
- Two marks only: highlighter yellow for what a rule would catch, annotation blue for what was decided.
- One variable family (Archivo), with hierarchy set by its width axis: 75% column heads, 87.5% headings, 100% body, 125% wordmark and stamp.
- Direction is a column, not a sign: Additions and Subtractions, tabular lining figures.
- Flat paper with depth from rules: a 2px ink rule under heads and above totals, 1px rules between rows.
- Keyboard-first: number keys file, J/K move, / edits the rule, Z undoes.

## Colors

A near-monochrome statement palette of navy-black ink on white, with a pale teal tint for the summary panel and two pen colors that each mean one thing.

### Primary
- **Annotation Blue** (annot): the decision color. Filed-run ticks, the "filed as" note and arrow, the status line after a successful filing, the quiet button (Undo), the pressed state of a category key, the focus ring, the caret, the "this merchant" marker in the reach list, and `accent-color`. When a line is being filed, its merchant name turns this blue while the ticks are drawn.
- **Annotation Wash** (annot-wash): the pale blue behind general text selection, and the starting color of the fade when a filed run first lands on the statement.

### Secondary
- **Highlighter Yellow** (hl): the reach color. It marks the span of each descriptor that the current rule matches, shown as a band across the lower 46% of the text rather than a filled box. It is also the selection color inside descriptions and the rule field, because selecting descriptor text sets the rule.
- **Highlighter Wash** (hl-soft): the paler yellow behind the "Rule catches 3 of 5" tag on collapsed merchants that the current rule reaches.

### Tertiary
- **Security Tint** (tint): the teal-gray ground of the activity summary panel, always under the guilloche tile.
- **Tint Ink** (tint-ink): the microprint line across the top of the page. Decorative only, and never used for text someone has to read.
- **Tint Wash** (tint-2): the faintest tint, used behind the open (focused) merchant's rows and behind inline `code`.

### Neutral
- **Statement White** (paper): the page, input fields, keys at rest, button fills, and the phone filing sheet.
- **Navy-Black Ink** (ink): body text, figures, the 2px rules under column heads and above totals, button borders, the Specimen stamp ground, and the hover inversion of buttons and keys.
- **Secondary Ink** (ink-2): dates, account names, meta labels, filed-run descriptors, the status line at rest, and help text that blocks filing.
- **Tertiary Ink** (ink-3): line counts, ordinary help text, the shortcut legend, chevrons, the rule field's border, and disabled keys.
- **Rule** (rule): the 1px rule above the column heads, under merchant heads, the margin's left edge, section dividers in the margin, and key rows.
- **Soft Rule** (rule-soft): row dividers between statement lines, reach-list dividers, microprint underline, and skeleton bars.
- **Refusal Red** (bad): reach errors (a rule that matches nothing or everything), a failed preview, a failed request, and the "Changed outside this page" reconciliation warning.

### Named Rules
**The Two Pens Rule.** Highlighter yellow means only "this rule would catch this". Annotation blue means only "this was decided" (or has focus). Never swap them, never use either for decoration, emphasis or branding.

**The Security Tint Rule.** The teal tint and its guilloche belong to the activity summary, a reconciliation figure block. The focused-merchant wash uses the fainter tint-2 with no pattern. Never put the guilloche behind statement lines.

**The Red Is Refusal Rule.** Refusal red appears only when something cannot be filed or does not add up. It is never used for outflows; direction is shown by column.

## Typography

**Display Font:** Archivo Variable (with Archivo, system-ui, sans-serif), self-hosted, weight 100 to 900, width 62 to 125.
**Label/Mono Font:** ui-monospace (SF Mono, Menlo) for inline `code` only, such as the `ledger import` command in the empty state.

**Character:** A single grotesque that behaves like a statement's own typesetting: condensed and bold for column heads, a little narrow for headings, normal width for reading, and wide and heavy for the wordmark and stamp. Figures are always tabular and lining.

### Hierarchy
- **Display** (700, 30px, 1.1, width 87.5%, -0.012em): the page title "Uncategorized items". 25px at 860px and below, 22px on phones.
- **Headline** (700, 18px, 1.25, width 87.5%): "Transaction history" and the open merchant's name at the top of the margin (16px on phones, one line with ellipsis).
- **Title** (700, 13 to 14px, width 87.5%): margin section heads ("Reach", "File under"), the rule field label, and the summary panel heading (14px).
- **Column head** (700, 12.5px, width 75%): Date, Account, Description, Additions, Subtractions.
- **Body** (400, 16px, 1.45): the base size; the reach lead is 15.5px. Prose blocks cap at 62ch.
- **Line** (400, 14px, tabular lining figures): statement lines, merchant heads (600, 15px and 700 when open), summary rows.
- **Label** (400 to 500, 12.5 to 13.5px): meta labels, help text, line counts, the status line (13.5px, 500), the shortcut legend (12px).
- **Wordmark** (800, 15px, width 125%, 0.01em): "ledger" above the title, as a statement letterhead.
- **Stamp** (800, 11.5px, width 125%, uppercase, 0.14em): the word SPECIMEN, reversed out of ink.

### Named Rules
**The Width Axis Rule.** Hierarchy is set with the width axis and weight of one family, not with a second typeface or color. Condensed (75%) is for column heads, narrow (87.5%) for headings, normal for reading, extended (125%) for identity marks only.

**The Tabular Figures Rule.** Every count, date and amount uses tabular lining figures, right-aligned in its column. Money strings come from the server already formatted; the interface never reformats a figure.

**The Printed Case Rule.** Merchant descriptors appear in uppercase because the bank printed them that way; that is data, not styling. The only uppercase styling in the system is the Specimen stamp.

## Layout

The page is a statement sheet in two columns: the transaction history on the left (`minmax(0, 1fr)`) and the annotation margin on the right (384px), with a 48px gap and 40px side gutters. The statement header uses the same grid, so the activity summary sits directly above the margin. A microprint band (8px) runs across the very top, and a 38px status line sits between the header and the sheet.

The history is a fixed-layout table so column widths hold regardless of descriptor length: mark gutter 28px, date 72px, account 104px, description takes the rest, Additions and Subtractions 112px each. Line rows use 7px by 8px cell padding; merchant heads use 11px vertical padding. Filed runs form a band at the top of the table body, above the open queue, closed by a 2px rule. The latest four runs show, with a quiet "Show N earlier filed runs" row above them.

The margin is sticky (16px from the top, max height the viewport minus 32px, scrolling internally) with a 1px left rule and 24px left padding. Its blocks (rule field, reach, keys) are separated by 16px of space and a 1px rule with 12px above the content.

**Narrow desktop (1180px and below):** margin 330px, gutters 28px, column gap 32px, account 92px, amounts 96px.

**Phone and small tablet (860px and below):**
- Single column with 16px gutters. The table becomes stacked rows on a `18px 56px 1fr` grid; the header row, account column and both amount columns are hidden, and a signed amount (−33.60) is set on its own line under the descriptor instead.
- The margin becomes a filing sheet fixed to the bottom of the viewport (max 52% of the height) with a 2px ink top rule. It keeps only the rule field, the reach lead line and the keys; help text, reach lists and section heads are hidden. Keys grow to 44px.
- The status line becomes sticky at the top and carries the Undo button, since filed runs scroll away.
- The activity summary collapses to one reconciliation line: "55 − 12 + 0 = 43 uncategorized".
- The sheet gets 60vh of bottom padding, and merchants scroll into view with 48px top and 54vh bottom scroll margins so they clear the status bar and the sheet.

**Touch devices (hover: none):** keycaps and the shortcut legend are hidden.

## Elevation & Depth

The system is flat paper. There are no shadows on the statement, the margin, the summary panel, buttons or keys. Depth and grouping come from rules of different weights and from the two tint washes: a 2px ink rule under the column heads and across the top of the summary panel, a 1.5px ink rule above totals, a 1px ink rule over the key grid; 1px rules between merchants and in the margin; soft 1px rules between lines.

### Shadow Vocabulary
- **Filing sheet lift** (`box-shadow: 0 -10px 28px rgb(22 32 43 / 0.14)`): only on the phone filing sheet, which is fixed over scrolling statement lines and needs to read as lying on top of them.

### Named Rules
**The Printed Flat Rule.** Nothing on the statement casts a shadow. When a surface needs separating, use a rule of the right weight. The one exception is a sheet that physically overlaps scrolling content on phones.

## Shapes

Square stock. Panels, the rule field, category keys and the summary panel have square corners (0px). Small pressables get a barely softened corner (2px): buttons, keycaps and inline code. Skeleton bars use 1px. There are no pills, no circles and no rounded cards.

Marks are authored line icons on a 16px grid in `currentColor`, with 1.5 to 1.8 strokes and round caps and joins: the tick, the "filed as" arrow, the undo hook, the caution triangle and the disclosure chevron. The highlighter is a band, not a box: a flat yellow gradient covering the lower 46% of the text, with a 135° hatch of the same yellow for lines a longer rule claims instead.

## Components

### Buttons
Ink-bordered and plain, like a form's printed box.
- **Shape:** barely softened corners (2px), 1px ink border.
- **Default:** statement white with ink text, 7px by 12px, 13.5px at 600. Used for "Try again" and "Reprint the specimen".
- **Hover:** inverts to ink with white text over 120ms. **Disabled:** 50% opacity, not-allowed cursor.
- **Quiet:** no border or fill, annotation-blue text, 4px by 6px. Used for Undo (with the undo mark and a Z keycap), "Use full description" and "Show earlier filed runs". Hover fills annotation blue with white text.

### Category Keys (signature)
Ruled rows, like a department-key list, not a grid of boxes or chips.
- **Layout:** two columns with a 16px gap, under a 1px ink rule; each key is a row with a 1px bottom rule, 36px minimum height (44px on phones), 5px by 6px padding.
- **Content:** a boxed numeral keycap (22px, 1px currentColor border, 2px corners, 12px bold tabular) followed by the category label at 14px 600. The categories are Groceries, Dining, Monthly, Travel + transit, Transfer, Income and Fees, on keys 1 to 7.
- **States:** hover inverts to ink; press turns annotation blue; disabled keys go to tertiary ink. Keys stay disabled until the reach preview on screen matches the rule exactly, and the reason is shown beneath them in secondary ink.

### Rule Field
- **Style:** square, white, 1px tertiary-ink border, 15px 600 text, 8px by 10px, caret in annotation blue. Highlighter-yellow selection.
- **Focus:** 2px annotation-blue outline at 0 offset and a blue border. Escape resets to the full descriptor; Enter commits.
- **Companion:** a quiet "Use full description" button appears only when the rule differs from the full descriptor.

### Reach Block
Shows everything a rule catches before it is saved.
- **Lead:** "Files **12 lines** across **3 merchants**" at 15.5px with bold counts; ", this merchant only" in secondary ink when that is all it reaches.
- **Saved as:** shown only when the normalized needle differs from what was typed, with the needle highlighted.
- **Lists:** disclosure rows per merchant (chevron that rotates 90° over 160ms, name, bold count) opening onto small 12.5px line tables. Separate disclosures cover lines left alone because they are already categorized, and lines a longer rule claims.
- **Refusals:** caution mark plus refusal-red text, for example when a pattern is all digits or misses the open merchant.

### Statement Lines (signature)
- **Column heads:** condensed bold 12.5px, a 1px rule above and a 2px ink rule below.
- **Merchant head:** line count in tertiary ink, merchant name as a button (600; 700 at 15px when open), group total in Additions or Subtractions. Collapsed merchants the rule reaches carry a highlighter-wash tag.
- **Open merchant:** its lines are shown under a tint-2 wash, each rising 3px into place with a 14ms stagger. Date and account are in secondary ink, the descriptor carries the highlighter band, and the amount sits in its column.
- **Filing:** the merchant name turns blue and a tick is drawn beside each line (220ms, 22ms stagger), and the request waits at least 380ms so the ticks can land.

### Filed Runs (signature)
Decisions stay on the statement as annotations, in a band above the open queue.
- **Row:** a blue tick in the gutter, the line count, the merchant descriptor in secondary ink (truncated with an ellipsis before anything else wraps), then the annotation note at 13px 600 in blue: arrow, category, rule "TRIMET", and the merchant count when more than one.
- **Undo:** the latest run carries an inline quiet Undo with a Z keycap. A decision made before the page loaded appears as an "Earlier" row with the same treatment.
- **Arrival:** the band's closing 2px rule fades in from annotation wash and drops 4px over 320ms.

### Activity Summary
A bank's balance block, printed on security tint.
- **Style:** tint ground under a fixed 48 by 12px guilloche tile of two hairline (0.5px) waves, 2px ink top rule, 14px by 18px padding, square corners.
- **Content:** a reconciliation table: uncategorized at start, minus filed, plus returned by undo, equals uncategorized now (the total row sits under a 1.5px ink rule at 700). A footnote gives merchants left to file, plus a refusal-red warning if the figures do not add up.
- **Phone:** one line of arithmetic at 14px 700.

### Statement Header
- **Letterhead:** a microprint band, the extended wordmark, the display title, and a definition list of statement period and categorized count (12.5px labels in secondary ink over 15px 600 values).
- **Specimen stamp:** on synthetic data, a 1px ink box holding SPECIMEN reversed out of ink, followed by "Synthetic data. Not a real account." at 12.5px.

### Status Line
- **Rest:** 38px tall, 13.5px 500, secondary ink, reporting only.
- **After filing:** annotation blue with a tick; after an error, refusal red with a caution mark. Both settle up 3px over 260ms. Filing notices stay until the next action; other notices clear after 5 seconds.

### Empty and Loading States
- **Closing line:** when nothing is left, the statement ends with "Uncategorized ending balance / 0 lines" between a 2px ink rule and a 1px rule, at 16px 700.
- **Skeleton:** nine rows in the table's own columns, 9px soft-rule bars pulsing over 1.4s.

### Motion
All motion uses one ease-out curve (`cubic-bezier(0.16, 1, 0.3, 1)`) and short durations of 120 to 320ms. Motion always shows the paper being marked: a highlighter sweep, a tick drawn, an annotation landing, lines rising. Under reduced motion every animation and transition is removed and ticks are drawn in their finished state.

## Do's and Don'ts

### Do:
- **Do** show money in Additions and Subtractions columns with tabular lining figures, and use a signed inline amount only where the columns are hidden on phones.
- **Do** mark a rule's reach with the highlighter band (lower 46% of the text) on every line it would catch, before anything is saved.
- **Do** write decisions back onto the statement in annotation blue: tick, arrow, category and rule, with Undo on the latest.
- **Do** separate surfaces with rules: 2px ink under column heads and above totals, 1px rule between groups, soft 1px rule between lines.
- **Do** set hierarchy with Archivo's width axis and weight: 75% for column heads, 87.5% for headings, 125% only for the wordmark and stamp.
- **Do** keep every filing action on a number key and show the keycap, and hide keycaps on touch devices.
- **Do** use the security tint and its fixed 48 by 12px guilloche tile only on reconciliation panels.

### Don't:
- **Don't** review merchants one card at a time or lay categories out as a board of chips; categories are ruled key rows.
- **Don't** use highlighter yellow or annotation blue for anything other than reach and decision; neither is a brand or emphasis color.
- **Don't** color outflows red; refusal red is for errors and mismatches only.
- **Don't** add shadows to anything on the statement; the phone filing sheet is the only lifted surface.
- **Don't** round anything beyond 2px, and don't round panels, fields or keys at all.
- **Don't** add a second typeface for display or labels; monospace is only for inline command code.
- **Don't** add uppercase, letter-spaced labels above headings; the Specimen stamp is the only uppercase styling.
- **Don't** stretch the guilloche with its panel or put it behind statement lines, where it would compete with figures.
