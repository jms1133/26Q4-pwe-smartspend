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
