# Smart Spend – Agent Instructions

@.claude/current_state.md

## Project
Expense tracker for the university module "Projekt Web-Entwicklung" (Prof. Soltenborn).
Users enter natural language ("15 euros for cinema tickets"); the AI model gpt-6-luna
extracts amount, category, subcategory, title and a funny comment.
Grading: 50% code quality, 30% documentation, 20% presentation.
Roadmap and agent phases: `docs/development-plan.md` (read when starting a phase).

## Stack & folders
- `flutter_application/` – Flutter Web (later Android), state with `provider`
- `server_app/` – Dart `shelf` + `shelf_router` backend (port 8082), DB layer in `lib/db/`,
  AI client in `lib/services/ai_service.dart`
- `api.yaml` – OpenAPI 3.0 contract, single source of truth
- `openapi/` – generated client, READ-ONLY
- `docs/` – `documentation.md` (Ausarbeitung, German), `ai_logs.md` (AI logs),
  `ai_engineering_journal.md` (Julian's own journal)
- Database: PostgreSQL 16 via Docker Compose (`docker compose up -d --wait`); server reads `POSTGRES_*`/`DB_PORT`/`DB_HOST` from env or the repo-root `.env`. `dart test` needs the `db` container running.
- CI: `.github/workflows/ci.yml` (analyze + tests for both apps, Postgres service container) and a SonarQube Cloud scan (`sonar-project.properties`, token only as GitHub secret `SONAR_TOKEN`). No local SonarQube: the Community Build has no Dart analyzer.

## Rules
1. **MoSCoW:** Must-haves before Should/Could. Follow the order in the development plan.
2. **OpenAPI:** Never edit `openapi/`. Change `api.yaml`, then tell me to regenerate.
3. **Tests:** Write tests for every new handler and Provider before a feature counts as done.
4. **AI logs:** After a significant feature, bug fix or architecture decision, write a log
   entry using the template at the top of `docs/ai_logs.md`. Facts only, no reflection.
   In the main session, append it to `docs/ai_logs.md`. Parallel agents put it in their
   final summary instead; the main session appends it after merging.
5. **Journal:** Never write or edit `docs/ai_engineering_journal.md`. Julian writes it himself.
6. **State:** Only the main session updates `.claude/current_state.md`, at the end of a session
   or after merging. Parallel agents never edit it.
7. **Hidden framework behavior:** Point out when `notifyListeners()` is needed, and explain
   CORS, shelf_router and async request handling when relevant.
8. **Identity:** Never write the email address of the logged-in Claude account into
   code, docs, logs, commit messages or PR descriptions. If attribution is needed,
   use the GitHub account `jms1133` only, with no email address.

## Workflow
9. **Session start:** compare `.claude/current_state.md` with `git status` and
   `git log`; report differences before doing anything else.
10. **Plan first:** for each step, propose a plan and wait for approval. Once
    approved, write the agreed decisions into `docs/development-plan.md` under
    that step before writing code.
11. **Done checklist:** every step brief ends with a numbered done list. The
    final report answers each item with evidence (command output, test names)
    or says "not done". Items marked "Julian" are mine to verify.
12. Update `.claude/current_state.md` when a step's PR is ready, after a
    merge, and at session end — not after every commit. Also update it
    before a long pause or when the context is getting long, so a new
    session can resume. Keep it short: branches, what's done, what's next,
    open points. Decisions live in the brief, details in the AI log; don't
    repeat them here.

## How to explain things to me
- Write complete, production-ready code; don't withhold it. Explain the "why".
- I know SQL and relational databases well: skip DB theory.
- I'm a beginner in Dart, Flutter and shelf: explain async/await, typing,
  JSON-to-object mapping and the widget lifecycle, using database analogies where helpful.

## Commands
SDK is not on PATH, prepend:
export PATH="/Users/julian.morales/code/FHDW/26Q4/WebEntwicklung/dependencies/flutter/bin/cache/dart-sdk/bin:/Users/julian.morales/code/FHDW/26Q4/WebEntwicklung/dependencies/flutter/bin:$PATH"

- Regenerate client (repo root): `java -jar tools/openapi-generator-cli-7.12.0.jar generate -g dart -i api.yaml -o openapi`
- Backend (`server_app/`): `dart analyze lib test`, `dart test`, `dart run bin/server.dart`
- Frontend (`flutter_application/`): `flutter analyze`, `flutter test`, `flutter run -d chrome --web-port=5000`
- Port 8082 blocked by a stale test server: `lsof -tiTCP:8082 -sTCP:LISTEN | xargs kill`
- Server needs `JWT_SECRET` (≥ 32 bytes) in the repo-root `.env`; optional `BCRYPT_COST` (default 12).
- Backend coverage: `dart test --coverage-path=coverage/lcov.info`
- DB shell: `docker compose exec db psql -U smart_spend -d smart_spend`
- Stale UI: `flutter clean && flutter pub get`, then Cmd+Shift+R