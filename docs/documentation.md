# Smart Spend  Projektdokumentation (Ausarbeitung)

> Projekt Web-Entwicklung (26Q4), Modul bei Prof. Soltenborn.
> Diese Ausarbeitung fasst Idee, Architektur, Umsetzung, Entwurfsentscheidungen
> und Reflexion zusammen. Die vertiefenden KI-Interaktionen sind separat im
> `ai_engineering_journal.md` dokumentiert (wird gesondert eingereicht, nicht im
> Repo).
>
> STATUS: Lebendes Dokument. Mit jedem Feature erweitern. Offene Punkte sind mit
> `TODO` markiert.

---

## 1. Idee & Mehrwert

Viele Haushaltsbuch-Apps �berfordern Nutzer mit tief verschachtelten
Kategoriensystemen. "Smart Spend" verfolgt einen minimalistischen Ansatz: Der
Nutzer gibt eine Ausgabe als einfachen Satz ein (z. B. "Habe heute 15 Euro f�r
Kinokarten bezahlt"); ein KI-Modell (`gpt-6-luna`) extrahiert Betrag, Titel und
Kategorie als strukturiertes JSON.

**Mehrwert:**
- **Zeitersparnis:** keine manuelle Kategorisierung �ber Dropdown-Men�s.
- **Reduzierte kognitive Last:** keine eigenen Kategorisierungsregeln n�tig.
- **Konsistenz:** die KI sorgt f�r einheitliche Zuordnung.

(Ausf�hrlich in `README.md`, Abschnitte 12.)

## 2. Anforderungen (MoSCoW)

Die Anforderungen wurden nach MoSCoW priorisiert, um die verpflichtende
Kern-Webanwendung zuerst fertigzustellen und erst danach das KI-Feature zu
integrieren.

- **Must:** Flutter-Web-Client (Erfassungsformular, Dashboard, Historie),
  Dart-Backend (REST-API via OpenAPI, persistente DB, aggregierte Daten).
- **Should:** KI-Klassifizierung (Freitext � JSON), AI Engineering Journal.
- **Could:** automatische Tests + statische Analyse, Docker-Deployment.

Vollst�ndige Auflistung in `README.md`, Abschnitt 3. Die konsequente
MoSCoW-Reihenfolge ist in Journal-Eintrag 1 reflektiert.

## 3. Architektur

### 3.1 �berblick

Verteilte Client-Server-Architektur mit zentraler Datenbank und einem externen
KI-Dienst:

```
[ Flutter Web Client ]  --HTTP/JSON-->  [ Dart shelf Server ]  --SQL-->  [ PostgreSQL 16 (Docker) ]
   provider (State)                         CRUD + /classify
                                                 |
                                                 +--HTTPS-->  [ gpt-6-luna (OpenAI) ]
```

> TODO: Architektur-Diagramm als Grafik einf�gen (z. B. draw.io / Mermaid-Export).

### 3.2 Komponenten

| Schicht | Technologie | Ort | Aufgabe |
|---|---|---|---|
| Frontend | Flutter Web, `provider` | `flutter_application/lib/` | UI, State-Management |
| Backend | Dart, `shelf`, `shelf_router` | `server_app/bin/`, `server_app/lib/` | REST-API, CORS, DB-Zugriff |
| API-Vertrag | OpenAPI 3.0 | `api.yaml` | Single Source of Truth Client�Server |
| Generierter Client | OpenAPI Generator (Dart) | `openapi/` | typisierter API-Client (read-only) |
| Persistenz | PostgreSQL 16 in Docker Compose, Dart-Paket `postgres` (Connection-Pool) | `server_app/lib/db/`, `docker-compose.yml` | Speicherung der Ausgaben und Kategorien |
| KI | `gpt-6-luna` via HTTPS | `server_app/lib/services/ai_service.dart` | Text-Klassifizierung |

### 3.3 Datenmodell

Tabelle `expenses` (PostgreSQL): `id` (PK, `GENERATED ALWAYS AS IDENTITY`), `title`, `category`,
`subcategory` (optional), `description` (optional), `amount` (`NUMERIC(12, 2)`, exakte
Cent-Betraege; in der API weiterhin `number`, Umrechnung nur im Handler),
`timestamp` (`TIMESTAMPTZ`, Default `now()`; in der API als ISO-8601 in UTC).

Tabelle `categories` (PostgreSQL): `id` (PK, Identity), `name` mit Unique-Index auf `lower(name)` (case-insensitive Eindeutigkeit, ersetzt SQLites `COLLATE NOCASE`).
Schema und Seed (9 Basiskategorien) stehen in der Migration
`server_app/migrations/001_initial_schema.sql` (siehe Entwurfsentscheidung 7). `other` ist
bewusst **nicht** Teil des Seeds (siehe Abschnitt 5, Entwurfsentscheidung 6).

Im API-Vertrag: `ExpenseInput` (vom Client gesendet) und `Expense` (`allOf`
ExpenseInput + server-vergebene `id`/`timestamp`). `category` war urspruenglich
ein Enum im `api.yaml`; seit dem Feature "Dynamische Kategorien" ist es ein
Freitext-String, der serverseitig gegen die `categories`-Tabelle find-or-create
(case-insensitive) aufgeloest wird. `subcategory` ist ein optionaler
Freitext-Zusatz: eine feinere Gruppierung unterhalb der stabilen Oberkategorie
(z. B. Casino -> `entertainment`/`gambling`), die die KI beim Klassifizieren
optional mitliefert (siehe Journal 8). `description` beherbergt den optionalen
**KI-Kommentar**: ein kurzer, lustiger Einzeiler aus Sicht eines
Finanzberaters (siehe Journal 9) - frei editierbar, Feld bleibt
general-purpose.

**Forschungs-Log (nur Dokumentation):** `docs/classification_log.jsonl` haelt
pro `/classify`-Aufruf eine JSON-Zeile fest (Eingabe, bekannte Kategorien, rohe
Modellantwort, geparstes Ergebnis inkl. `parsed_subcategory` und
`parsed_description`, `was_new_category`). Es ist **kein** Nutzer-Feature und
wird **nicht** in der App-DB gespeichert; es dient allein der Analyse des
Modellverhaltens fuer diese Ausarbeitung (vgl. Journal 7, 8, 9).

### 3.4 API-Endpunkte

| Methode | Pfad | Zweck |
|---|---|---|
| GET | `/expenses` | alle Ausgaben auflisten |
| POST | `/expenses` | Ausgabe anlegen |
| PUT | `/expenses/{id}` | Ausgabe aktualisieren |
| DELETE | `/expenses/{id}` | Ausgabe l�schen |
| POST | `/classify` | Freitext -> strukturierter `ExpenseInput` (KI) |
| GET | `/categories` | alle Kategorien auflisten |
| POST | `/categories` | Kategorie find-or-create (case-insensitive) |
| POST | `/chat` | generischer Chat-Endpunkt (Alt-Pfad) |

## 4. Umsetzung nach Phasen

- **Phase 1  API-Vertrag:** `Expense`/`ExpenseInput`-Schemata, Kategorien-Enum,
  CRUD-Pfade. Client nach jeder �nderung neu generiert (`/openapi` nie manuell
  editiert). � Journal 1.
- **Phase 2  Backend-CRUD:** SQLite-Anbindung, shelf-Handler je Route,
  Mapping SQL-Row � generiertes Modell, CORS-Middleware, Port 8082.
  11 Server-Tests. � Journal 2, 3.
- **Phase 3  Flutter-CRUD-UI:** `ExpenseProvider` (ChangeNotifier) mit
  load/add/edit/remove, Dashboard + Formular, gebunden an den generierten
  Client. 6 Provider-Tests. � Journal 4.
- **Phase 4  KI-Klassifizierung:** `AiService` (Secrets-Laden mit
  Pr�zedenz, defensives JSON-Parsing), `/classify`-Endpunkt, "Parse with
  AI"-Feld im Formular. 7 AI-Tests. � Journal 5.
- **Analytics-Dashboard:** clientseitig abgeleitete Auswertungen
  (Kategorie-Anteil, Monatstrend, Monatsvergleich) via `fl_chart`.
  12 Analytics-Tests. Journal 6.
- **Dynamische Kategorien:** `category` vom Enum zu einer `categories`-Tabelle
  migriert; `/categories`-Endpunkte, find-or-create beim Speichern, dynamisches
  Dropdown (bestehende Liste + KI-Vorschlag "(new)" + Freitext). Prompt
  bevorzugt bestehende Kategorien bzw. erfindet eine spezifische neue und
  vermeidet Sammelkategorien wie `other`. Forschungs-Log fuer die KI-Analyse.
  19 Backend-Tests. Journal 7.
- **KI-Unterkategorien:** Der `/classify`-Prompt liefert zusaetzlich eine
  optionale `subcategory` (feinere Gruppierung unterhalb der stabilen
  Oberkategorie, z. B. Casino -> `entertainment`/`gambling`); defensives Parsen
  (leer/fehlend -> `null`), Anzeige/Bearbeitung im vorhandenen Formularfeld.
  Datenmodell war bereits vorbereitet (keine Client-Neugenerierung noetig).
  22 Backend-Tests. Journal 8.
- **KI-Kommentar:** Der `/classify`-Prompt liefert zudem einen optionalen,
  lustigen Einzeiler aus Sicht eines Finanzberaters (tadelnd bei Verschwendung,
  anerkennend bei sinnvollen Kaeufen) im vorhandenen `description`-Feld. Prompt
  enthaelt positive UND negative Beispiele plus Sprach-/"nie beleidigend"-Regel.
  Feld in "KI-Kommentar" umbenannt, frei editierbar. 24 Backend-Tests. Journal 9.
- **Phase 0 (Infrastruktur), Schritt 3 - PostgreSQL-Migration:** DB-Schicht von
  `sqlite3` auf das Paket `postgres` (Connection-Pool) umgestellt; Handler sind
  jetzt durchgehend `async`. Schema per nummerierten SQL-Migrationen mit
  `schema_version`-Tabelle, `IDENTITY`-Spalten statt `AUTOINCREMENT`,
  `NUMERIC(12, 2)` fuer Betraege, `TIMESTAMPTZ` statt ISO-Text, Unique-Index auf `lower(name)` statt
  `COLLATE NOCASE`, Find-or-create als ein `INSERT ... ON CONFLICT ... DO UPDATE
  ... RETURNING`, `RETURNING` statt `lastInsertRowId`. Verbindungsdaten aus
  `.env`/Umgebung (`DbConfig`). 51 Backend-Tests.

## 5. Entwurfsentscheidungen (Auswahl)

Die ausf�hrlichen Begr�ndungen stehen im AI Engineering Journal; hier die
Kurzfassung:

1. **MoSCoW vor Begeisterung:** erst die testbare CRUD-App, dann die KI als
   d�nner Adapter in den bestehenden Create-Flow  kein paralleler Code-Pfad.
   (Journal 1)
2. **Explizite Validierung statt `assert()`:** `assert()` wird im Release-Build
   entfernt; Eingabepr�fung erfolgt daher unbedingt und gibt sauberes `400`
   zur�ck. (Journal 2)
3. **Dual-Enum-Br�cke:** der Generator erzeugt aus `allOf` zwei Enum-Klassen;
   �berbr�ckt wird auf dem String-`.value` als stabiler Wire-Repr�sentation.
   (Journal 3)
4. **KI-Grenze = nicht vertrauensw�rdige Eingabe:** defensives Parsen der
   Modellantwort (erster `{...}`-Block, String-/Komma-Betr�ge, Fallback
   `other`). (Journal 5)
5. **Analytics als "Views":** Auswertungen sind Projektionen �ber die bereits im
   Provider gecachten Daten  kein zus�tzlicher Backend-Endpunkt. (Journal 6)
6. **Kategorien als Daten, aber diszipliniert:** `category` wurde vom festen
   Enum zu einer DB-Tabelle (find-or-create, case-insensitive; heute per Unique-Index auf `lower(name)`). Gegen
   Synonym-Wildwuchs wirkt A+C: der KI-Prompt bevorzugt bestehende Kategorien
   (A), neue entstehen erst beim Speichern (C). `other` ist bewusst nicht mehr
   geseedet und wird dem Modell nicht angeboten - es ueberlebt nur als
   Not-Fallback fuer eine leere Modellantwort. Begruendung: ein Seed-Wert ist
   fuer das Modell auch ein Signal; `other` als bequemer Sammeltopf verhindert
   spezifische Kategorien. (Journal 7)
7. **PostgreSQL statt SQLite, Zugangsdaten nur im Server:** der Server liest
   Host/Port/DB/User/Passwort aus Umgebungsvariablen bzw. der `.env` im
   Repo-Root (dieselbe Datei wie Docker Compose), ohne Default-Passwort.
   Das Schema wird ueber nummerierte SQL-Dateien (`server_app/migrations/NNN_name.sql`)
   verwaltet: beim Start wendet der Server alle noch nicht in `schema_version`
   eingetragenen Dateien in einer Transaktion an (Advisory-Lock gegen parallele
   Starts, bei Fehler kompletter Rollback). Bereits angewendete Dateien werden nie
   geaendert, Aenderungen (z. B. `users` fuer den Login) kommen als neue Datei.
   Eigener kleiner Runner statt Bibliothek, da nur Vorwaerts-Migrationen noetig sind.

## 6. Qualit�tssicherung

- **Automatische Tests:** Backend `dart test` (51, inkl. Server-CRUD, Betraege und Kategorien gegen PostgreSQL, Migrationen, DB-Konfiguration, AI-Parsing
  mit Unterkategorien und KI-Kommentar sowie Kategorien-Handler); Frontend
  `flutter test` (6 Provider + 12 Analytics = 18). Alle gr�n.
- **Statische Analyse:** `dart analyze` und `flutter analyze` ohne Befunde.
- **Teststrategie:** Provider-Tests laufen gegen einen `FakeDefaultApi`
  (kein Server/DB n�tig); zeitbasierte Analytics-Methoden erhalten ein
  injizierbares `now` f�r deterministische Tests.
- **Datenbank-Isolation in Tests:** jeder Server-Test legt eine eigene,
  zufaellig benannte PostgreSQL-Datenbank (`smart_spend_test_<zeit>_<zufall>`)
  an und loescht sie danach (`DROP DATABASE ... WITH (FORCE)`). Parallele
  Testlaeufe (z. B. mehrere Agents) teilen sich so einen `db`-Container, ohne
  sich gegenseitig Daten zu ueberschreiben, und jeder Test durchlaeuft die echten
  Migrationen. Ersetzt SQLites `:memory:`.

> TODO: Screenshots einf�gen (Dashboard, Formular, Analytics, KI-Parsing).

## 7. Lokale Ausf�hrung

PostgreSQL-Container plus zwei Prozesse (Datenbank, dann Backend, dann Frontend). Details inkl. Troubleshooting in `README.md`,
Abschnitt 5. Kurz:

```bash
# Einmalig: cp .env.example .env und POSTGRES_PASSWORD setzen
docker compose up -d --wait                   # PostgreSQL 16 auf 127.0.0.1:5432

# Terminal 1  Backend
cd server_app && dart run bin/server.dart     # http://0.0.0.0:8082

# Terminal 2  Frontend
cd flutter_application && flutter run -d chrome
```

## 8. Ausblick / Future Work

Geplante bzw. diskutierte Erweiterungen (nach Aufwand/Abh�ngigkeit geordnet):

1. **Login-System (NAECHSTER SCHRITT):** Benutzer-Tabelle, Passwort-Hashing,
   Auth-Endpunkte, Token/Session, Auth-Middleware, `user_id`-Fremdschl�ssel auf
   `expenses`. Voraussetzung f�r korrekte Mehrbenutzer-Synchronisierung.
2. **Ger�te-Synchronisierung:** f�llt weitgehend aus dem (Docker-)Deployment
   des Backends ab; pro Nutzer korrekt erst mit Login.
3. **Android-Version:** gleicher Flutter-Code; ben�tigt eine konfigurierbare
   Server-URL statt `localhost` sowie ein erreichbares Backend.

Bereits umgesetzt (vormals hier geplant): **KI-Unterkategorien** (optionale
`subcategory` aus der KI, siehe Abschnitt 4, Journal 8).

> TODO: nach Umsetzung jeweils in Abschnitt 4/5 nachziehen.

## 9. Fazit

> TODO: Abschlie�ende Reflexion schreiben (Was lief gut, was war schwierig,
> was wurde �ber Dart/Flutter/verteilte Architektur gelernt). Material daf�r
> liefern die sechs Journal-Eintr�ge.
