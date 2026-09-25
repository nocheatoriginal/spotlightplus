# Spotlight Plus

Native macOS-Menüleisten-App mit einer Favoritenleiste neben Apples Spotlight. Entwickelt auf macOS 26, Mindestversion macOS 14. Keine externen Pakete, keine Netzwerkzugriffe.

## Starten

1. `bash scripts/build.sh` baut `build/Spotlight Plus.app` und prüft die Tastaturregeln.
2. Die App im Finder öffnen. Für dauerhafte Nutzung vorher an einen festen Ort verschieben, beispielsweise `~/Applications`.
3. Unter **Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen** Spotlight Plus erlauben. Die App benötigt diese Freigabe für Fenstererkennung und das Abfangen der Favoritenkürzel. Falls macOS die App nach der Freigabe nicht aktiviert, einmal beenden und erneut öffnen.
4. Über **App hinzufügen** bis zu neun Apps wählen und mit den Pfeilen sortieren.
5. Spotlight wie gewohnt öffnen. Bei sichtbarem Spotlight startet ⌘1 die erste App, ⌘2 die zweite usw. Die Leiste lässt sich auch anklicken.

Die Einstellungen sind über das Lupensymbol in der Menüleiste erreichbar. Zum automatischen Start kann die App in macOS unter **Allgemein → Anmeldeobjekte** hinzugefügt werden.