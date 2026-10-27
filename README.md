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