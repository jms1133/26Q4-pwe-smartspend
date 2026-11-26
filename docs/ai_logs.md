# AI Logs – Smart Spend

Factual records of AI-assisted work (Claude Code). Entries 1–9 were written in the
earlier Context / Interaction / Reflection format; new entries use the template below.
Julian's own reflections are in `ai_engineering_journal.md`.

## Template
### Entry N – <feature> (YYYY-MM-DD, branch)
- **Goal:** what Julian asked for
- **Key prompts:** Julian's most important prompts
- **AI output:** main code and architecture decisions, with file names
- **Alternatives considered:** and why they were rejected
- **Problems and corrections:** AI mistakes, and what Julian changed or rejected
- **Verification:** tests added, results, manual checks
- **Open questions:**

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

## Entry 10 – Phase 0: Infrastructure (2026-11-25)

Phase 0 runs as one sequential session. One subsection per step, each using the template fields.

### Step 1 – Configurable test port (phase0/configurable-test-port, PR #9)
- **Goal:** `server_test.dart` started the server on fixed port 8082, so parallel agents and stale test servers collided.
- **Key prompts:** Plan item in `docs/development-plan.md`: "Make the test server port configurable". The agent first proposed a `TEST_SERVER_PORT` env variable (default 8082). Julian's correction: "start the server with PORT=0, print the bound port, parse it in the test, use 127.0.0.1."
- **AI output:** `server_app/test/server_test.dart` starts the server with `PORT=0` (the OS picks a free port) and `DB_PATH=':memory:'`. It parses the bound port from the `Server running on http://host:port` startup line, connects via `http://127.0.0.1:$port`, drains stdout with `listen()`, and fails after a 30s startup timeout.
- **Alternatives considered:** A fixed port per agent via env (`TEST_SERVER_PORT`) was rejected because it needs manual coordination and still collides with stale processes. `localhost` was rejected because on macOS it can resolve to `::1` first, while the server binds IPv4 only (`anyIPv4`). Reading only `.first` from stdout was rejected because an undrained pipe can fill up and block the child process.
- **Problems and corrections:** Julian rejected the `TEST_SERVER_PORT` proposal in favor of `PORT=0` with port parsing. Julian raised the startup timeout to 30s. The timeout error message still said "15s" and was corrected to "30s".
- **Verification:** `dart analyze lib test` clean, `dart test` 24/24.
- **Open questions:** none.

### Step 2 – Docker Compose + PostgreSQL (phase0/docker-compose-postgres)
- **Goal:** Run PostgreSQL in Docker Compose as the base for the SQLite → PostgreSQL migration.
- **Key prompts:** "docker-compose.yml + PostgreSQL … bind 127.0.0.1:${DB_PORT:-5432}:5432, pg_isready healthcheck, pinned major (postgres:16), .env gitignored with committed .env.example."
- **AI output:** `docker-compose.yml` with one `db` service (`postgres:16`, named volume `db_data`, `restart: unless-stopped`, `pg_isready` healthcheck at 5s interval / 10 retries / 10s start period). `.env.example` contains `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `DB_PORT`. `.gitignore` adds `.env` and `!.env.example`. `.worktreeinclude` lists `.env` and `server_app/secrets.json` so they are copied into agent worktrees.
- **Alternatives considered:** Binding to `0.0.0.0` was rejected because it exposes the DB to the network. `postgres:latest` was rejected because major upgrades change the on-disk format. A default password was rejected: `POSTGRES_PASSWORD` uses `${VAR:?msg}`, so Compose refuses to start without it. Shelf server and SonarQube containers were left for later Phase 0 steps.
- **Problems and corrections:** In the live check, a shell variable assignment (`P=…`) failed under zsh, so the throwaway stack ran under the default project name `smart-spend` instead of a separate one. `down -v` still removed the container, network and volume.
- **Verification:** `docker compose config` without a password fails with the custom message. With `--env-file .env.example` it resolves to `host_ip: 127.0.0.1`. `docker compose up -d --wait` reached `healthy`. `psql select version()` returned PostgreSQL 16.14. `git check-ignore`: `.env` is ignored, `.env.example` is not. No containers or volumes were left over.
- **Open questions:** Server-side DB connection config (host/port/user/password from env) is part of the migration step.

### Step 3 – SQLite → PostgreSQL migration (phase0/postgres-migration)
- **Goal:** Move `server_app/lib/db/` and all handlers from `sqlite3` to PostgreSQL. The server reads its connection config from env, the schema is managed by versioned migrations, and tests get an isolated database that is safe for parallel agents.
- **Key prompts:**
  - "I believe that phase 0 is complete but check" → the agent found Steps 3–5 not started. "ok go ahead".
  - Review before commit: "Is the migration mechanism in place (schema_version table + numbered SQL files applied at startup)? If not, add it; Login depends on it. What type is amount? It should be NUMERIC(12,2) … Is find-or-create race-safe via INSERT ... ON CONFLICT ((lower(name))) DO UPDATE ... RETURNING id? Does the config read DB_HOST (default localhost)? … record database-per-test as a deliberate deviation from the agreed schema-per-run … No data import."
- **AI output:**
  - `pubspec.yaml`: `sqlite3` replaced by `postgres: ^3.7.0`.
  - New `lib/db/db_config.dart`: `DbConfig.fromEnvironment()` reads `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `DB_PORT` and the optional `DB_HOST` (default `localhost`). Process env takes precedence over the repo-root `../.env`. Defaults match `docker-compose.yml`, except the password, which throws a `StateError` if missing. `SslMode.disable`, because the package defaults to `require`.
  - New `lib/db/migrations.dart` + `server_app/migrations/001_initial_schema.sql`:
    - `loadMigrations(dir)` reads `NNN_description.sql` files sorted by version. A `.sql` file with an invalid name or a duplicate version is a `StateError`; non-SQL files are ignored.
    - `applyMigrations(db, migrations)` runs in one transaction: `pg_advisory_xact_lock`, `CREATE TABLE IF NOT EXISTS schema_version (version, name, applied_at)`, then every file whose version is not recorded yet (`QueryMode.simple`, so a file may hold several statements), plus its `schema_version` row. A failure rolls back the whole call. A version in the DB that the code doesn't know is a `StateError` (DB newer than server).
    - `001_initial_schema.sql`: `GENERATED ALWAYS AS IDENTITY` ids, `amount NUMERIC(12, 2)`, `timestamp TIMESTAMPTZ DEFAULT now()`, unique index on `lower(categories.name)` (replaces `COLLATE NOCASE UNIQUE`), seed of the 9 categories (`other` deliberately not seeded).
  - `lib/db/database.dart`: `openExpenseDatabase(DbConfig, {migrationsDir = 'migrations'})` loads the files, opens a `Pool` (max 10 connections), applies migrations and prints `Applied database migrations: …` when something was applied.
  - Handlers take a `Session` and are all `async`.
    - `findOrCreateCategory`: one statement, `INSERT … ON CONFLICT ((lower(name))) DO UPDATE SET name = categories.name RETURNING id, name, (xmax = 0) AS created`. The no-op update makes RETURNING yield the existing row; `xmax = 0` tells 201 from 200 without a second query.
    - `amount`: `_rowToExpense` parses the NUMERIC `String` into the API's `double`. Writes go through `_amountToNumeric`: `toStringAsFixed(2)` (rounds to cents, no exponent notation) sent as `Type.numeric`; non-finite or `|amount| >= 1e10` returns 400 instead of a DB overflow 500.
    - Create and update use `RETURNING`, which replaces `lastInsertRowId` plus a re-select. Update returns 404 if a concurrent delete wins.
    - Delete uses `affectedRows` instead of a pre-check.
    - The list is ordered `timestamp DESC, id DESC`.
    - Duplicate payload validation was extracted into `_parseExpenseInput`.
  - `bin/server.dart`: `DB_PATH` removed, pool opened from `DbConfig.fromEnvironment()`.
  - Tests: new `test/support/test_database.dart` (`TestDatabases.create()/drop()` via the `postgres` maintenance DB). `server_test.dart` creates `smart_spend_test_<micros>_<random>` per test and starts the server with `POSTGRES_DB` set to it; `tearDown` waits for the process to exit, then `DROP DATABASE … WITH (FORCE)`. New `test/migrations_test.dart`.
  - Docs: `.env.example` (comment + optional `DB_HOST`), `README.md`/`CLAUDE.md` database line, `documentation.md` §3.1/3.2/3.3/4/5 (decision 7)/6/7.
- **Deliberate deviation from the agreed plan:** test isolation is **database-per-test**, not the agreed **schema-per-run**. Reasons:
  - The server under test runs as a child process (`dart run bin/server.dart`) with its own pool. With schema-per-run, every pooled connection would need `search_path` set, and the server code has no hook for that without test-only code in production paths.
  - Several tests assert on a fresh state ("empty array on a fresh database", seeded category list). A schema shared by a whole run would need truncation and re-seeding between tests, which duplicates the seed outside the migration.
  - A fresh database per test also runs the real migration path on every test.
  - Cleanup is one `DROP DATABASE … WITH (FORCE)`, which also ends connections the killed server left open.
  - Random names keep parallel agents on one Compose `db` apart, which was the goal of schema-per-run.
  - Cost: about 3 s per server test (DB create + server start + migration).
- **Alternatives considered:**
  - Transaction rollback per test: rejected because the server runs in a child process with its own pool.
  - Testcontainers or a separate test container per agent: rejected because it adds complexity, and one `db` with random DB names is enough.
  - A migration library: not used. A ~100-line runner with a `schema_version` table covers the needs (forward-only, transactional DDL) without a dependency.
  - `citext` for `categories.name`: rejected because it needs an extension, while a functional unique index has the same effect.
  - Find-or-create via `DO NOTHING` + SELECT fallback (first version): replaced by `DO UPDATE … RETURNING` (one statement, always returns a row).
  - A single CTE (`INSERT … RETURNING UNION SELECT`) for find-or-create: rejected because the outer SELECT uses the statement snapshot and may not see a row that a parallel transaction just committed.
  - `DOUBLE PRECISION` for `amount` (first version): replaced by `NUMERIC(12, 2)` after review, so cents are stored exactly. The API contract stays `number`/`double`; the conversion happens only in the handler.
- **Problems and corrections:**
  - First version had no migration mechanism (`CREATE … IF NOT EXISTS` in `initializeSchema`), `DOUBLE PRECISION`, a two-statement find-or-create and host default `127.0.0.1`. All four were changed after Julian's review.
  - The `postgres` package decodes NUMERIC as `String` and its encoder rejects exponent notation, hence `toStringAsFixed(2)` before sending.
  - `127.0.0.1` vs `localhost`: Compose binds IPv4 only, and `localhost` resolves to `127.0.0.1` and `::1` on macOS. A live connection with host `localhost` to the container succeeded (the socket connect tries each address), so the default is now `localhost`.
  - The `postgres` package defaults to `SslMode.require` (seen in its source, `resolved_settings.dart`), while the stock `postgres:16` image has TLS off. `SslMode.disable` was set from the start. Not observed as a runtime failure.
  - During the smoke test, a stale dev server from an earlier run held port 8099, so the first run failed with `Address already in use`. Killed it and reran.
  - `docs/documentation.md` is not valid UTF-8 (mixed encoding), so it was edited line-by-line with `sed` and the untouched lines were diffed byte-identical. Conversion is left for a separate commit.
  - No data import: the old `server_app/smart_spend.db` (git-ignored) is not migrated. A seed script with fictional data comes later.
- **Verification:**
  - Throwaway Compose project `smartspend-verify` on port 55432.
  - `dart analyze lib test bin`: clean.
  - `dart test`: 51/51.
    - 24 existing tests.
    - 8 `db_config` unit tests.
    - 8 migration tests: sorting and non-SQL files ignored, invalid name, duplicate version, missing directory, repo directory loads; applies once and is idempotent and a later file is applied on top; a failing migration rolls back everything incl. `schema_version`; an unknown DB version throws.
    - 11 new server tests: case-insensitive category reuse on expense create, UTC timestamp, cents stored exactly (0.1 + 0.2 + 1234567890.12), rounding to cents (1.239 → 1.24), integer JSON amount, out-of-range amount → 400 on create and update (9999999999.99 accepted), seeded/sorted category list, 201 on a new category, 200 + same row on case-variant, 5 concurrent POSTs of case variants → one 201, four 200, one id, one row, 400 on blank name.
  - After the run, no `smart_spend_test_%` databases remained.
  - Manual smoke test on an empty DB: first start printed `Applied database migrations: 1`; POST with `Kinokarten für Ü-18 €`, category `Entertainment`, amount `0.1` returned `entertainment`, `0.1`, umlauts intact; `psql` showed `amount = 0.10` of type `numeric(12,2)`. Second start printed no migration line, the row was still listed, `schema_version` had one row.
  - Startup fails fast: a wrong password gives `28P01 password authentication failed`, and a missing password gives a `StateError` with setup instructions.
  - `down -v` removed the container and volume.
  - **Not verified:** the Flutter app end-to-end (create, list, edit, delete) against the PostgreSQL backend. Julian tests it manually.
- **Open questions:**
  - `dart test` now requires the `db` container, which the CI pipeline (Step 5) needs as a service container.
  - The shelf server is still not in Compose. In a container it needs `DB_HOST=db`, and the `Dockerfile` (scratch image with only `bin/server`) must also copy `server_app/migrations/`, since the runner reads them from disk relative to the working directory.

### Step 4 – SonarQube: Community Build → SonarQube Cloud (phase0/sonarqube)
- **Goal:** Static analysis and coverage for `server_app` and `flutter_application` in SonarQube, as a quality signal for the grading and for the security requirement.
- **Key prompts:**
  - "check .claude and get ready for step 4" → the agent proposed a `sonarqube` Compose service (profile `sonar`), host scanner, lcov coverage. Julian: "yes".
  - "I added the sonar token to .env, run the analysis".
  - After the agent reported that Community Build has no Dart: Julian sent the SonarQube Server Dart page ("SonarQube now includes native support for Dart and Flutter"), then decided "ok lets go public to use the cloud version. check that no secret was ever commited".
  - "Decision: SonarQube Cloud, replacing the local Community Build … do Step 4 and Step 5 together on the current branch `phase0/sonarqube` as one PR, with separate commits."
- **AI output:**
  - First version (removed again in this step): `docker-compose.yml` service `sonarqube` (`sonarqube:26.11.0.134175-community`, profile `sonar`, `127.0.0.1:${SONAR_PORT:-9000}`, healthcheck on `/api/system/status`, three named volumes); SonarScanner CLI 8.4 unpacked to `../dependencies/` (outside the repo); `SONAR_PORT`/`SONAR_TOKEN` in `.env.example`.
  - Final version: `docker-compose.yml` and `.env.example` are back to their `main` state (only `db`, no `SONAR_*`). `sonar-project.properties` at the repo root: organization `jms1133`, project key `jms1133_26Q4-pwe-smartspend`, sources `server_app/lib`, `server_app/bin`, `server_app/migrations`, `flutter_application/lib`, tests in both `test/` folders, `openapi/**`, build output, `.dart_tool` and `*.g.dart` excluded, `sonar.dart.lcov.reportPaths` for both lcov files. `.gitignore` adds `**/coverage/` and `.scannerwork/`.
  - Coverage without a new dependency: `dart test --coverage-path=coverage/lcov.info` writes lcov directly (the brief had planned the `coverage` package + `format_coverage`); frontend `flutter test --coverage`.
- **Wrong assumption in the original brief:** the brief stated "Dart is supported in Community Build". It was based on the SonarQube Community Build language overview page, which marks Dart as supported in Community Build, Cloud and Server. This was not checked against the image before writing the brief.
- **Finding: the Community Build does not analyze Dart.** Evidence:
  - Scan output: `0 languages detected in 18 preprocessed files`; only IaC, Text/Secrets and Zero Coverage sensors ran, no Dart sensor; `EXECUTION SUCCESS` despite that.
  - Container plugins (`/opt/sonarqube/lib/extensions/`): csharp, flex, go, html, iac, jacoco, java, javascript, kotlin, php, python, text, vbnet, xml. No Dart plugin.
  - Language API `/api/languages/list`: 24 languages, no `dart`. `/api/plugins/installed`: no Dart plugin.
  - Edition page (sonarsource.com downloads): Community Build lists 22 languages without Dart; "Developer Edition adds: … C, C++, Dart, GitHub Actions …".
  - SonarQube Server Dart page (the link Julian sent): "Available in: SonarQube Server 2026.5 LTA". The native support is real, but in SonarQube Server (paid) and SonarQube Cloud, not in the Community Build.
  - The language overview table contradicts the edition page; the scan and the container are the ground truth.
- **Alternatives considered:**
  - SonarQube Developer Edition image: native Dart, stays in Compose, but paid; a trial licence would expire before the end of the course.
  - Community Build + third-party `sonar-flutter` plugin (insideapp): last release 0.5.2 (2023-09-07), built against plugin API 7.9; compatibility with 26.11 unknown.
  - Community Build for non-Dart files + stricter `dart analyze` lints only: Dart code would not appear in SonarQube at all.
  - Chosen: SonarQube Cloud. The repo is public, so the Free plan has no LOC limit; analysis runs from CI (Step 5).
- **Secret audit before relying on a public repo** (the repo turned out to be public since creation, 2026-10-23):
  - Scope: all 32 commits reachable from local branches, `origin/*` and the GitHub PR heads `refs/pull/1..11/head` (fetched explicitly, because merged PR commits stay readable after branch deletion).
  - Sensitive paths ever added: only `.env.example` and `server_app/secrets.json.example` (placeholders `sk-your-key-here`, `org-optional`, `proj-optional`).
  - The real local values (`SONAR_TOKEN`, `POSTGRES_PASSWORD`, `api_token`, `organization_id`, `project_id` from `secrets.json`) were searched as fixed strings in every commit: not found. Values were never printed, only their lengths.
  - Pattern scan (OpenAI `sk-`, Sonar `sq[apu]_`, GitHub `ghp_`/`github_pat_`, AWS `AKIA`, Google `AIza`, private keys, Slack, JWT): no matches.
  - GitHub secret scanning and push protection: enabled, 0 alerts.
  - Noted: 21 of 32 commits carry Julian's work e-mail as author. Not a secret; history was not rewritten.
- **Problems and corrections:**
  - The first healthcheck used `wget`, which the SonarQube image (Ubuntu 24.04) does not contain; the container showed `unhealthy` while `/api/system/status` returned `UP`. Changed to `curl`. Moot after the removal.
  - The scan reported `EXECUTION SUCCESS` although no Dart file was analyzed; success of the scanner run is not evidence of analysis.
  - The local SonarQube container and its three volumes were removed (`docker compose rm -s -f sonarqube`, `docker volume rm …`). The local token stopped being used; Julian removed it from `.env` and set a personal SonarQube Cloud token as the repository secret `SONAR_TOKEN`.
- **Verification:**
  - Local Community Build scan (before the switch): see the evidence list above.
  - After the switch: `docker compose config --services` → `db` only (also with `--profile sonar`); `.env.example` and `.env` contain 0 `SONAR_` lines; `git check-ignore` covers `.env`, both `coverage/lcov.info` files and `.scannerwork`.
  - `dart analyze lib test bin` clean, `dart test --coverage-path=coverage/lcov.info` 51/51; `flutter analyze` clean, `flutter test --coverage` 18/18.
  - **Not verified by the agent:** the first SonarQube Cloud analysis (runs only in CI, Step 5). Julian checks the dashboard for `.dart` files with issues and coverage.
- **Open questions:**
  - Server handlers have 0 % coverage: `server_test.dart` starts the server as a subprocess, so only code loaded in the test isolate (`db_config`, `migrations`, `ai_service`) shows up in lcov. Next step: run the server tests in-process (pool created in the test, `buildRouter()` served on port 0).
  - Whether the Free plan imports Dart coverage as expected is confirmed only by the first CI run.

### Step 5 – GitHub Actions pipeline (phase0/sonarqube, same PR as Step 4)
- **Goal:** Every push and pull request runs analyze and tests for both apps against a real PostgreSQL and sends the results with coverage to SonarQube Cloud.
- **Key prompts:** "Add one GitHub Actions workflow, running on push and pull requests: a Postgres 16 service container with a healthcheck, with test credentials set in the workflow rather than from secrets; `dart analyze lib test bin`, then `dart test` with coverage; `flutter analyze`, then `flutter test` with coverage; the SonarQube Cloud scan using `SONAR_TOKEN` from repository secrets."
- **AI output:** `.github/workflows/ci.yml`, workflow-level `permissions: contents: read`, `concurrency` per ref with cancel-in-progress, `FLUTTER_VERSION: 3.47.7` (the local version, Dart 3.13.5, matching `sdk: ^3.13.5`).
  - Job `backend`: service container `postgres:16` with `pg_isready` health options, port 5432; job env `DB_HOST=localhost`, `DB_PORT=5432`, `POSTGRES_DB/USER=smart_spend`, `POSTGRES_PASSWORD=ci-test-only` (a throwaway value for a container that only lives during the job, not a secret). `subosito/flutter-action@v2` provides `dart`. Steps: `dart pub get`, `dart analyze lib test bin`, `dart test --coverage-path=coverage/lcov.info`, upload `coverage-backend`.
  - Job `frontend`: `flutter pub get`, `flutter analyze`, `flutter test --coverage`, upload `coverage-frontend`.
  - Job `sonar` (`needs: [backend, frontend]`): checkout with `fetch-depth: 0` (blame data for new-code detection), Flutter setup and `pub get` in both apps (SonarSource: dependencies must be resolved for the Dart analysis), download both lcov artifacts, rewrite the frontend `SF:lib/…` paths to absolute workspace paths (the backend lcov already has absolute paths), then `SonarSource/sonarqube-scan-action@v8` (runs on the runner as a Node action, not in Docker, so it sees the SDK and `.dart_tool/`). Organization and project key come from `sonar-project.properties`.
  - The scan steps are skipped with a notice when `SONAR_TOKEN` is empty (pull requests from forks get no secrets), so those runs still report analyze/test results.
- **Alternatives considered:**
  - `dart-lang/setup-dart` for the backend: rejected, one Flutter setup gives the same Dart SDK for both apps, so local and CI versions match.
  - Running the scan inside the `backend`/`frontend` jobs: rejected, one scan with both lcov files gives one project view.
  - Test DB credentials from secrets: rejected per brief; the service container is ephemeral.
  - Docker Compose inside CI: rejected, the service container gives the same `postgres:16` with less setup.
- **Problems and corrections:** Action versions were checked against the GitHub releases API instead of being assumed (checkout v7.0.1, sonarqube-scan-action v8.5.1, upload-artifact v7.0.2, download-artifact v8.0.2, flutter-action v2.23.0; majors pinned).
- **Verification:**
  - `actionlint` 1.7.12 (run from `/tmp`, not added to the repo): no findings.
  - The commands in the workflow are the ones run locally: 51/51 backend, 18/18 frontend, both analyzers clean.
  - **Not verified by the agent:** the actual Actions run. Julian pushes the branch and checks that all three jobs are green and the scan uploads.
- **Open questions:**
  - Branch protection (required checks) and Dependabot are not configured yet.
  - README rewrite as a separate `docs/readme` step (README is currently a copy of `CLAUDE.md`).

### Steps 4 + 5 follow-up – First SonarQube Cloud findings in `ci.yml` (phase0/sonarqube, PR #12, 2026-11-26)
- **Goal:** Fix the findings of the first SonarQube Cloud scan that Julian described as "SHA errors".
- **Key prompts:** "last session we ran the sonarQube and got SHA errors"; after the proposal: "yes all of it."
- **Finding:** The CI runs for PR #12 (push and pull_request) were green and the scan ended with `ANALYSIS SUCCESSFUL`. The "SHA errors" were 8 MAJOR issues in `.github/workflows/ci.yml` (read via `api/issues/search?pullRequest=12`):
  - `githubactions:S7637` "Use full commit SHA hash for this dependency" (lines 46, 68, 96, 122): third-party actions `subosito/flutter-action@v2` and `SonarSource/sonarqube-scan-action@v8` were referenced by mutable tags. `actions/*` were not flagged.
  - `githubactions:S8550` "Using dependencies without locking resolved versions" (lines 51, 73, 105, 106): `dart pub get` / `flutter pub get` without lockfile enforcement. `server_app/pubspec.lock` was git-ignored, so the backend had no lockfile in the repo (CI resolved `_fe_analyzer_shared` 111.0.0, the local lockfile has 109.0.0).
- **AI output:**
  - `ci.yml`: all actions pinned to full commit SHAs with the tag as a comment, SHAs resolved via `gh api repos/<repo>/commits/<tag>`: checkout `3d3c42e…` v7.0.1, upload-artifact `cf430e0…` v7.0.2, download-artifact `9000827…` v8.0.2, flutter-action `1a44944…` v2.23.0, sonarqube-scan-action `70bad23…` v8.5.1. All four `pub get` calls use `--enforce-lockfile`.
  - `server_app/.gitignore`: `pubspec.lock` entry removed; `server_app/pubspec.lock` committed.
  - `.github/dependabot.yml`: weekly updates for `github-actions` and `pub` (`/server_app`, `/flutter_application`).
  - `sonar-project.properties`: `sonar.sources`/`sonar.tests` removed (scan warning: "configured but have no effect" under the new analysis scope); `sonar.test.inclusions` for both `test/` folders; `sonar.exclusions` extended with `tools/**` (20 MB generator jar) and `*.png`, `*.jpg`, `*.ico`, `*.jar` (UTF-8 encoding warnings on icons).
- **Alternatives considered:** Pinning only the two flagged third-party actions: rejected for consistency. Pinning without Dependabot: rejected, pinned SHAs would never get updates.
- **Problems and corrections:** `.claude/current_state.md` said the branch was not pushed; it was pushed with PR #12 open. A first local `dart test` run failed with `ProcessException: dart run bin/server.dart` because the agent's shell had lost `PATH` (`server_test.dart` spawns `dart`); rerun with the SDK on `PATH` passed. Not a code issue.
- **Verification:** `actionlint` (Docker image `rhysd/actionlint`): no findings. `dart pub get --enforce-lockfile` and `flutter pub get --enforce-lockfile` succeed. `dart analyze lib test bin` and `flutter analyze` clean. `dart test` 51/51, `flutter test` 18/18. **Not verified yet:** CI run and the PR #12 issue count after the push.
- **Open questions:** Remaining documentation warnings (`docs/*.md` invalid UTF-8 at single lines) not investigated.

### Step 6 – In-process server tests (phase0/inprocess-tests, 2026-11-26)
- **Goal:** Real coverage for the server handlers in SonarQube Cloud. Before this step they had 0 %: `server_test.dart` ran `dart run bin/server.dart` as a subprocess, and coverage only measures code running in the test VM.
- **Key prompts:** "prepare for next steps"; approval with two changes: "keep exactly one subprocess smoke test that starts bin/server.dart with PORT=0 and checks that the server comes up and /expenses returns 200" and "report coverage per handler file and for lib/server.dart, before and after."
- **AI output:**
  - New `server_app/lib/server.dart`: `buildHandler(Session, AiService)` (pipeline `logRequests` → `handleCors` → router), `handleCors`, `buildRouter`, root/echo/chat handlers, moved from `bin/server.dart`. The duplicated CORS header map became one `_corsHeaders` constant; the two identical `catch` blocks in `_chatHandler` became one.
  - `server_app/bin/server.dart` keeps only `main()`: open the pool from `DbConfig.fromEnvironment()`, `buildHandler`, serve on `PORT` (default 8082).
  - `server_app/test/server_test.dart`: `setUp` creates a throwaway database, opens the pool with `openExpenseDatabase(databases.baseConfig.withDatabase(name))` and serves `buildHandler` via `shelf_io.serve` on `127.0.0.1`, port 0. `tearDown` closes the server, then the pool, then drops the database. `AiService(secretsPath: 'test/no-secrets.json')`. Test cases and assertions unchanged (22).
  - New `server_app/test/server_startup_test.dart`: the single subprocess smoke test (`PORT=0`, own database, waits for the "Server running" line, `GET /expenses` → 200 and `[]`).
- **Alternatives considered:**
  - Smoke test as a group in `server_test.dart`: rejected after writing it, because the file's top-level `setUp` would also start an in-process server and pool for that test. Moved to its own file; recorded in the Step 6 brief.
  - Calling `handler(Request(...))` directly without a socket: rejected, real HTTP keeps the middleware and routing under test the same way as before.
- **Problems and corrections:** The first baseline run in the agent's shell failed with `command not found: rm`, because `PATH` had been overwritten. Reran with system paths added. Not a code issue.
- **Verification:**
  - `dart analyze lib test bin`: no issues. `dart test --coverage-path=coverage/lcov.info`: 52/52 (51 before + smoke test), runtime 1:10 → 0:08.
  - Line coverage from `coverage/lcov.info`, before → after: `lib/handlers/expense_handlers.dart` 0 % (not loaded) → 63.6 % (75/118); `lib/handlers/category_handlers.dart` 0 % → 90.0 % (27/30); `lib/server.dart` did not exist (code in `bin/server.dart`, not loaded) → 70.7 % (29/41); `lib/db/database.dart` not loaded → 87.5 % (7/8). Unchanged: `db_config.dart` 100 %, `migrations.dart` 100 %; `ai_service.dart` 32.2 % → 34.4 %.
  - `dart run bin/server.dart`: "Server running on http://0.0.0.0:8082"; `curl /expenses` → 200; `OPTIONS /expenses` → 200 with the CORS headers.
  - After `dart test test/server_startup_test.dart` no `bin/server.dart` process is left running.
- **Open questions:**
  - Uncovered lines are mainly `classifyHandler` (`/classify`) and `_chatHandler`, which need a fake `HttpClient` for `AiService`. Out of scope for this step.
  - 48 `smart_spend_test_*` databases from runs at 10:30–10:31 (before this step) are still in the local Compose `db`. None were left by runs of the new tests. Not deleted.

---

## Entry 11 – Login system backend (2026-11-26, feature/login-backend)
- **Goal:** Users register with a username and log in; every expense and category belongs to exactly one user, and no user can read, change or delete another user's data (Step 7 brief in `docs/development-plan.md`).
- **Key prompts:** Answers to the open questions: "A: username, not email", "B: migration deletes existing expenses and categories, with a comment why", "C: I tag main as pre-login; login-ui branches from this branch", "D: rate limiting stays in this step". Additions: composite FK `(user_id, category_id)`, ON CONFLICT target equal to the index expression, seed copy in the same transaction as the user insert, bcrypt in `Isolate.run` with a dummy hash and a UTF-8 byte check, HS256 only with one test per rejected variant, CORS outside auth with `Authorization` in Allow-Headers, rate limits with reset on success, `Retry-After` and pruning. "Approved but consider one addition: ... list password spraying ... as a known limitation."
- **AI output:**
  - `api.yaml` (commit `48d7c04`): `bearerAuth` global, `security: []` on `/` and `/auth/*`, `POST /auth/register` (201 `User`, 400, 409, 429), `POST /auth/login` (200 `AuthToken`, 400, 401, 429), 401 on all protected paths.
  - `server_app/migrations/002_users.sql`: deletes existing expenses and categories; `users` with unique index `users_username_lower_key` on `lower(username)`; `categories.user_id` + `UNIQUE (user_id, id)` + unique index `(user_id, lower(name))`; `expenses.category` replaced by `category_id`, `user_id`, FK `expenses_user_category_fkey (user_id, category_id) → categories (user_id, id)`, index `(user_id, timestamp DESC, id DESC)`.
  - `server_app/lib/auth/`: `auth_config.dart` (`JWT_SECRET` ≥ 32 bytes, `BCRYPT_COST` 4–31, env or repo-root `.env`), `password_hasher.dart` (`Isolate.run` around `hashpw`/`checkpw`, dummy hash computed at startup), `token_service.dart` (header pre-check `alg == HS256`, `typ == JWT`, `exp` against injected `now`), `rate_limiter.dart` (sliding window, prune on every check), `auth_services.dart`, `auth_middleware.dart` (public: `OPTIONS`, `/`, `/auth/*`; else 401 + `WWW-Authenticate: Bearer`, user id into `request.context`), `auth_handlers.dart` (register in one `runTx` with `unnest(@names)` seed copy; 409 only for `users_username_lower_key`, other unique violations rethrown).
  - `server_app/lib/db/default_categories.dart`: the 9 seed names as a Dart constant.
  - Handlers: every expense/category query filters `user_id` from the token; expenses return the category name via `JOIN`; create/update use `WITH e AS (INSERT/UPDATE … RETURNING *) SELECT … JOIN`; find-or-create uses `ON CONFLICT (user_id, (lower(name)))`; `/classify` lists only the user's categories. `/echo` removed. Pipeline: logging → CORS → auth → router.
  - Tests: `test/support/test_server.dart` (`TestServer`, `ApiClient`, bcrypt cost 4), `auth_test.dart`, `isolation_test.dart`, `token_service_test.dart`, `rate_limiter_test.dart`, `auth_config_test.dart`; `server_test.dart` uses `alice`'s token; `server_startup_test.dart` sets `JWT_SECRET` and adds a test that the server refuses to start without it.
  - `.env.example`: empty `JWT_SECRET=` with a generation hint; `ci.yml`: test-only `JWT_SECRET` in the backend job env.
- **Alternatives considered:**
  - Email as login: rejected (no verification or reset in scope, would only store personal data).
  - `package:clock` for expiry: rejected, it works through zones that shelf_io may not pass to handlers; an injected `now` function is used instead.
  - Relying on `JWT.verify`'s own `exp` check: rejected, it uses the real clock; `checkExpiresIn: false` plus our own check against `now`.
  - Running bcrypt on the server isolate: rejected, measured 314 ms per hash at cost 12 (15 ms at cost 4), which would block all other requests.
  - PostgreSQL row-level security: out of scope; the composite FK covers the cross-user category case at DB level.
- **Problems and corrections:**
  - Dart has no `catch … when`; replaced with `rethrow` inside the catch.
  - A `RateLimiterFactory` referenced in `test_server.dart` did not exist; replaced with direct `RateLimiter(...)` construction.
  - `dart format lib test bin` (SDK 3.13, tall style) reformatted six files outside this step (`db_config.dart`, `migrations.dart`, `ai_service.dart`, `ai_service_test.dart`, `db_config_test.dart`, `test_database.dart`); reverted to keep the diff focused.
  - The `JWT_SECRET` for Julian's local `.env` was first appended to `server_app/.env` (shell cwd), so `dart run` still refused to start; moved to the repo-root `.env` and the stray file removed.
  - Leftover unused `package:http` import in `server_startup_test.dart` removed after `dart analyze` flagged it.
  - Skipped stop: Julian had asked to stop after the `api.yaml` change so he could regenerate the client first. The instruction was misread (brief item 1 "Julian regenerates `openapi/`" taken as a task for the end), and the backend was written before regeneration. Check afterwards: client regenerated into `/tmp/openapi-check`; `Expense`, `ExpenseInput` and `Category*` models byte-identical, only additions (`AuthToken`, `Credentials`, `User`, `login`, `register`). With copies of both apps pointed at it, `dart analyze lib test bin` (server) and `flutter analyze` reported no issues, `flutter test` 18/18 passed.
- **Verification:**
  - `dart analyze lib test bin`: no issues. `dart test`: 108/108 passed (52 before). After adding `test/auth_services_test.dart` (3 tests for `AuthServices.fromConfig`, bcrypt cost 4): 111/111, `auth_services` coverage 42.9 % → 100 % (7/7 lines).
  - Migration 002 dry-run in a scratch DB: legacy rows deleted, ON CONFLICT on `(user_id, (lower(name)))` returns the existing row with `created = false`.
  - Coverage (`--coverage-path`): `auth_config` 100 %, `auth_handlers` 93.7 %, `auth_middleware` 100 %, `password_hasher` 100 %, `rate_limiter` 100 %, `token_service` 100 %, `category_handlers` 90.9 %, `expense_handlers` 64.3 %, `server.dart` 72.5 %.
  - `curl` session against a throwaway DB on port 8090: register `alice` 201; login as `Alice` 200 with token and `expiresAt` +1 h; `POST /expenses` with token 201; `GET /expenses` with token 200; without token 401 with `www-authenticate: Bearer` and `access-control-allow-origin: *`; wrong password 401; `OPTIONS /expenses` without token 200 with `access-control-allow-headers: Origin, Content-Type, Authorization`.
  - `actionlint`: no findings. Staged diff scanned for the local secrets: none.
- **Open questions:**
  - The local dev DB `smart_spend` is still at schema version 1; the next server start applies 002 and deletes its expenses and categories (decision B).
  - Not verified yet: client regeneration, `flutter analyze`/`flutter test` against the new client, CI run (Julian).
  - Known limitations, documented in `documentation.md` §3.5: 409 reveals existing usernames; password spraying is not stopped by the per-(IP, username) login limit; limits are in-memory per process; no refresh token or server-side logout.
  - CORS: `Access-Control-Allow-Origin` is still `*` (`server_app/lib/server.dart:43`; asserted in `test/auth_test.dart:255` and `:262`). The development plan's security section requires CORS restricted to the web app's origin. Open for Phase 4.
