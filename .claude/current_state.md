# Current State — Claude Context & Handoff

> What a new session needs to resume: branches, current step, next steps,
> open points, last verification. Imported by `CLAUDE.md` (rule 12).
> Decisions per step: briefs in `docs/development-plan.md`. What was done and
> why: `docs/ai_logs.md` (Entries 1–12). Julian's reflections:
> `docs/ai_engineering_journal.md` (9 entries, never edited by Claude).

## Done so far

Phases 1–4 (API contract, backend CRUD, Flutter CRUD UI, AI classification),
analytics, dynamic categories, AI subcategories, KI-Kommentar: AI log
Entries 1–9. Phase 0 infrastructure (Steps 1–6: test port, Docker Compose +
PostgreSQL, SQLite → PostgreSQL, SonarQube Cloud + GitHub Actions, in-process
server tests): Entry 10. Step 7 login backend: Entry 11, merged as PR #17.
Step 8 login UI: Entry 12, done on `feature/login-ui`, PR not yet opened.

## Branches

- `main` at `dc20c59` (PR #18), protected: required checks Backend, Frontend,
  SonarQube Cloud scan; no reviews; Julian can bypass (`enforce_admins:
  false`). No open PRs.
- **`main` requires login since `c1a4488`**: every route except `OPTIONS`,
  `/` and `/auth/*` returns 401, and the app on `main` sends no token, so it
  is unusable until Step 8 merges. Demo fallback: tag `pre-login` on
  `715d9e0` (pushed); see open point 8.
- `feature/login-ui` from `dc20c59`: Step 8 complete, 8 commits, local
  only. Julian pushes and opens the PR.

## Current step

Step 8 – Login UI on `feature/login-ui`. Brief: `docs/development-plan.md`,
"Step 8 – Login UI". AI log Entry 12. Open: Done items 4 (Chrome end-to-end)
and 5 (CI + SonarQube gate) for Julian. Risk: new-code coverage on
`main.dart` is low (29 % for the whole file), see Entry 12 open questions.

## Next steps (in order, presentation on 1 December)

1. Step 8 Login UI: push, PR, Julian's checks, merge.
2. Seed script with demo data.
3. `docs/documentation.md` (German): architecture diagram, screenshots,
   Fazit, Docker/PostgreSQL setup, auth design. Then README.
4. In parallel, docs-only agent: encoding fix (open point 3) and README
   rewrite (open point 2).

Future work: `docs/development-plan.md`, "Priority order after Phase 0".

## Open points

1. Follow-up from Step 6: `/classify` and `/chat` tests with a fake
   `HttpClient`.
2. `README.md` is a copy of `CLAUDE.md`; rewrite as a project README
   (docs-only agent, don't touch it otherwise).
3. SonarQube reports invalid UTF-8 in `docs/documentation.md` (line 16) and
   `docs/ai_logs.md` (line 45).
4. Seed script: demo data for the fresh PostgreSQL DB.
5. Local dev DB: if it was still at schema 1, the next server start applies
   migration 002 and wipes its expenses/categories; register a user again
   afterwards. Julian's local `.env` has a random `JWT_SECRET`.
6. Dependabot `pub` PRs fail `flutter pub get --enforce-lockfile` in CI
   (Dependabot resolves `test_api 0.7.14`, Flutter 3.47.7 pins `0.7.12`).
   Semver-major `pub` updates are ignored until after the course; fix by
   regenerating the lockfile on the Dependabot branch with Flutter 3.47.7.
7. CORS still sends `Access-Control-Allow-Origin: *`
   (`server_app/lib/server.dart:43`, asserted in `test/auth_test.dart:255/262`);
   the plan requires the web app's origin only. Phase 4.
8. **`pre-login` fallback needs its own empty database.** The dev DB
   `smart_spend` is at schema 2 after migration 002; the `pre-login` code
   (`715d9e0`) expects schema 1, so run it against a separate empty DB
   (e.g. `POSTGRES_DB=smart_spend_prelogin`).
9. The shelf server is not in Compose (needs `DB_HOST=db` and `migrations/`
   in the image).
10. Deferred decision: category dedup is trim + case-insensitive only;
    synonyms rely on the AI prompt and user review.

## Last verification run

Step 8 (2026-11-26, `feature/login-ui`): `flutter analyze` clean,
`flutter test --coverage` 48/48, `flutter pub get --enforce-lockfile` exit 0
on the committed lock; `server_app`: `dart analyze lib test bin` clean,
`dart test` 111/111. Not run: Chrome end-to-end, CI. Details:
`docs/ai_logs.md` Entry 12, "Verification".
