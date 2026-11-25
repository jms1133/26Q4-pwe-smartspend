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

## Branch State

- `main` — everything through dynamic categories, AI subcategories and
  KI-Kommentar. Context restructuring (CLAUDE.md in repo root, docs/ai_logs.md,
  development-plan.md) committed on top.
- No open feature branches.


## Resume Here (next feature: Login)

AI subcategories is finished (see above). The agreed **next step** is the
**Login system** (see `documentation.md` §8 item 1): user table, password
hashing, auth endpoints, token/session, auth middleware, `user_id` FK on
`expenses`. It is the prerequisite for correct multi-user sync.

Optional subcategory follow-ups if revisited later: analytics drill-down by
subcategory; promote subcategory to its own managed vocabulary only if the
classification log shows the free-text approach sprawling.

**Open decision (still deferred):** category dedup is trim + case-insensitive
only. True synonyms rely on the AI prompt (A) + user review (C). Embedding-
similarity dedup remains descoped.

## Verification (last run)

- `flutter analyze` — clean; `flutter test` — **18/18** pass (6 provider +
  12 analytics).
- Backend `dart analyze lib test` clean; `dart test` — **24** pass (server CRUD
  + ai_service free-text/fallback/subcategory/description + category handlers).
- `/classify` verified end-to-end + logged to `docs/classification_log.jsonl`
  (needs valid `api_token` in `server_app/secrets.json`). Before/after evidence
  in the log: same 4 inputs went other/other/entertainment/food →
  loan/donation/gambling/investment after the prompt + seed fix.

## Immediate Next Steps (in order)

1. **Commit** the AI-subcategories + KI-Kommentar work (code + Journals 8/9 +
   documentation.md) on `feature/dynamic-subcategories`, then **open the PR**
   into `main`.
2. **Login system** — see "Resume Here" above.
3. **Remaining planned features:** Sync (via Docker deployment) → Android.
   See `documentation.md` §8 for the dependency order.
3. **Phase 5 — `docs/documentation.md`** scaffolded (German, 9 sections) with
   TODOs for architecture diagram, screenshots, and final Fazit. 30% of grade —
   extend as features land. Tracked in the repo.
4. **Deployment — Docker** (Backend & DB) not started.

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
# GOTCHA: server_test.dart spawns a REAL server on fixed port 8082 and waits on
# its first stdout line. If a prior run was interrupted, a stale process can hold
# 8082 and every test fails with "Bad state: No element" at server_test.dart:22.
# Fix: lsof -tiTCP:8082 -sTCP:LISTEN | xargs kill, then re-run.

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
