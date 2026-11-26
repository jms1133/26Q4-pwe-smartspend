# Development Plan – Smart Spend

Expense tracker for the module "Projekt Web-Entwicklung": Flutter client (web, later Android), Dart `shelf` backend, `api.yaml` as the OpenAPI contract, and AI classification with gpt-6-luna.

**Already done:** CRUD backend with SQLite, Flutter CRUD UI with Provider, `/classify` AI endpoint, UTF-8 fix, Analytics dashboard (pie and bar charts), dynamic categories, AI subcategories, KI-Kommentar. See `.claude/current_state.md` and `docs/ai_logs.md` (entries 1–9).

## Goals

- Private user accounts: each user sees only their own expenses.
- Same data on web and Android, synced through the server.
- New web interface with its own identity and personality.
- Verifiable software security (professor's requirement).
- Containerized backend and database (Docker).

## Architecture

- **Clients:** Flutter Web and Flutter Android. Both use the generated OpenAPI client from `/openapi` and talk only to the shelf server, never to the database directly.
- **Backend:** Existing Dart `shelf` / `shelf_router` server. Login, tokens and per-user data are implemented here.
- **Database:** Migrate from SQLite to PostgreSQL, running in Docker. The server is the only component with database credentials.
- **Mobile offline cache:** Small local SQLite database on Android (`sqflite` or `drift`) that syncs with the server when online.
- **Containers:** Docker Compose with PostgreSQL and the shelf server. Flutter itself is not containerized. Code analysis runs in SonarQube Cloud from CI, not in Compose.
- **Contract first:** Every API change goes into `api.yaml` first, then the client is regenerated. `/openapi` is never edited by hand.

## Features (in dependency order)

1. **Infrastructure:** Docker Compose, PostgreSQL migration, configurable ports.
2. **Login system:** `users` table, password hashing, register/login endpoints, JWT tokens, auth middleware, `user_id` foreign key on `expenses` and categories.
3. **Login UI:** Login and register screens, token handling in the client, logout.
4. **Web interface redesign:** visual identity, theme, layout.
5. **Configurable server URL:** replace the hardcoded `http://localhost:8082` via `--dart-define`, so Android can reach the server.
6. **Android build:** run the app on emulator and real device.
7. **Sync and offline mode:** Android saves locally first and syncs with the server when online; web reads directly from the server.
8. **Budgets with alerts:** monthly budget per category, warning at 80 %.
9. **Export:** CSV and PDF of the user's expenses.
10. **Optional:** analytics drill-down by subcategory.

## Could-have: "Grumpy Uncle" personality

The app gets a consistent character: a grumpy uncle who is an accountant by profession. He gives genuinely useful tips, but with a grumpy touch, and he grudgingly approves of good decisions.

- **One persona everywhere:** the persona lives in a single prompt constant in `ai_service.dart`, so the KI-Kommentar and any future AI texts (tips, budget warnings) share the same voice. Keep the existing rule: grumpy, never insulting, same language as the user.
- **Financial mood score:** a score from 0 to 100 based on good practices, for example staying within budgets, progress toward a savings target, and month-over-month change. Implemented as a Provider getter with an injectable `now`, like the analytics getters, so it is easy to unit test.
- **Adaptive look:** the app's color shifts from red to green with the score (for example `ColorScheme.fromSeed` with an interpolated seed color and an animated theme transition).
- **Uncle as a Tamagotchi-like companion:** an original animated character (own design, without the Tamagotchi name or look) that reacts to the mood score, from proud and cheerful at green to dramatically despairing at red. A mood label and a speech bubble with the latest KI-Kommentar always accompany it, so the state is not communicated by color alone (accessibility). Care mechanics: logging expenses regularly "feeds" him; streaks and staying within budget earn XP and level-ups; neglect makes him sleepy and dusty rather than punishing the user. The score-to-state mapping is a pure function, easy to unit test. Animation via a Rive state machine with the score as input, or Lottie / simple image assets as a fallback.
- **Savings target:** new setting per user, stored on the server (requires an `api.yaml` change).
- **Dependencies:** web redesign (Phase 1), login (per-user targets) and budgets (Phase 3).

## Future idea (out of scope for the course): Premium personalities

- A premium version offers more personalities to choose from, including a more aggressive one with dark humour.
- **Prepare it cheaply now:** build the Grumpy Uncle as one entry in a persona list (for example a `Persona` enum or map of prompt texts) instead of hardcoding it, so adding personalities later is just new data.
- **Guardrails for edgier personas:** explicit opt-in, clear labeling, and hard limits in the prompt (no jokes about protected traits, health, or real financial distress).

## Security

**Authentication**

- Passwords hashed with bcrypt or Argon2, never stored in plain text.
- Short-lived JWT tokens (for example `dart_jsonwebtoken`); signing secret in an environment variable.
- shelf auth middleware checks the token before every protected handler.
- Rate limiting on the login endpoint against brute force.

**Data isolation**

- Every query filters by `user_id`, taken from the verified token, never from the request body or URL.
- Requests for another user's expense return 404, not 403.
- Optional second layer: Row Level Security in PostgreSQL.

**Input and data**

- Parameterized SQL queries only.
- Input validation in the handlers (positive amounts, length limits), with the same constraints documented in `api.yaml`.
- Length limit on text sent to `/classify`; AI output stays defensively parsed by `parseExpenseJson`.

**Transport and configuration**

- HTTPS in deployment; Android blocks plain HTTP by default, allow it only for local development.
- CORS restricted to the web app's origin.
- Secrets (`secrets.json`, JWT secret, DB password) never in Git; passed to Docker via environment variables.

**Client**

- Android: token in `flutter_secure_storage`.
- Web: short-lived token in browser storage; document the trade-off.

**Verification**

- SonarQube Cloud (Dart is not in the free Community Build, see Step 4) plus `dart analyze` / `flutter analyze` with strict lints.
- Dependabot for vulnerable or outdated packages.
- Isolation tests: user A cannot read, edit or delete user B's expenses.

## Quality and CI

- Tests for every new handler and Provider before a feature counts as done.
- GitHub Actions on every push: `dart analyze`, `dart test`, `flutter analyze`, `flutter test`, SonarQube.
- Claude records a factual AI log entry per feature in `docs/ai_logs.md`; Julian writes `docs/ai_engineering_journal.md` himself. `documentation.md` update committed with each feature.

## Step brief template

Every step gets a brief in this format, filled in under its phase below
once the plan is approved.

```
**Step N – <name>** · branch `<phase>/<name>` from `main`
Goal: …
Agreed decisions: 1. … 2. …
Out of scope: …
Done:
1. `dart analyze lib test` clean, `dart test` all green (show output)
2. …
3. (Julian) end-to-end check in the Flutter app
4. AI log entry appended; docs updated
```

## Work order and agents

Parallel Claude Code sessions, each in its own git worktree and branch (`claude --worktree <name>`).

**Phase 0 – one session, sequential (comes before all other phases):**

- Docker Compose with PostgreSQL.
- Migrate the DB layer from SQLite to PostgreSQL.
- Make the test server port configurable (`server_test.dart` currently uses fixed port 8082, which would collide between agents).
- Basic GitHub Actions pipeline.

**Steps 4 + 5 – SonarQube Cloud and GitHub Actions** · branch `phase0/sonarqube` from `main`, one PR with separate commits (combined because the presentation is on 1 December)
Goal: every push and pull request runs analyze and tests for both apps and a SonarQube Cloud scan that shows Dart issues and coverage.
Agreed decisions:
1. SonarQube Cloud replaces the local Community Build. Revised: the first version added a `sonarqube:26.11.0.134175-community` service to Compose, but Dart analysis is not part of the Community Build (only Developer Edition and up, and SonarQube Cloud). The `sonarqube` service and its volumes are removed again; Compose runs only `db`. Repo is public, so the Cloud Free plan has no LOC limit. Organization `jms1133`, project key `jms1133_26Q4-pwe-smartspend`, Automatic Analysis off (CI-based analysis, required for coverage import).
2. (dropped) Embedded H2 database for local SonarQube; no local SonarQube any more.
3. (dropped) Local port, healthcheck and volumes; no local SonarQube any more.
4. Revised: the scanner runs only in CI via `SonarSource/sonarqube-scan-action` (runs on the runner, so it sees the Dart SDK and `.dart_tool/`). No local scanner runs; `SONAR_TOKEN` is a GitHub Actions repository secret only and is not in `.env` or `.env.example`.
5. One `sonar-project.properties` at the repo root for both apps: `sonar.organization`, project key; sources `server_app/lib`, `server_app/bin`, `server_app/migrations`, `flutter_application/lib`; tests in both `test/` folders; `openapi/**`, build output and `*.g.dart` excluded.
6. Revised: coverage via lcov without a new dependency: backend `dart test --coverage-path=coverage/lcov.info`, frontend `flutter test --coverage`; both paths in `sonar.dart.lcov.reportPaths`. `**/coverage/` and `.scannerwork/` are git-ignored.
7. Revised: no local token. The token is a personal SonarQube Cloud token stored as the repository secret `SONAR_TOKEN`.
8. Workflow `.github/workflows/ci.yml` on `push` and `pull_request`. Jobs: `backend` (Postgres 16 service container with `pg_isready` healthcheck, test credentials set in the workflow, not from secrets; `dart analyze lib test bin`, `dart test` with coverage), `frontend` (`flutter analyze`, `flutter test --coverage`), `sonar` (needs both, downloads their lcov artifacts, runs the scan with `SONAR_TOKEN`). Flutter version pinned to the local one (3.47.7), which also provides the Dart SDK for the backend.
9. The scan is skipped when `SONAR_TOKEN` is unavailable (pull requests from forks get no secrets), so those runs still show analyze/test results.
10. Follow-up after the first scan (8 MAJOR issues in `ci.yml`, rules `githubactions:S7637` and `githubactions:S8550`): every action is pinned to a full commit SHA with the release tag as a comment (`checkout` v7.0.1, `upload-artifact` v7.0.2, `download-artifact` v8.0.2, `flutter-action` v2.23.0, `sonarqube-scan-action` v8.5.1).
11. `server_app/pubspec.lock` is committed (removed from `server_app/.gitignore`); both apps are applications, so their lockfiles belong in Git. All `pub get` calls in CI use `--enforce-lockfile`.
12. Dependabot (`.github/dependabot.yml`), weekly: `github-actions` (keeps the pinned SHAs current) and `pub` for `server_app` and `flutter_application`.
13. `sonar-project.properties`: `sonar.sources`/`sonar.tests` removed (no effect under SonarQube Cloud's new analysis scope); scope controlled via `sonar.exclusions` (also `tools/**` and binary images) and `sonar.test.inclusions`.
Out of scope: fixing findings outside `ci.yml` (Phase 4), stricter lint sets, shelf server in Compose, branch protection.
Open points (next steps): server handlers show 0 % coverage because `server_test.dart` runs the server as a subprocess; next step moves the server tests in-process (pool created in the test, `buildRouter()` served on port 0). README rewrite as a separate `docs/readme` step.
Done:
1. `dart analyze` and `flutter analyze` clean locally, `dart test` and `flutter test` green locally (show output).
2. Compose starts only `db`; `.env.example` has no `SONAR_*` entries.
3. Workflow file valid; each job and step explained.
4. (Julian) branch pushed: the Actions run is green, including the scan step.
5. (Julian) SonarQube Cloud dashboard shows `.dart` files with issues and coverage.
6. Brief, AI log (Entry 10, Steps 4 and 5) and `current_state.md` updated.
7. `actionlint` clean; `dart pub get --enforce-lockfile` and `flutter pub get --enforce-lockfile` succeed locally.
8. SonarQube Cloud PR #12 shows 0 issues for S7637/S8550 (checked via the issues API).

**Step 6 – In-process server tests** · branch `phase0/inprocess-tests` from `main`
Goal: the server handlers show real coverage in SonarQube Cloud. Coverage only measures code running in the test process, and `server_test.dart` currently runs the server as a subprocess.
Agreed decisions:
1. `buildRouter`, `handleCors` and the root/echo/chat handlers move from `bin/server.dart` to `lib/server.dart`, which exposes `Handler buildHandler(Session db, AiService aiService)` (router + logging + CORS pipeline). `bin/server.dart` keeps only `main()`: read env, open the pool, serve.
2. One throwaway database per test via `TestDatabases`: `setUp` creates it, opens the pool with `openExpenseDatabase(baseConfig.withDatabase(name))` and serves `buildHandler(...)` with `shelf_io.serve` on `InternetAddress.loopbackIPv4`, port 0. `tearDown` closes the server, then the pool, then drops the database.
3. Exactly one subprocess smoke test stays: it starts `bin/server.dart` with `PORT=0` and its own database and checks that the server comes up and `GET /expenses` returns 200 (env config + migrations at startup). The rest of the process plumbing is removed from the CRUD tests.
4. The tests stay real HTTP tests through `package:http`, so routing and the CORS middleware are exercised end to end.
5. The in-process `AiService` points at a non-existent secrets path, so no test can reach the real model.
6. No existing test case or assertion changes; the 22 server tests stay, the smoke test is added on top.
Out of scope: new `/classify` and `/chat` tests with a fake `HttpClient`, README, encoding fix, seed script.
Done:
1. `dart analyze lib test bin` clean, `dart test` all green (show output).
2. `dart run bin/server.dart` still starts on 8082; `curl /expenses` returns 200.
3. Line coverage per handler file and for `lib/server.dart` from `coverage/lcov.info`, before and after.
4. (Julian) CI on the PR is green; SonarQube Cloud shows handler coverage above 0 %.
5. Brief in this plan; AI log subsection in `docs/ai_logs.md` Entry 10.

**Priority order after Phase 0 (agreed 2026-11-26, presentation on 1 December):**

1. Login system backend (feature 2). Core Must-have, comes first to keep a buffer.
2. Login UI (feature 3).
3. Seed script with demo data for the presentation.
4. Documentation (`docs/documentation.md`) and README.

In parallel, as a separate docs-only agent: the encoding fix (invalid UTF-8 reported by SonarQube in `docs/documentation.md` and `docs/ai_logs.md`) and the README rewrite.

Future work, after the items above and only if time allows: web interface redesign, configurable server URL and Android build, sync and offline mode, budgets with alerts, CSV/PDF export, Grumpy Uncle personality, shelf server container in Docker Compose.

The phase plan below describes the original parallel split; where it conflicts with this order, this order wins.

**Phase 1 – parallel:**

- Agent A: web interface redesign (Flutter only).
- Agent B: login system backend (`api.yaml`, users table, hashing, JWT, middleware, `user_id`, isolation tests).

**Phase 2 – parallel, after Phase 1 is merged:**

- Agent C: login UI and token handling in the client.
- Agent D: CSV/PDF export (Flutter only).

**Phase 3 – parallel:**

- Agent E: configurable server URL, Android build, offline cache and sync.
- Agent F: budgets with alerts.

**Phase 4:** security hardening, SonarQube findings, final documentation and presentation prep.

**Phase 5 – Could-have, only if time allows (parallel):**

- Agent G: Grumpy Uncle persona in the AI prompt; savings target, streak and XP fields (`api.yaml` + backend).
- Agent H: mood score getter, red-to-green theme, companion character with its states, streak and XP display (Flutter only, after G's `api.yaml` change is merged).

**Agent rules**

- Each agent uses its own server port (`PORT=...`), Flutter port (`--web-port`) and database (separate DB name or `:memory:` in tests).
- Only one agent at a time changes `api.yaml`; merge it and regenerate `/openapi` before the next one builds on it.
- Avoid editing the same files in parallel; merge branches at the end of each phase. Agents do not edit `.claude/current_state.md`, `docs/ai_logs.md` or the journal; they put their log entry in their final summary, and the main session appends it after merging.
- Ignored files the agents need (`server_app/secrets.json`, `.env`) are copied into each worktree via `.worktreeinclude`.

## Context management

- `CLAUDE.md` (repo root) is short: project, stack, real folder names, rules and commands. It imports `.claude/current_state.md` so the state loads automatically.
- `.claude/current_state.md` holds operational state only: finished features with AI log numbers, branch state, next steps. Only the main session updates it.
- This plan lives in `docs/` and is read when starting a phase, not loaded automatically.