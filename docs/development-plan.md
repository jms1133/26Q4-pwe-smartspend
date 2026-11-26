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
3. Exactly one subprocess smoke test stays, in its own file `test/server_startup_test.dart` (so the in-process `setUp` doesn't run for it): it starts `bin/server.dart` with `PORT=0` and its own database and checks that the server comes up and `GET /expenses` returns 200 (env config + migrations at startup). The rest of the process plumbing is removed from the CRUD tests.
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

**Step 7 – Login system backend** · branch `feature/login-backend` from `main` (`715d9e0`). `feature/login-ui` branches from it later; both PRs merge back to back, so `main` never has an app that gets 401 everywhere. Demo fallback: tag `pre-login` on `main` (Julian).
Goal: users register with a username and log in; every expense and category belongs to exactly one user, and no user can read, change or delete another user's data.
Agreed decisions:
1. `api.yaml` first. Security scheme `bearerAuth` (HTTP bearer, JWT) applied globally; `security: []` on `/`, `/auth/register`, `/auth/login`. `POST /auth/register`: `Credentials` → 201 `User` {id, username}; 400 invalid, 409 taken, 429. `POST /auth/login`: `Credentials` → 200 `AuthToken` {token, expiresAt}; 400, 401, 429. `Credentials` = {username, password}. 401 on every protected path. `/echo` is removed from the router (never in `api.yaml`). Julian regenerates `openapi/`.
2. Migration `002_users.sql` (runs in the runner's transaction; 001 stays unchanged). Deletes all existing expenses and categories first, with a comment why (dev data only, seed script follows). `users`: `id` identity PK, `username TEXT NOT NULL`, `password_hash TEXT NOT NULL`, `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`, unique index on `lower(username)`. `categories`: drop `categories_name_lower_key`; add `user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE`, `UNIQUE (user_id, id)`, unique index `(user_id, lower(name))`. `expenses`: `category TEXT` is replaced by `category_id INTEGER NOT NULL`; add `user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE`, composite FK `(user_id, category_id) REFERENCES categories (user_id, id)` (an expense can't point to another user's category), index `(user_id, timestamp DESC)`. Handlers return the category name via a JOIN; the `Expense` schema in `api.yaml` is unchanged.
3. Per-user categories. The 9 seed names become a Dart constant in `lib/`. `POST /auth/register` runs `INSERT INTO users … RETURNING id` and the seed copy into `categories` in one `runTx`. Find-or-create uses `ON CONFLICT (user_id, (lower(name)))`, the exact expression of the new index. The `/classify` prompt lists only the current user's categories.
4. Username: trimmed and lowercased first, then validated against `^[a-z0-9._-]{3,32}$`; stored and compared lowercase. No email (no verification or reset in scope, so it would only store personal data).
5. Passwords: package `bcrypt` 1.2.0. `hashpw`/`checkpw` run inside `Isolate.run`, because the package is synchronous and would block the single server isolate for every request. Cost from `BCRYPT_COST` (default 12, tests 4). Password length 8–72, checked as `utf8.encode(password).length` (bcrypt ignores bytes after 72). Unknown username: `checkpw` against a dummy hash computed once at startup with the same cost, then the same 401 as a wrong password, so response time doesn't reveal which accounts exist.
6. JWT: package `dart_jsonwebtoken` 3.4.1, HS256, claims `sub` (user id), `iat`, `exp`, valid 1 hour. Before verifying, the header must have `alg == "HS256"` and `typ == "JWT"`; everything else, including `none`, is rejected. `JWT.verify(SecretKey)` runs with `checkExpiresIn: false`; `TokenService` compares `exp` against an injected `DateTime Function() now` (same pattern as the analytics getters' `now`), not `package:clock`, which works through zones that shelf_io may not pass to request handlers. The rate limiter uses the same `now`. `JWT_SECRET` from env or `.env` via `AuthConfig.fromEnvironment` (same pattern as `DbConfig`); the server doesn't start if it is missing or shorter than 32 bytes. `.env.example` gets a placeholder, `ci.yml` a test-only value in the job `env` (not a secret); the test setup and `server_startup_test.dart` set it themselves.
7. Middleware order in `buildHandler`: logging → CORS → auth → router. CORS sits outside auth, so preflights are answered without a token and 401 responses carry the CORS headers. `Access-Control-Allow-Headers` in `_corsHeaders` must contain `Authorization`; checked on 2026-11-26: it already does (`Origin, Content-Type, Authorization`), so only a test is added. Auth lets `OPTIONS`, `/` and `/auth/*` through; everything else needs `Authorization: Bearer <jwt>`, otherwise 401 with `WWW-Authenticate: Bearer`. Valid token → `request.change(context: {'userId': id})`.
8. Data isolation: every expense and category query has `WHERE user_id = @userId` from `request.context`, never from body or URL. Another user's expense → 404, same as an unknown id.
9. Error responses: unknown user and wrong password give an identical 401. A taken username gives 409, which reveals the account exists; documented trade-off, reduced by the register rate limit.
10. Rate limits, in memory, injected clock, client IP from `request.context['shelf.io.connection_info']`. Login: 5 failures per (IP, username) in 15 minutes → 429; a successful login resets the counter. Register: 10 attempts per IP per hour → 429. 429 sends `Retry-After` in seconds. Expired entries are pruned on every check, so the map can't grow without limit. Limits are constructor parameters, so tests use small values. Known limitation (documented): the per-(IP, username) key doesn't stop password spraying, i.e. one password tried against many usernames from one IP.
11. Tests, in-process like Step 6: `auth_test.dart` (register, login, middleware, JWT, CORS, rate limits), `isolation_test.dart` (two users), unit tests for `TokenService` and the rate limiter. Existing server tests get a `setUp` helper that registers `alice` and sends her token; assertions change only where the schema requires it. Fictional usernames only (`alice`, `bob`) in tests, curl sessions and docs.
Out of scope: Login UI, refresh tokens, password reset, PostgreSQL row-level security, shelf server container, `/classify` and `/chat` tests with a fake HTTP client.
Done:
1. `dart analyze lib test bin` clean, `dart test` all green (show output).
2. `api.yaml` updated. (Julian) client regenerated; afterwards `flutter analyze` and `flutter test` still clean.
3. Isolation tests pass for read, update and delete in both directions, plus the composite category FK (list test names).
4. Test names for: the dummy-hash path; each rejected JWT variant (other algorithm, `none`, wrong secret, altered payload, expired); the preflight asserting `Access-Control-Allow-Headers` contains `Authorization`; CORS headers on a 401; login rate limit (429 + `Retry-After` + reset on success); register rate limit.
5. `curl` session with `alice`: register → login → `GET /expenses` with token 200, without token 401, `OPTIONS` without token 200.
6. (Julian) CI green. `JWT_SECRET` in `.env.example` (placeholder) and `ci.yml` (test value); no real secret committed.
7. Brief in this plan; AI log Entry 11; auth section in `docs/documentation.md` incl. the 409 trade-off and password spraying as known limitations.

**Step 8 – Login UI** · branch `feature/login-ui` from `main` (`dc20c59`). Backend unchanged; no `api.yaml` change, no client regeneration.
Goal: users register and log in in the Flutter app, every request after that carries the token, an expired or invalid token leads back to the login screen, and the app on `main` works again.
Agreed decisions:
1. `AuthProvider` (ChangeNotifier) in `lib/providers/auth_provider.dart`. State: `token`, `expiresAt`, `username`, `isBusy`, `isRestoring`, `error`. `isAuthenticated` = token present and `expiresAt` after an injected `DateTime Function() now` (same pattern as the analytics getters). Methods `restore`, `login`, `register`, `logout`. `notifyListeners()` after every state change; the gate rebuilds only through it.
2. One shared `ApiClient` with `HttpBearerAuth()..accessToken = () => auth.token ?? ''`. The generated client calls the getter on every request and skips the header for an empty string, so `ExpenseProvider` and `_classify` send the current token without further changes.
3. Token storage: package `shared_preferences` (browser `localStorage` on web) behind a `TokenStore` interface (`read`, `write`, `clear`). It stores `token` and `expiresAt`; `logout()` clears both. Tests use an in-memory `TokenStore`. `restore()` at app start drops an expired token. Documented trade-off: any XSS can read `localStorage`; the 1-hour token validity limits the damage. Android can later swap in `flutter_secure_storage` behind the same interface.
4. Register logs in automatically: `register()` then `login()` with the same credentials. If register succeeds but the following login fails, the screen shows "Account created, please log in" and switches to login mode.
5. `AuthGate` as `MaterialApp.home`: a loading indicator while `isRestoring` (so the login screen doesn't flash on reload), `LoginScreen` when logged out, `DashboardScreen` when logged in. `main.dart` no longer calls `loadExpenses()`/`loadCategories()` at provider creation (that request would have no token); the dashboard loads in `initState`. On logout `ExpenseProvider.clear()` empties expenses, categories and error.
6. Stale responses: `ExpenseProvider` has a session counter, incremented in `clear()`. Every request captures the counter before `await`; if it changed when the response arrives, the response is dropped (no state change, no notify). A request started as alice can't fill the lists after bob logs in.
7. 401 on a protected request: `ExpenseProvider` takes an `onUnauthorized` callback; any `ApiException` with code 401 calls it, and it calls `auth.logout(reason: sessionExpired)`. `_classify` does the same. The gate shows the login screen with "Session expired, please log in again." `logout()` is idempotent: several parallel 401s produce one state change, one notify and one message. A 401 from `login()` itself shows "Invalid username or password.", never "Session expired".
8. Error messages: login and register call `loginWithHttpInfo`/`registerWithHttpInfo`, because only the raw response carries `Retry-After`. 429 → "Too many attempts. Try again in N min." (rounded up from `Retry-After` seconds); 401 → "Invalid username or password."; 409 → "Username is already taken."; 400 → the server's message.
9. Network errors: the generated client rethrows socket/HTTP-client errors as `ApiException(400)` with an `innerException`. Every error mapping checks `innerException != null` first and shows "Server not reachable", not the raw message or a 400 text. Applies to `AuthProvider` and `ExpenseProvider`.
10. `LoginScreen`: one screen with a login/register toggle; register mode adds "Confirm password". Client-side checks mirror the server for usability only: username trimmed and lowercased, `^[a-z0-9._-]{3,32}$`; password 8–72 bytes as `utf8.encode(password).length`. The dashboard AppBar shows the username and a logout button.
11. Tests: `auth_provider_test.dart` with a fake `DefaultApi` and the in-memory `TokenStore` (login success stores token + expiresAt; wrong password; 429 message with `Retry-After`; register then login; register OK + login fails → "Account created"; 409; network error → "Server not reachable"; logout clears store and state; parallel logouts → one notify; `restore` keeps a valid and drops an expired token; the bearer getter returns the current token). `ExpenseProvider`: 401 calls `onUnauthorized`; `clear()` empties state; stale response after `clear()` is dropped; network error → "Server not reachable". Widget tests: gate shows the loading state during restore, login when logged out, dashboard when logged in; form validation; successful login switches to the dashboard. Fictional usernames only (`alice`, `bob`).
Out of scope: refresh tokens, configurable server URL and Android, CORS restricted to the web origin (Phase 4), seed script, redesign, backend changes.
Done:
1. `flutter analyze` clean, `flutter test` all green (show output).
2. Test names for: login success and failure, 429 with `Retry-After`, 409, register-then-login-fails, network error, logout clearing data, idempotent logout, expired token on restore, 401 leading back to login, stale response dropped, gate loading/login/dashboard.
3. `dart analyze lib test bin` and `dart test` in `server_app` still green (backend unchanged).
4. (Julian) End-to-end in Chrome: register `alice` → add an expense → reload (still logged in, no login flash) → logout → register `bob` → empty list. Edit the token in DevTools → Application → Local Storage, trigger a request → back to login with the session-expired message.
5. (Julian) CI on the PR green, including the SonarQube Cloud quality gate.
6. Brief in this plan; AI log Entry 12; client side of the auth section in `docs/documentation.md` (§3.5) incl. the `localStorage` trade-off; `current_state.md` updated.

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