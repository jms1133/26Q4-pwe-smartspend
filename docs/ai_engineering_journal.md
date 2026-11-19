# AI Engineering Journal  Smart Spend

This journal documents significant interactions with the AI pair programmer
during development, as required by the course. Each entry follows the format:
**Context** (the problem), **Interaction** (prompts and key AI output), and
**Reflection** (what worked, what needed adjustment, how it was verified, and
what was learned).

---

## Entry 1  MoSCoW: Build CRUD Before AI

**Context**
The project brief centers on a natural-language AI feature (parsing text like
"I spent 15 euros on cinema tickets" into structured JSON via `gpt-6-luna`).
The temptation was to start with that headline feature. But the grading and
MoSCoW prioritization treat the AI classification as a *Should/Could*, while
the functioning web app (Flutter client + Dart `shelf` server + database
persistence) is the *Must*.

**Interaction**
We agreed a build order driven by MoSCoW rather than by what was most exciting:
1. Phase 1  define the `Expense`/`ExpenseInput` schema and CRUD paths in
   `api.yaml` (the single source of truth for the client/server contract).
2. Phase 2  backend: SQLite via the `sqlite3` package, `shelf` handlers for
   each CRUD route, mapping SQL rows to the generated Dart models.
3. Phase 3  frontend: `ExpenseProvider` (ChangeNotifier) + dashboard/list and
   a create/edit form wired to the generated OpenAPI client.
4. Phase 4  only now, AI classification feeding into the same `POST /expenses`
   logic from Phase 2.
The existing `/chat` endpoint and `Message` schema were deliberately left
untouched until Phase 4.

**Reflection**
Sequencing by MoSCoW meant that at every checkpoint we had something
demonstrable and testable. Building the CRUD POST path first also means the AI
feature later becomes a thin adapter (raw text � structured `ExpenseInput`)
rather than a parallel code path  it reuses the already-tested persistence
logic. Verified by completing Phases 13 with passing tests before writing a
single line of AI integration code.

---

## Entry 2  The `assert()` Validation Pitfall (Backend)

**Context**
While implementing `createExpenseHandler` and `updateExpenseHandler`, we relied
on the generated `ExpenseInput.fromJson()` to reject malformed request bodies.
Inspecting the generated code revealed that its required-key check is wrapped in
a Dart `assert()`.

**Interaction**
The generated validation looked like this (abridged):
```dart
assert(() {
  requiredKeys.forEach((key) {
    assert(json.containsKey(key), 'Required key ... is missing');
  });
  return true;
}());
```
The key realization: **`assert()` is stripped entirely in release/AOT builds.**
So in production the validation would silently vanish  the handler would either
crash with a confusing error or accept invalid input. The fix was to validate
explicitly before deserializing, in both handlers:
```dart
if (!ExpenseInput.requiredKeys.every(body.containsKey)) {
  return Response(400, body: 'Missing required fields');
}
```
This returns a proper `400` instead of leaking a `500`/`AssertionError`.

**Reflection**
This is a transferable Dart lesson: `assert()` is a *development-time* sanity
check, never a substitute for runtime input validation. Generated code can lull
you into trusting checks that disappear in production. Verified by adding handler
tests that POST incomplete bodies and asserting a `400` response  these pass in
both debug and would hold in release mode because the check is now unconditional.

---

## Entry 3  The Dual-Enum Generator Quirk (Client)

**Context**
`api.yaml` defines `Expense` as an `allOf` composition of `ExpenseInput` plus
the server-assigned `id`/`timestamp`. Both share the same `category` enum. When
building the Flutter form and provider, type errors appeared around the category
field.

**Interaction**
Inspecting the generated `/openapi` code showed the generator emits **two
separate enum classes** for what is semantically one enum:
`ExpenseInputCategoryEnum` and `ExpenseCategoryEnum`. `allOf` composition does
not merge nested enums, so each schema gets its own copy. The practical rules we
adopted:
- When **building a request** (`ExpenseInput` for create/update), use
  `ExpenseInputCategoryEnum`. The form dropdown is populated from
  `ExpenseInputCategoryEnum.values`.
- When **reading a response** (`Expense` from the server), the category is an
  `ExpenseCategoryEnum`. The list UI just displays `expense.category.value`
  (a plain string), so no conversion is needed there.
- When **editing**, we map across the two enums by matching on `.value`:
  ```dart
  ExpenseInputCategoryEnum.values.firstWhere(
    (c) => c.value == existing.category.value,
    orElse: () => ExpenseInputCategoryEnum.other,
  );
  ```

**Reflection**
This is an easy trap to get backwards, and the compiler error messages are not
obvious about *why* two "identical" enums are incompatible. Understanding that
it stems from `allOf` composition (not a bug in our spec) saved time  the
workaround is to bridge on the string `.value`, which is the stable wire
representation both sides agree on. Verified via `flutter analyze` (no type
errors) and the `ExpenseProvider` edit test, which round-trips a category change
through both enum types successfully.

---

## Entry 4 — Phase 3 Frontend: Provider State & the Flutter Bridge

**Context**
Phase 3 replaced the placeholder chat UI with the real CRUD frontend: a
dashboard that lists expenses and a form that creates/edits them, all backed by
`provider` state management and wired to the generated OpenAPI client. As a
beginner to Flutter (but comfortable with databases), the goal was to understand
*how* the pieces trigger each other, not just make them compile.

**Interaction**
Key concepts worked through, framed against database intuition:

- **`ExpenseProvider extends ChangeNotifier`** acts as an in-memory cache in
  front of the server, holding `List<Expense>` plus `isLoading`/`error` flags.
- **`notifyListeners()` is a manual trigger.** Flutter does not watch variables;
  mutating `_expenses` changes nothing on screen until `notifyListeners()` fires
  — analogous to an AFTER-write DB trigger telling subscribed widgets to rebuild.
  Every CRUD method ends with it.
- **`Future`/`async`/`await`** model pending network results without blocking the
  UI thread. `loadExpenses()` sets `isLoading = true` + notifies *before* the
  await (spinner on), and clears it in a `finally` block (spinner always off,
  even on error) — the same discipline as always closing a transaction.
- **Immutable list rebuilds** (`[..._expenses, created]`) plus
  `List.unmodifiable` getters force all writes through notifying methods and keep
  change detection reliable.
- **`Consumer` vs `context.read`:** `Consumer<ExpenseProvider>` *subscribes* and
  rebuilds on notify (used to display the list); `context.read(...)` is a
  one-shot lookup with no subscription (used in button callbacks that trigger
  actions but don't display data).
- **`StatefulWidget` lifecycle** in the form: `initState()` creates and pre-fills
  `TextEditingController`s (empty for create, existing values for edit — one form
  for both); `dispose()` releases those controllers to avoid memory leaks (like
  closing DB connections); `setState()` is the local-widget equivalent of
  `notifyListeners()`.
- **The `mounted` guard** after `await`: the user may navigate away mid-request,
  destroying the widget; `if (!mounted) return;` prevents touching a dead
  `context`.

**Reflection**
The mental model that unlocked everything was treating `notifyListeners()`/
`setState()` as explicit triggers rather than expecting automatic reactivity —
the opposite of a reactive spreadsheet, closer to firing a trigger by hand. The
`isLoading`-in-`finally` and `mounted`-after-`await` patterns are small but
prevent the two most common beginner bugs (stuck spinners, crashes on disposed
widgets). Verified with `flutter analyze` (clean) and 6 `ExpenseProvider` tests
run against a `FakeDefaultApi` subclass, so all state logic is tested with no
running server or database — the fake stands in like an in-memory stub table.

---

## Entry 5 — Phase 4 AI: Defensive Parsing & the `/classify` Adapter

**Context**
Phase 4 finally integrates `gpt-6-luna`. The design decision was *not* to let the
AI write directly to the database. Instead a new `POST /classify` endpoint takes
raw text, asks the model to return structured JSON, and returns an
`ExpenseInput` for the user to review before saving through the already-tested
`POST /expenses` path. This keeps the AI as a thin adapter (raw text →
structured input) over the Phase 2 persistence logic, exactly as planned in
Entry 1.

**Interaction**
Three sub-problems were worked through:

1. **Spec first.** A new `ClassifyInput` schema (`{ text: string }`) and the
   `/classify` path (operationId `classifyText`, returning `ExpenseInput`) were
   added to `api.yaml` — the single source of truth — then the OpenAPI generator
   was re-run so the Flutter client gained a typed `classifyText()` method.

2. **Secrets without per-session env injection.** Loading the API key via an
   environment variable meant re-exporting it every new terminal session. We
   adopted a precedence chain in `AiService.apiKey`: read a git-ignored
   `secrets.json` next to the server first, then fall back to `OPENAI_API_KEY`
   (for Docker/CI). If neither exists it *throws* at call time — an explicit
   failure beats silently sending an unauthenticated request. The key is cached
   after the first successful load.

3. **Treating model output as untrusted.** An LLM may wrap JSON in prose or code
   fences, invent categories, or return the amount as a string. The static
   `AiService.parseExpenseJson` defends against all three: it extracts the first
   `{...}` block, coerces string amounts (including `"3,50"` comma decimals),
   rejects missing/zero amounts and empty titles, and falls back to the `other`
   category for anything unknown rather than crashing.

**Reflection**
The valuable lesson is that an AI boundary is an *untrusted input boundary* — the
same mindset as validating an HTTP request body (Entry 2), just with fuzzier
input. Isolating the fragile logic into a pure static function made it directly
unit-testable without any network or key: 7 tests cover clean JSON, prose-wrapped
JSON, unknown categories, comma-decimal amounts, and each rejection path, all
passing via `dart test`. Keeping the AI feeding *into* the existing create flow
(rather than beside it) meant Phase 4 added almost no new persistence risk.

---

## Entry 6 — Analytics: Computed Views Over Cached Data (Frontend)

**Context**
With CRUD and AI in place, the app lacked the thing that makes an expense
manager actually useful: insight. The goal was a dashboard answering "where did
my money go?", "how much this month?", and "am I spending more or saving?" via
charts and a month-over-month comparison.

**Interaction**
The key architectural decision was recognizing this needed **zero backend
work**. The `ExpenseProvider` already caches the full `List<Expense>` — each with
`amount`, `category`, and `timestamp` — so analytics are *derived views* over
data already in memory, not a new data source. No `api.yaml`, server, or
`/openapi` changes; a new endpoint would have been redundant I/O.

Three sub-problems:

1. **Pure, injectable analytics.** All aggregation lives as getters/methods on
   the provider (`spendByCategory`, `spendByMonth`, `monthOverMonthChange`,
   etc.). Each time-based method takes an optional `now` parameter
   (`currentMonthTotal({DateTime? now})`). This is the single most important
   testability choice — without it, month math depends on the wall clock and
   tests become flaky. With it, tests anchor `now` to a fixed `DateTime(2026, 3,
   15)` and assert exact buckets.

2. **Representing "undefined" honestly.** `monthOverMonthChange` returns
   `double?` and yields `null` when last month had zero spend — growth from zero
   is mathematically undefined. Returning `0` or `∞` would have lied to the user;
   `null` lets the UI show a neutral "nothing to compare" state instead of a
   misleading "+∞%".

3. **Charts as a thin presentation layer.** Added `fl_chart` (pie for category
   share, bar for the 6-month trend). `spendByMonth` deliberately emits
   *continuous* zero-filled buckets so the bar chart has a gapless x-axis even in
   months with no spending — a data-shape decision made in the provider, not
   patched in the widget.

**Reflection**
The transferable lesson mirrors a database *view*: analytics are a projection of
existing rows, so they belong next to the data (the provider), computed on
demand, not persisted or re-fetched. Pushing the `now` seam into the API made 11
unit tests trivial and deterministic with a `FakeDefaultApi` — no clock mocking,
no server. Verified via `flutter analyze` (clean) and `flutter test` (18/18,
including the 12 new analytics cases). Because it is a pure read-side feature, it
added no persistence or validation risk to the existing CRUD/AI paths.

---

## Entry 7 — Dynamic Categories: From Enum to Data (and Taming the AI)

**Context**
Until now `category` was a fixed enum baked into `api.yaml`. That hard-codes the
product's vocabulary: the AI could never suggest a category we hadn't foreseen,
and adding one meant editing the spec and regenerating the client. The goal was
to make categories *data* — a runtime table the AI or user can extend — without
letting the category list sprawl into a mess of near-synonyms
("food"/"groceries"/"essen").

**Interaction**
Four distinct sub-problems were worked through:

1. **Enum → table migration.** `category` became a plain `string` in the spec;
   a `categories` table (`name COLLATE NOCASE UNIQUE`) now holds the vocabulary,
   seeded on first run. On create/update the server does a **find-or-create**
   (case-insensitive) and stores the canonical name. This directly undid the
   dual-enum bridge from Entry 3 — the generated `ExpenseInputCategoryEnum`/
   `ExpenseCategoryEnum` classes vanished, and all Flutter call sites that
   bridged on `.value` were replaced with plain `String` logic. One subtle
   Flutter trap: the generated `Category` model collides with Flutter's own
   `foundation.Category`, so the provider imports `foundation` with
   `hide Category`.

2. **Synonym-sprawl mitigation = A + C.** Rather than a heavyweight
   embedding-similarity dedup (descoped), we combined two cheap mechanisms:
   **(A)** the classify prompt is given the current category list and told to
   prefer an existing one; **(C)** new categories only materialize when the user
   *saves* (confirm-on-save via find-or-create). Dedup itself is just trim +
   `COLLATE NOCASE`.

3. **Instrumenting the AI to see what it actually does.** Before trusting the
   prompt, we added a research-only classification log
   (`docs/classification_log.jsonl`, one JSON line per `/classify` call: input,
   known categories, *raw* model response, parsed result, `was_new_category`).
   This is not a user feature and is never persisted to the app DB — it exists
   purely to study model behaviour for the Ausarbeitung. It was wired via an
   optional `onRaw` callback on `classifyExpense`, so the logging seam does not
   change the method's return type or the existing tests.

4. **The "other" escape hatch.** The log immediately exposed a problem: with
   `other` in the seed list, the model took the lazy path — "500€ an meine
   Schwester geliehen" → `other`, "200€ an die Kirche gespendet" → `other`
   (3 of 4 test inputs). `other` groups unrelated things and defeats the point
   of dynamic categories. The fix was twofold: **remove `other` from the seed
   list**, and **reword the prompt** to "invent a specific new category when
   none fits" while explicitly forbidding catch-alls (`other`/`misc`/
   `sonstiges`). `other` survives only as a last-resort *code* fallback for a
   genuinely empty model response — never seeded, never shown to the model.

**Reflection**
The standout lesson is **instrument before you tune**. The classification log
turned a vague feeling ("it picks `other` too much") into hard before/after
evidence: post-change, the same four inputs produced `loan`, `donation`,
`gambling`, `investment` — all `was_new_category: true`. Logging the *raw*
response (not just the parsed result) was what made the model's reasoning
visible. A second lesson: a seed value is also a *signal* to the model — simply
offering `other` as a legal option was enough to make it the default; removing
the option changed behaviour more than any amount of prompt wording alone would
have. The enum→data move also shows that "more flexible" and "more disciplined"
aren't opposites: freeing the vocabulary (data) while constraining *how* it
grows (prompt A + confirm-on-save C) is what keeps it usable. Verified with
`dart analyze`/`flutter analyze` clean, backend `dart test` 19/19 (the old
enum-fallback test became a free-text/"missing → other" test) and frontend
`flutter test` 18/18. An open follow-up the log also surfaced: coarse but
*correct* groupings (Casino → `entertainment`) would be better expressed as
category + subcategory (`entertainment`/`gambling`) — deferred to an AI-driven
subcategory feature.

---

## Entry 8 — AI-Driven Subcategories: Finer Grouping Without Sprawl

**Context**
Entry 7's classification log surfaced a recurring pattern: some expenses fit a
stable *top-level* category but deserve a finer grouping. A casino visit is
genuinely `entertainment`, but lumping it with cinema tickets loses information;
splitting it into its own top-level `gambling` category would fragment the
dashboard aggregation that Analytics (Entry 6) depends on. The answer is a
second axis: keep the top-level category stable for clean aggregation, and add
an optional `subcategory` for the finer tag (`entertainment` / `gambling`).

**Interaction**
The surprise here was how *little* code the feature needed — most of the
plumbing already existed:

1. **The data layer was already done.** `subcategory` was present in `api.yaml`
   (ExpenseInput), the generated client (`toJson`/`fromJson`), the SQLite
   `expenses.subcategory` column, both expense handlers, and even the form's
   Subcategory text field and the dashboard list subtitle. The schema had been
   provisioned ahead of the feature. So **no OpenAPI regeneration was needed** —
   a reminder to check what the generated model already carries before touching
   `api.yaml`.

2. **The gap was purely the AI path.** Three precise edits closed it:
   - the `/classify` prompt now asks for `"subcategory": string|null`, described
     as an *optional finer tag under a stable top-level category* (casino →
     `entertainment`/`gambling`, dog food → `food`/`pet`), with an explicit
     instruction to send `null`/omit when there is no meaningful grouping;
   - `parseExpenseJson` reads it defensively — trimmed, empty/missing normalized
     to `null` — mirroring the existing title/category discipline;
   - the form's `_classify` populates the already-present Subcategory field from
     `parsed.subcategory ?? ''` so the suggestion surfaces for review.

3. **Extended the research log, not the app.** `_logClassification` gained a
   `parsed_subcategory` field so the Ausarbeitung can show subcategory behaviour
   alongside category behaviour — consistent with the Entry 7 log, still
   research-only and non-fatal.

4. **Free text, deliberately.** Subcategory is *not* a second find-or-create
   table. Starting with free text keeps the feature small; the open question of
   whether subcategories need their own managed vocabulary is explicitly
   deferred until the data shows it's needed.

**Reflection**
Two lessons. First, **provisioning the schema ahead of the feature pays off**:
because `subcategory` was already threaded through the spec, client, DB, and UI,
the feature collapsed to a prompt change, a few parse lines, and one controller
assignment. The state file had scoped this as a larger task; reading the code
first (not the plan) revealed the real, much smaller delta. Second, the
**category-stable / subcategory-free split is the same "flexible yet disciplined"
principle from Entry 7 applied to a new axis**: the top-level category stays
aggregation-friendly and sprawl-controlled (prompt A + confirm-on-save C), while
the subcategory gives unconstrained grouping freedom where it can't hurt the
dashboards. Defensive parsing (empty → `null`) keeps the optional field from
polluting the data with blank strings. Verified: backend `dart analyze` clean,
`dart test` **22/22** (+3 subcategory parse cases); frontend `flutter analyze`
clean, `flutter test` **18/18**.

---

## Entry 9 — The "KI-Kommentar": Personality as a Product Feature

**Context**
The app so far was *correct* but joyless. The idea: have the AI add a short,
funny one-sentence comment in the voice of a financial advisor — gently teasing
a wasteful buy ("im Casino 200€ verzockt" → "Nein! Genau so hat mein Onkel
Roberto sein Auto verloren.") and genuinely approving a sensible one ("12€
Biogemüse" → "Gute Wahl! Bio ist etwas teurer, aber dein Körper wird es dir
danken."). The goal was engagement, not new data: make the tool fun enough to
actually open.

**Interaction**
Like Entry 8, the plumbing already existed — `description` was threaded through
the spec, generated client, DB, both handlers, and the form field — so the
change was again just the AI path, with **no OpenAPI regeneration**:

1. **Reuse `description`, don't invent a `comment` field.** The AI comment lives
   in the existing optional `description`. Zero schema churn; the field stays
   general-purpose (a user can still type a plain note or clear the comment).
   The UI relabels it "KI-Kommentar" and gives it two lines + a chat icon.

2. **The prompt needs BOTH poles.** The first instinct — "add a funny comment"
   — risks a model that roasts *everything*, including a sensible grocery run.
   The fix was to give explicit **positive and negative examples** (tequila /
   casino as playful jabs; Biogemüse / Notgroschen as sincere approval) plus a
   "never insulting" guardrail and a "same language as the user" rule so German
   input gets a German quip.

3. **Defensive parse + log, reused verbatim.** `parseExpenseJson` normalizes
   `description` (trim, empty/missing → null) exactly like `subcategory`; the
   research log gained `parsed_description`.

**Reflection**
The main lesson is that **a prompt rule is a distribution, not a switch**: asking
only for "funny" skews the model toward one tone. Pairing the instruction with
balanced few-shot examples (reward *and* tease) is what makes the personality
feel fair rather than mean — the same "show, don't just tell" insight as the
`other`-seed signal in Entry 7, applied to tone instead of taxonomy. The second
lesson is a product one: **reusing `description` turned a "fun idea" into a
~15-line change** because earlier phases over-provisioned the schema. Tone is a
real feature, but it stayed cheap because the data plumbing was already paid for.
Verified: backend `dart analyze` clean, `dart test` **24/24** (+2 description
cases); frontend `flutter analyze` clean, `flutter test` **18/18**. One caveat
to revisit: the comment is generated at classify time and the user can edit it,
so it is *not* regenerated if they later change the amount/category — acceptable
for a fun field, but noted.

**Addendum (tone follow-up).** A first live test confirmed the "distribution"
lesson more sharply than expected: the *instruction* already said to praise and
tease equally, yet the output was genuinely funny only for wasteful purchases
and merely *pleasant* for good ones ("40€ running shoes" → "A solid investment
in your stride"). The cause was the **examples**, not the rule: the two negative
few-shots were punchy mini-stories while the two positive ones were warm-but-
tame, so the model matched the comedic energy of each *example*, not the verbal
instruction. The fix was to rewrite the positive examples to be just as funny
("Dein Darm schreibt dir gerade eine Dankeskarte.", "Future-You just booked a
vacation on the beach of your foresight.") and add an explicit "approval should
be just as funny as the teasing, never a flat compliment" clause. Refined
lesson: with few-shot prompting the **examples dominate the instruction** — to
shift tone you must change what you *show*, not just what you *say*. Prompt-only
change; tests stayed 24/24. (Side note: the test harness spawns a real server on
fixed port 8082 and can leave a process behind if a run is interrupted, which
surfaced here as spurious `server_test` failures until 8082 was freed.)

---
