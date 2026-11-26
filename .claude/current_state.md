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
Step 8 login UI: Entry 12, merged as PR #19.

## Branches

- `main` at `1ebf5af` (PR #19, Step 8), protected: required checks Backend,
  Frontend, SonarQube Cloud scan; no reviews; Julian can bypass
  (`enforce_admins: false`). The app on `main` works again with login.
  Demo fallback still available: tag `pre-login` on `715d9e0`; see open
  point 8.
- `chore/state-after-login-ui` from `1ebf5af`: this state update, local.
  `feature/login-ui` merged and deleted locally (remote branch still there).
- Uncommitted: one new line in `docs/classification_log.jsonl` from Julian's
  Chrome end-to-end test; Julian decides whether to commit it.

## Current step

None in progress. Step 8 done (all 6 Done items, incl. Julian's Chrome
end-to-end check). Next: seed script.

## Next steps (in order, presentation on 1 December)

1. Seed script with demo data (users `alice`/`bob` plus expenses).
2. `docs/documentation.md` (German): architecture diagram, screenshots,
   Fazit, Docker/PostgreSQL setup, auth design. Then README.
3. In parallel, docs-only agent: encoding fix (open point 3) and README
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
9. Follow-ups from Step 8 (Entry 12, open questions): `main.dart` coverage
   29 % (no widget tests for the expense form and tiles); `_classify` handles
   401 outside `ExpenseProvider`.
10. The shelf server is not in Compose (needs `DB_HOST=db` and `migrations/`
   in the image).
11. Deferred decision: category dedup is trim + case-insensitive only;
    synonyms rely on the AI prompt and user review.

## Last verification run

Step 8 merge (2026-11-26): PR #19 merged as `1ebf5af`; all PR checks green,
SonarQube Cloud quality gate OK (new coverage 89.3 %, 0 % duplication); CI
run `45856838247` on `main` green (all three jobs). Julian: Chrome end-to-end
done. Locally before the merge: `flutter analyze` clean, `flutter test` 48/48,
`--enforce-lockfile` exit 0, `dart test` 111/111. Details: Entry 12.
