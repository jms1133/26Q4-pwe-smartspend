# **Smart Spend - AI-Powered Expense Manager**

## **1. Idee**

Viele Haushaltsbuch-Apps überfordern Nutzer mit komplexen, tief verschachtelten Kategoriensystemen. Nutzer verbringen zu viel Zeit damit, zu entscheiden, ob ein Kaffee-to-go am Bahnhof unter "Lebensmittel", "Restaurant" oder "Reisen" fällt. "Smart Spend" löst dieses Problem durch einen minimalistischen Ansatz: Der Nutzer gibt seine Ausgabe als einfachen Satz ein (z. B. "Habe heute 15 Euro für Kinokarten bezahlt"). Ein angebundenes KI-Modell analysiert den Text, extrahiert den Betrag und ordnet die Ausgabe automatisch einer standardisierten, sinnvollen Kategorie zu.

## **2. Mehrwert**

- **Zeitersparnis & Convenience:** Keine manuelle Kategorisierung oder Navigation durch Dropdown-Menüs mehr nötig.
- **Reduzierte kognitive Last:** Nutzer müssen sich keine eigenen Kategorisierungs-Regeln ausdenken.
- **Konsistenz:** Die KI sorgt für eine einheitliche Zuordnung (z. B. wird "Kino" immer unter "Entertainment" verbucht).

## **3. Anforderungen (MoSCoW-Priorisierung)**

Um eine rechtzeitige Fertigstellung zu garantieren und ein Verzetteln zu vermeiden, werden die Anforderungen nach dem MoSCoW-Prinzip strukturiert. Dadurch wird sichergestellt, dass die verpflichtenden Grundanforderungen für das Web-Entwicklungsprojekt zuerst erfüllt sind.

### **Must-Have (Kernfunktionalität & Vorlesungsanforderungen)**

- **Client (Flutter Web-App):**
    - Formular zur manuellen Erfassung von Ausgaben (Betrag, Datum, Kategorie, Titel).
    - Dashboard-Ansicht (z. B. als Pie-Chart) zur Visualisierung der monatlichen Ausgaben nach Kategorien.
    - Historien-Ansicht zur Übersicht aller erfassten Ausgaben.
- **Server (Dart Backend):**
    - REST-API (via OpenAPI spezifiziert) zur Erfassung und Verwaltung von Ausgaben.
    - Persistente Speicherung der Ausgaben in einer angebundenen Datenbank.
    - Bereitstellung aggregierter Daten für das Client-Dashboard.

### **Should-Have (KI-Integration & Haupt-Feature)**

- **KI-Klassifizierung:**
    - Minimalistisches UI mit einem zentralen Text-Eingabefeld (Chat-ähnlich) für natürliche Sprache.
    - Server-Middleware zur Kommunikation mit der OpenAI-API (`gpt-6-luna`), die Freitext in strukturiertes JSON (Betrag, Datum, Kategorie, Titel) umwandelt.
    - Möglichkeit zur manuellen Überprüfung und Korrektur der von der KI getätigten Einträge in der Historien-Ansicht.
- **Dokumentation:**
    - Dokumentation der KI-Nutzung während der Entwicklung im **AI Engineering Journal**.

### **Could-Have (Qualitätssicherung & Optimierungen)**

- **Erweiterte Qualitätssicherung:**
    - Automatische Tests (Unit-Tests für die KI-Antwort-Formatierung, Mocking der OpenAI-API).
    - Einsatz von statischer Code-Analyse.
- **Deployment & Schnittstellen:**
    - Containerisierung und Bereitstellung via Docker.

## **4. Technologien**

- **Frontend:** Flutter (Web) mit Charts-Bibliothek (z. B. `fl_chart`)
- **Backend:** Dart (`shelf`, `shelf_router`)
- **API-Spezifikation:** OpenAPI / Swagger
- **KI-Integration:** OpenAI API (`gpt-6-luna`)
- **Datenbank:** SQLite oder PostgreSQL
- **Deployment:** Docker

## **5. Lokale Ausführung**

Die App besteht aus **zwei Prozessen**, die gleichzeitig laufen müssen — jeder in
einem eigenen Terminal. Das Backend muss **zuerst** gestartet werden, da der
Client beim Start sofort `GET /expenses` aufruft.

> **Hinweis:** Falls `dart` / `flutter` nicht im `PATH` liegen, den Terminals den
> Flutter-SDK-Pfad voranstellen:
> - `flutter`: `dependencies/flutter/bin`
> - `dart`:    `dependencies/flutter/bin/cache/dart-sdk/bin`

### Terminal 1 — Backend (Dart Server)

```bash
cd server_app
dart run bin/server.dart
```

Warten auf: `Server running on http://0.0.0.0:8082`. Terminal offen lassen.

### Terminal 2 — Frontend (Flutter Web)

```bash
cd flutter_application
flutter run -d chrome
```

Der Client erwartet das Backend unter `http://localhost:8082` (siehe
`flutter_application/lib/main.dart`).

### Schnelltest (optional)

Sobald der Server läuft, in einem weiteren Terminal:

```bash
curl http://localhost:8082/expenses
```

Gibt `[]` oder ein JSON-Array zurück — bestätigt, dass das Backend erreichbar ist.

### Fehlerbehebung

- **`:8082/expenses … net::ERR_CONNECTION_REFUSED`** im Browser: Das Backend
  läuft nicht. Erst den Server starten, dann im Client auf *Refresh* klicken.
- **Port 8082 belegt** (von einem alten Lauf): `lsof -ti:8082 | xargs kill`.

## **6. Tests & Statische Analyse**

```bash
# Server (von server_app/)
dart test
dart analyze

# Client (von flutter_application/)
flutter test
flutter analyze
```