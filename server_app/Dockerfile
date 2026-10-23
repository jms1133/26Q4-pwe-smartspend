FROM dart:stable AS build

WORKDIR /app

# 1. Quellcode von openapi kopieren
COPY openapi/ ./openapi/

# 2. pubspec-Dateien von server_app kopieren
COPY server_app/pubspec.* ./server_app/

# 3. In das server_app Verzeichnis wechseln und Abhängigkeiten auflösen
WORKDIR /app/server_app
RUN dart pub get

# 4. Restlichen Quellcode von server_app kopieren
COPY server_app/ .

# 5. Lokalen Mac-Cache löschen & Abhängigkeiten im Container sauber auflösen
RUN rm -rf .dart_tool
RUN dart pub get

# 6. AOT-Kompilierung ausführen
RUN dart compile exe bin/server.dart -o bin/server

# Minimales Production-Image
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server_app/bin/server /app/bin/server

EXPOSE 8081
CMD ["/app/bin/server"]