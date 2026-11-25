# Current State — Claude Context & Handoff

> Single source of truth for picking up where the last session left off.
> Read this FIRST, then `.claude/CLAUDE.md`, `.claude/learning-directives.md`,
> and `.claude/project-plan.md`. Keep this file current at the end of a session.
>
> This file holds *operational* state (branches, what's done, next steps). The
> deep per-feature reflections live in `/docs/ai_engineering_journal.md`, which
> is tracked in the repo and committed alongside each feature. Don't duplicate
> reflections here — just point to the journal entry number.

## Phases Done (see journal for reflections)

- **Phase 1 — API Contract (`api.yaml`)** — `Expense`/`ExpenseInput` schemas,
  category enum, CRUD paths, `POST /classify`. Journal 1. Client regenerated
  into `/openapi` after every change (NEVER hand-edit `/openapi`).
- **Phase 2 — Backend CRUD (`server_app`)** — SQLite via `sqlite3`, shelf
  handlers + `classifyHandler`, `buildRouter()`, CORS, **port 8082**.
  `test/server_test.dart` = 11 tests (`:memory:`). Journals 2, 3.
- **Phase 3 — Flutter CRUD UI (`flutter_application`)** — `ExpenseProvider`
  (ChangeNotifier), DashboardScreen + ExpenseFormScreen, basePath
  `http://localhost:8082`. Journal 4.
- **Phase 4 — AI Classification (`gpt-6-luna`)** — `AiService` (secrets.json/env
  key precedence, defensive `parseExpenseJson`), `POST /classify`, "Parse with
  AI" field on the New Expense form. 7 ai_service tests. Journal 5. MERGED (PR #2).
- **UTF-8 outbound fix** — `callLuna` encodes body as explicit UTF-8 bytes +
  `charset=utf-8` (umlauts/€ now round-trip). MERGED (PR #3).
- **Analytics Dashboard (frontend-only)** — provider getters
  (`spendByCategory`, `spendByMonth`, `monthOverMonthChange`, etc., all with an
  injectable `now` seam), `fl_chart` pie + bar, Analytics tab. 12 new provider
  tests. Journal 6. **MERGED (PR #4).**
- **Dynamic Categories (feature #1)** — DONE on `feature/dynamic-categories`
  (committed + pushed by user). `category` moved from a fixed enum to a runtime
  `categories` table so the AI/user can add new ones. Synonym-sprawl mitigation
  = A+C: AI prompt prefers existing categories (A), new ones only materialize
  when the user saves (C, find-or-create on `POST /expenses`). Dropdown = AI
  suggestion (labeled "(new)") + existing list + "+ Add new category…" free-text.
  `other` removed from the seed + no longer offered to the model (kept only as an
  empty-response fallback). Research-only `docs/classification_log.jsonl`
  (JSONL via an `onRaw` seam) records each `/classify` call for the Ausarbeitung.
  Journal 7 written; `documentation.md` §3.3/§4/§5/§6/§8 updated. 19 backend tests
  green, 18 flutter tests green.
- **AI Subcategories (feature #2)** — DONE on `feature/dynamic-categories`.
  The data layer already carried `subcategory` end-to-end (api.yaml, generated
  client, DB column, both expense handlers, form field, dashboard subtitle), so
  only the AI path needed work and NO OpenAPI regen was required. Changes:
  (1) `/classify` prompt now asks for optional `"subcategory": string|null` — a
  finer tag under a STABLE top-level category (casino → entertainment/gambling);
  (2) `parseExpenseJson` reads it defensively (trimmed, empty/missing → null);
  (3) form `_classify` fills the existing Subcategory field from
  `parsed.subcategory ?? ''`; (4) `_logClassification` gained `parsed_subcategory`.
  Subcategory is free text (NOT a second find-or-create table) by design.
  Journal 8 written; `documentation.md` §3.3/§4/§6/§8 updated. 22 backend tests
  green (+3 subcategory parse), 18 flutter tests green.
- **KI-Kommentar (feature #3)** — DONE on `feature/dynamic-categories`. Same
  shape as subcategory; REUSES the existing `description` field (no new field,
  NO OpenAPI regen). The AI now also returns a short, funny one-sentence comment
  from a financial-advisor persona — playfully teasing wasteful buys, genuinely
  approving sensible ones. Key design point: the prompt carries BOTH positive
  AND negative few-shot examples (tequila/casino jabs + Biogemüse/Notgroschen
  approval) + "never insulting" + "same language as the user" so it doesn't roast
  everything. Changes: (1) prompt adds `"description": string`; (2)
  `parseExpenseJson` normalizes it (trim, empty/missing → null); (3) form
  `_classify` fills the field, which is relabeled "KI-Kommentar" (2 lines, chat
  icon, still free-text editable); (4) `_logClassification` gained
  `parsed_description`. Caveat: comment is generated at classify time and NOT
  regenerated if the user later edits amount/category. Journal 9 written;
  `documentation.md` §3.3/§4/§6 updated. 24 backend tests green (+2 description
  parse), 18 flutter tests green.
  **Tone follow-up (prompt-only):** first live test was funny for wasteful buys
  but only *pleasant* for good ones — because the positive few-shot examples
  were tamer than the negative ones. Fixed by rewriting the positive examples to
  be equally funny + a "praise as funny as the teasing" clause. Lesson captured
  in Journal 9 Addendum: with few-shot prompting the EXAMPLES dominate the
  instruction — change what you *show*, not just what you *say*. Still 24/24.

## Phase 0 — Infrastructure (in progress, see `docs/development-plan.md`)

Logged in `docs/ai_logs.md` Entry 10 "Phase 0: Infrastructure", one subsection
per step. Append Steps 3–5 there (marker comment at the end of the entry).

- **Step 1 — Configurable test port** — MERGED (PR #9). `server_test.dart`
  starts the server with `PORT=0` + `DB_PATH=':memory:'`, parses the bound port
  from the startup line, connects via `127.0.0.1`, drains stdout with `listen()`,
  30s startup timeout. Julian rejected the first proposal (`TEST_SERVER_PORT`).
- **Step 2 — Docker Compose + PostgreSQL** — MERGED (PR #10).
  `docker-compose.yml`: `db` service, `postgres:16`, bound to
  `127.0.0.1:${DB_PORT:-5432}`, `pg_isready` healthcheck, volume `db_data`.
  `POSTGRES_PASSWORD` is required (`${VAR:?msg}`, no default). `.env` is
  git-ignored, template `.env.example` committed. `.worktreeinclude` copies
  `.env` + `server_app/secrets.json` into agent worktrees. Live-checked:
  healthy, PostgreSQL 16.14. Also fixed the timeout message (15s → 30s).
- **Step 3 — SQLite → PostgreSQL migration of the DB layer** — NEXT.
- **Step 4 — SonarQube** in Compose — pending.
- **Step 5 — Basic GitHub Actions pipeline** — pending.

## Branch State

- `main` — everything above, including Phase 0 Steps 1–2 (PR #9, PR #10).
- `phase0/configurable-test-port`, `phase0/docker-compose-postgres` — merged;
  local + remote branches can be deleted.

## Resume Here (Phase 0, Step 3: PostgreSQL migration)

Migrate `server_app/lib/db/` from SQLite (`sqlite3`) to PostgreSQL. Open points:
- Server reads DB connection config (host/port/db/user/password) from env,
  matching the names in `.env.example`.
- Tests currently use SQLite `:memory:` for isolation; decide how tests get an
  isolated PostgreSQL DB (e.g. separate DB name per run/agent) without
  breaking parallel agents.
- SQLite specifics to port: `COLLATE NOCASE UNIQUE` on `categories.name`
  (case-insensitive find-or-create), autoincrement ids, timestamp handling.

After Phase 0: **Login system** (`docs/development-plan.md` feature 2): `users`
table, password hashing, register/login endpoints, JWT, auth middleware,
`user_id` FK on `expenses` and categories.

Optional subcategory follow-ups if revisited later: analytics drill-down by
subcategory; promote subcategory to its own managed vocabulary only if the
classification log shows the free-text approach sprawling.

**Open decision (still deferred):** category dedup is trim + case-insensitive
only. True synonyms rely on the AI prompt (A) + user review (C). Embedding-
similarity dedup remains descoped.

## Verification (last run)

- Phase 0 Step 2: `docker compose config` fails without `POSTGRES_PASSWORD`;
  `up -d --wait` → healthy; backend `dart analyze lib test` clean, `dart test`
  24/24 (after the 30s message fix).

- `flutter analyze` — clean; `flutter test` — **18/18** pass (6 provider +
  12 analytics).
- Backend `dart analyze lib test` clean; `dart test` — **24** pass (server CRUD
  + ai_service free-text/fallback/subcategory/description + category handlers).
- `/classify` verified end-to-end + logged to `docs/classification_log.jsonl`
  (needs valid `api_token` in `server_app/secrets.json`). Before/after evidence
  in the log: same 4 inputs went other/other/entertainment/food →
  loan/donation/gambling/investment after the prompt + seed fix.

## Immediate Next Steps (in order)

1. **Phase 0 Step 3** — PostgreSQL migration (see "Resume Here").
2. **Phase 0 Step 4** — SonarQube in `docker-compose.yml`.
3. **Phase 0 Step 5** — basic GitHub Actions pipeline.
4. **Login system**, then the remaining features in `docs/development-plan.md`
   order (Login UI → redesign → sync → Android).
5. **`docs/documentation.md`** (German, 30% of grade) — still has TODOs for the
   architecture diagram, screenshots and Fazit. Add the Docker/PostgreSQL setup
   once Step 3 lands. Shelf server container is not in Compose yet.

## Docs / Journal Policy

- `/docs` is tracked in the repo; commit docs alongside the feature they
  describe. `documentation.md` = Ausarbeitung, `ai_engineering_journal.md` =
  graded reflections.
- Keep `ai_engineering_journal.md` current (Context / Interaction / Reflection)
  whenever a significant feature/bug/decision lands. Currently 9 entries
  (Entry 7 = dynamic categories: enum→table, A+C synonym mitigation, the
  classification log, and the `other` seed/prompt fix; Entry 8 = AI subcategories:
  optional finer tag under a stable category, schema already provisioned;
  Entry 9 = KI-Kommentar: fun financial-advisor comment reusing `description`,
  balanced pos/neg few-shot examples so it doesn't roast everything).

## Environment / Useful Commands

Dart/Flutter SDK is NOT on PATH by default. Prepend:
```bash
export PATH="/Users/julian.morales/code/FHDW/26Q4/WebEntwicklung/dependencies/flutter/bin/cache/dart-sdk/bin:/Users/julian.morales/code/FHDW/26Q4/WebEntwicklung/dependencies/flutter/bin:$PATH"
```

```bash
# Regenerate OpenAPI client after any api.yaml change (from repo root):
java -jar tools/openapi-generator-cli-7.12.0.jar generate -g dart -i api.yaml -o openapi

# Backend (from server_app/):
dart pub get
dart test                         # server_test.dart + ai_service_test.dart
dart run bin/server.dart          # port 8082, smart_spend.db, reads secrets.json
PORT=9000 DB_PATH=':memory:' dart run bin/server.dart
# server_test.dart now uses PORT=0 (OS-assigned port), so a stale dev server on
# 8082 no longer breaks tests. It still blocks `dart run bin/server.dart`:
# lsof -tiTCP:8082 -sTCP:LISTEN | xargs kill

# PostgreSQL (from repo root; first time: cp .env.example .env, set a password):
docker compose up -d --wait
docker compose exec db psql -U smart_spend -d smart_spend
docker compose down          # add -v to also delete the db_data volume

# Frontend (from flutter_application/):
flutter pub get
flutter analyze && flutter test
flutter run -d chrome --web-port=5000
# Stale UI after a merge: flutter clean && flutter pub get, then Cmd+Shift+R.
```

## Git Lessons (for the user, learning gh/git)

- `git add .` stages only the CURRENT dir and below — from a subfolder it misses
  sibling changes. Use the repo root or `git add -A`.
- `git checkout -b <branch>` does NOT commit working changes; stage+commit after.
- `git push` alone doesn't open a PR — use `gh pr create` (or the web banner).
  `-u`/`--set-upstream` links the local branch to its remote.
- A "Merge pull request" commit sits on top of the feature commit — `main` can
  look "different" but still contains the work one commit below.
