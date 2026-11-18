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

Viele Haushaltsbuch-Apps überfordern Nutzer mit tief verschachtelten
Kategoriensystemen. "Smart Spend" verfolgt einen minimalistischen Ansatz: Der
Nutzer gibt eine Ausgabe als einfachen Satz ein (z. B. "Habe heute 15 Euro für
Kinokarten bezahlt"); ein KI-Modell (`gpt-6-luna`) extrahiert Betrag, Titel und
Kategorie als strukturiertes JSON.

**Mehrwert:**
- **Zeitersparnis:** keine manuelle Kategorisierung über Dropdown-Menüs.
- **Reduzierte kognitive Last:** keine eigenen Kategorisierungsregeln nötig.
- **Konsistenz:** die KI sorgt für einheitliche Zuordnung.

(Ausführlich in `README.md`, Abschnitte 12.)

## 2. Anforderungen (MoSCoW)

Die Anforderungen wurden nach MoSCoW priorisiert, um die verpflichtende
Kern-Webanwendung zuerst fertigzustellen und erst danach das KI-Feature zu
integrieren.

- **Must:** Flutter-Web-Client (Erfassungsformular, Dashboard, Historie),
  Dart-Backend (REST-API via OpenAPI, persistente DB, aggregierte Daten).
- **Should:** KI-Klassifizierung (Freitext ’ JSON), AI Engineering Journal.
- **Could:** automatische Tests + statische Analyse, Docker-Deployment.

Vollständige Auflistung in `README.md`, Abschnitt 3. Die konsequente
MoSCoW-Reihenfolge ist in Journal-Eintrag 1 reflektiert.

## 3. Architektur

### 3.1 Überblick

Verteilte Client-Server-Architektur mit zentraler Datenbank und einem externen
KI-Dienst:

```
[ Flutter Web Client ]  --HTTP/JSON-->  [ Dart shelf Server ]  --SQL-->  [ SQLite ]
   provider (State)                         CRUD + /classify
                                                 |
                                                 +--HTTPS-->  [ gpt-6-luna (OpenAI) ]
```

> TODO: Architektur-Diagramm als Grafik einfügen (z. B. draw.io / Mermaid-Export).

### 3.2 Komponenten

| Schicht | Technologie | Ort | Aufgabe |
|---|---|---|---|
| Frontend | Flutter Web, `provider` | `flutter_application/lib/` | UI, State-Management |
| Backend | Dart, `shelf`, `shelf_router` | `server_app/bin/`, `server_app/lib/` | REST-API, CORS, DB-Zugriff |
| API-Vertrag | OpenAPI 3.0 | `api.yaml` | Single Source of Truth Client”Server |
| Generierter Client | OpenAPI Generator (Dart) | `openapi/` | typisierter API-Client (read-only) |
| Persistenz | SQLite (`sqlite3`) | `server_app/lib/db/` | Speicherung der Ausgaben |
| KI | `gpt-6-luna` via HTTPS | `server_app/lib/services/ai_service.dart` | Text-Klassifizierung |

### 3.3 Datenmodell

Tabelle `expenses` (SQLite): `id` (PK, autoincrement), `title`, `category`,
`subcategory` (optional), `description` (optional), `amount` (REAL),
`timestamp` (TEXT, ISO-8601).

Im API-Vertrag: `ExpenseInput` (vom Client gesendet) und `Expense` (`allOf`
ExpenseInput + server-vergebene `id`/`timestamp`). `category` ist aktuell ein
Enum im `api.yaml`.

### 3.4 API-Endpunkte

| Methode | Pfad | Zweck |
|---|---|---|
| GET | `/expenses` | alle Ausgaben auflisten |
| POST | `/expenses` | Ausgabe anlegen |
| PUT | `/expenses/{id}` | Ausgabe aktualisieren |
| DELETE | `/expenses/{id}` | Ausgabe löschen |
| POST | `/classify` | Freitext ’ strukturierter `ExpenseInput` (KI) |
| POST | `/chat` | generischer Chat-Endpunkt (Alt-Pfad) |

## 4. Umsetzung nach Phasen

- **Phase 1  API-Vertrag:** `Expense`/`ExpenseInput`-Schemata, Kategorien-Enum,
  CRUD-Pfade. Client nach jeder Änderung neu generiert (`/openapi` nie manuell
  editiert). ’ Journal 1.
- **Phase 2  Backend-CRUD:** SQLite-Anbindung, shelf-Handler je Route,
  Mapping SQL-Row ” generiertes Modell, CORS-Middleware, Port 8082.
  11 Server-Tests. ’ Journal 2, 3.
- **Phase 3  Flutter-CRUD-UI:** `ExpenseProvider` (ChangeNotifier) mit
  load/add/edit/remove, Dashboard + Formular, gebunden an den generierten
  Client. 6 Provider-Tests. ’ Journal 4.
- **Phase 4  KI-Klassifizierung:** `AiService` (Secrets-Laden mit
  Präzedenz, defensives JSON-Parsing), `/classify`-Endpunkt, "Parse with
  AI"-Feld im Formular. 7 AI-Tests. ’ Journal 5.
- **Analytics-Dashboard:** clientseitig abgeleitete Auswertungen
  (Kategorie-Anteil, Monatstrend, Monatsvergleich) über `fl_chart`.
  12 Analytics-Tests. ’ Journal 6.

## 5. Entwurfsentscheidungen (Auswahl)

Die ausführlichen Begründungen stehen im AI Engineering Journal; hier die
Kurzfassung:

1. **MoSCoW vor Begeisterung:** erst die testbare CRUD-App, dann die KI als
   dünner Adapter in den bestehenden Create-Flow  kein paralleler Code-Pfad.
   (Journal 1)
2. **Explizite Validierung statt `assert()`:** `assert()` wird im Release-Build
   entfernt; Eingabeprüfung erfolgt daher unbedingt und gibt sauberes `400`
   zurück. (Journal 2)
3. **Dual-Enum-Brücke:** der Generator erzeugt aus `allOf` zwei Enum-Klassen;
   überbrückt wird auf dem String-`.value` als stabiler Wire-Repräsentation.
   (Journal 3)
4. **KI-Grenze = nicht vertrauenswürdige Eingabe:** defensives Parsen der
   Modellantwort (erster `{...}`-Block, String-/Komma-Beträge, Fallback
   `other`). (Journal 5)
5. **Analytics als "Views":** Auswertungen sind Projektionen über die bereits im
   Provider gecachten Daten  kein zusätzlicher Backend-Endpunkt. (Journal 6)

## 6. Qualitätssicherung

- **Automatische Tests:** Backend `dart test` (11 Server + 7 AI = 18);
  Frontend `flutter test` (6 Provider + 12 Analytics = 18). Alle grün.
- **Statische Analyse:** `dart analyze` und `flutter analyze` ohne Befunde.
- **Teststrategie:** Provider-Tests laufen gegen einen `FakeDefaultApi`
  (kein Server/DB nötig); zeitbasierte Analytics-Methoden erhalten ein
  injizierbares `now` für deterministische Tests.

> TODO: Screenshots einfügen (Dashboard, Formular, Analytics, KI-Parsing).

## 7. Lokale Ausführung

Zwei Prozesse (Backend zuerst). Details inkl. Troubleshooting in `README.md`,
Abschnitt 5. Kurz:

```bash
# Terminal 1  Backend
cd server_app && dart run bin/server.dart     # http://0.0.0.0:8082

# Terminal 2  Frontend
cd flutter_application && flutter run -d chrome
```

## 8. Ausblick / Future Work

Geplante bzw. diskutierte Erweiterungen (nach Aufwand/Abhängigkeit geordnet):

1. **Dynamische Kategorien:** Erkennt die KI eine noch nicht existierende
   Kategorie, wird diese angelegt und in die Kategorienliste aufgenommen.
   Erfordert, `category` vom Enum zu einer DB-Tabelle (`/categories`) zu lösen;
   Normalisierung/Deduplizierung nötig.
2. **Login-System:** Benutzer-Tabelle, Passwort-Hashing, Auth-Endpunkte,
   Token/Session, Auth-Middleware, `user_id`-Fremdschlüssel auf `expenses`.
   Voraussetzung für korrekte Mehrbenutzer-Synchronisierung.
3. **Geräte-Synchronisierung:** fällt weitgehend aus dem (Docker-)Deployment
   des Backends ab; pro Nutzer korrekt erst mit Login.
4. **Android-Version:** gleicher Flutter-Code; benötigt eine konfigurierbare
   Server-URL statt `localhost` sowie ein erreichbares Backend.

> TODO: nach Umsetzung jeweils in Abschnitt 4/5 nachziehen.

## 9. Fazit

> TODO: Abschließende Reflexion schreiben (Was lief gut, was war schwierig,
> was wurde über Dart/Flutter/verteilte Architektur gelernt). Material dafür
> liefern die sechs Journal-Einträge.
