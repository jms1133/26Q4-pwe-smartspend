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
- **Containers:** Docker Compose with PostgreSQL, the shelf server and SonarQube. Flutter itself is not containerized.
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

- SonarQube or SonarCloud (verify current Dart support) plus `dart analyze` / `flutter analyze` with strict lints.
- Dependabot for vulnerable or outdated packages.
- Isolation tests: user A cannot read, edit or delete user B's expenses.

## Quality and CI

- Tests for every new handler and Provider before a feature counts as done.
- GitHub Actions on every push: `dart analyze`, `dart test`, `flutter analyze`, `flutter test`, SonarQube.
- Claude records a factual AI log entry per feature in `docs/ai_logs.md`; Julian writes `docs/ai_engineering_journal.md` himself. `documentation.md` update committed with each feature.

## Work order and agents

Parallel Claude Code sessions, each in its own git worktree and branch (`claude --worktree <name>`).

**Phase 0 – one session, sequential (comes before all other phases):**

- Docker Compose with PostgreSQL and SonarQube.
- Migrate the DB layer from SQLite to PostgreSQL.
- Make the test server port configurable (`server_test.dart` currently uses fixed port 8082, which would collide between agents).
- Basic GitHub Actions pipeline.

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