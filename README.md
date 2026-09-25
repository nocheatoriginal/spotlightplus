# Spotlight Plus

Native macOS-Menüleisten-App mit einer Favoritenleiste neben Apples Spotlight. Entwickelt auf macOS 26, Mindestversion macOS 14. Keine externen Pakete, keine Netzwerkzugriffe.

## Starten

1. `bash scripts/build.sh` baut `build/Spotlight Plus.app` und prüft die Tastaturregeln.
2. Die App im Finder öffnen. Für dauerhafte Nutzung vorher an einen festen Ort verschieben, beispielsweise `~/Applications`.
3. Unter **Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen** Spotlight Plus erlauben. Die App benötigt diese Freigabe für Fenstererkennung und das Abfangen der Favoritenkürzel. Falls macOS die App nach der Freigabe nicht aktiviert, einmal beenden und erneut öffnen.
4. Über **App hinzufügen** bis zu neun Apps wählen und mit den Pfeilen sortieren.
5. Spotlight wie gewohnt öffnen. Bei sichtbarem Spotlight startet ⌘1 die erste App, ⌘2 die zweite usw. Die Leiste lässt sich auch anklicken.

Die Einstellungen sind über das Lupensymbol in der Menüleiste erreichbar. Zum automatischen Start kann die App in macOS unter **Allgemein → Anmeldeobjekte** hinzugefügt werden.

## Verhalten

- Favoriten und Reihenfolge werden lokal in UserDefaults gespeichert.
- Nur belegte Plätze werden umgebogen. Nicht belegte Ziffern behalten Apples Verhalten.
- Umschalt-, Wahl- und Control-Kombinationen bleiben unverändert.
- Die Buttons Apps, Dateien, Aktionen und Zwischenablage senden die originalen ⌘1–⌘4 direkt an Spotlight. Eigene Ereignisse werden markiert, damit sie nicht als Favoritenkürzel abgefangen werden.
- Die Leiste nimmt keinen Tastaturfokus an: Tippen bleibt in Spotlight möglich.
- Die Sichtbarkeit wird über Besitzer, ID, Transparenz und Geometrie sichtbarer Systemfenster überprüft. Die Prüfung läuft seriell im Hintergrund (bis zu 30-mal pro Sekunde bei offenem Spotlight, etwa 10-mal im Leerlauf); es gibt keine wartenden Accessibility-Fensterabfragen. Fensterinhalte und Tastatureingaben werden nicht gespeichert.
- Zum vollständigen Abschalten genügt **Spotlight Plus beenden**. Es werden keine Systemeinstellungen oder Spotlight-Dateien verändert.

## Technische Grenze

Apple stellt keine öffentliche Schnittstelle zum Einbetten beliebiger Bedienelemente in Spotlight bereit. Diese App verwendet deshalb ein separates transparentes NSPanel, Accessibility und einen CGEvent-Tap. Die vier Kategorie-Buttons setzen die vom Nutzer beschriebenen Spotlight-Tastenkürzel voraus. Auf älteren macOS-Versionen sind möglicherweise nicht alle Kategorien vorhanden.

Die Erkennung der Spotlight-Fenster und die Zustellung synthetischer Kategorie-Tastenkürzel müssen auf der jeweiligen macOS-Version praktisch überprüft werden. Wenn Spotlight kein passendes sichtbares Systemfenster meldet, bleibt die Erweiterung inaktiv. Es wird keine Bildschirmaufnahmeberechtigung angefordert; die Fensterliste verwendet nur Besitzer und Geometrie.

Lokale Builds werden ad hoc signiert und sind nicht notarisiert. Nach einem Neubau kann eine erneute Freigabe in Bedienungshilfen nötig sein. Für eine verteilbare Version ist eine Developer-ID-Signatur sinnvoll.

## Prüfung

Der Build führt zusätzlich fünf Platzierungsprüfungen (wachsende Ergebnisse, Überlappung, Bildschirmränder, versetzte und schmale Displays) aus. Außerdem führt er 39 Checks für Ziffernzuordnung, unsichtbares Spotlight, unbelegte Plätze, zusätzliche Modifikatoren, normale Zifferneingabe und Caps Lock aus.

Manuelle Integrationsprüfung nach der Freigabe:

- Spotlight öffnen/schließen: Leiste erscheint/verschwindet; Suchtexteingabe funktioniert.
- Vier Apps hinzufügen, umsortieren, App neu starten: Reihenfolge bleibt erhalten.
- ⌘1–⌘4 in Spotlight: zugeordnete App startet bzw. wird aktiviert.
- Alle vier Kategorie-Buttons: ursprünglicher Spotlight-Bereich öffnet sich.
- ⌘1 in Safari/Finder und ⌘⇧1 in Spotlight: keine Favoritenaktion.
- Spotlight auf einem zweiten Display sowie in einem Vollbild-Space öffnen.
- Freigabe entziehen: Leiste und Abfangen bleiben deaktiviert.

Apple-Dokumentation: [Quartz Event Services](https://developer.apple.com/documentation/coregraphics/quartz-event-services), [Core Spotlight](https://developer.apple.com/documentation/corespotlight).

## Version 0.2

- Nativer Liquid-Glass-Hintergrund auf macOS 26 mit 28-Punkt-Rundung, automatischer Hell-/Dunkelanpassung und ohne künstliche weiße Umrandung. Ältere Systeme verwenden Popover-Material.
- Die Leiste sitzt bevorzugt oberhalb des Suchfelds, damit sich wachsende Suchergebnisse nicht auf ihre Position auswirken. Wenn dort der Platz fehlt, bleibt sie unterhalb; die Seite wird pro Öffnung festgelegt. Am Bildschirmrand wird die Position begrenzt.
- Fensterbreite bleibt pro Öffnung konstant. Unveränderte Geometrie löst keine erneute Fensterpositionierung aus.
- Beim Favoritenstart und beim Schließen per ⌘Leertaste wird die Leiste sofort ausgeblendet. Bereits laufende Abfragen dürfen sie danach nicht wieder einblenden. Escape und Mausklicks werden anhand der tatsächlichen Fenstersichtbarkeit erkannt, damit Escape zum Leeren einer Suchanfrage die Leiste nicht fälschlich entfernt.

Nach dem Neubau die laufende App über das Menüleistensymbol beenden und `build/Spotlight Plus.app` erneut öffnen. Falls eine Kopie in Programme verwendet wird, diese zuvor durch den neuen Build ersetzen. Favoriten bleiben erhalten. Der praktische Vergleich mit Spotlight ist nach dem Neustart zu prüfen; automatisierter UI-Zugriff war beim Bau wegen eines Timeouts nicht verfügbar.

## Version 0.2.1 – Overlay erscheint nicht

- Das Einstellungsfenster darf offen bleiben: Es blockiert die Favoritenleiste nicht mehr.
- Eine beim Ausblenden gesperrte Spotlight-Fenster-ID wird spätestens nach 350 ms wieder freigegeben. Schnell wieder geöffnetes Spotlight bleibt dadurch nicht dauerhaft unsichtbar, wenn zwischen zwei Abfragen kein geschlossenes Fenster beobachtet wurde.
- Die Einstellungen zeigen den tatsächlichen Status von Bedienungshilfen, Tastaturzugriff und Spotlight-Erkennung sowie die Version und den Pfad der gestarteten App.
- Fünf weitere Regressionstests prüfen Ausblendung, wiederverwendete Fenster-IDs und schnelles Wiederöffnen (insgesamt 49 Checks).

Bei fehlendem Overlay zuerst sicherstellen, dass Version 0.2.1 läuft. Wenn dort steht, dass macOS keine Freigabe erteilt hat, obwohl ein Eintrag existiert: App beenden, alten Spotlight-Plus-Eintrag in Bedienungshilfen entfernen, exakt die im Fenster angezeigte App erneut hinzufügen und aktivieren, danach neu starten. Das ist nur erforderlich, wenn die Statusanzeige tatsächlich eine fehlende Freigabe meldet.

## Version 0.3 – feste Seite, weniger Rendering-Arbeit

Diese Änderungen ersetzen die frühere Platzierung und Liquid-Glass-Darstellung:

- Die kompakte Favoritenleiste sitzt ausschließlich oberhalb des Spotlight-Suchfelds mit 8 Punkten Abstand. Es gibt keinen Seitenwechsel nach unten. Reicht der Platz am oberen Bildschirmrand nicht, bleibt sie verborgen und die Einstellungen melden den fehlenden Platz; das Suchfeld dann etwas nach unten verschieben.
- Nur Oberkante, X-Position und Breite sind für die Platzierung relevant. Die Höhe der Suchergebnisse wird ignoriert. Erst nach 120 ms stabiler Geometrie wird eingeblendet bzw. eine neue Position übernommen; es gibt keine Fensteranimation und kein erzwungenes synchrones Neuzeichnen.
- Eine native titellose Darstellung eines NSPanel übernimmt die Systemrundung. NSVisualEffectView mit Popover-Material ersetzt NSGlassEffectView. Es gibt keine selbst gezeichnete Umrandung, Glasbrechung oder feste Farbtönung. Icons und Favoriten bleiben erhalten.
- Bei sichtbarem Spotlight wird nur die bekannte Fenster-ID abgefragt (etwa alle 60 ms), die gesamte Fensterliste nur bei der Suche nach einem Fenster (etwa alle 180 ms). Dies reduziert die Abfragearbeit; eine CPU-/GPU-Messung und ein visueller Vergleich auf dem Benutzergerät stehen noch aus.
- 54 automatische Checks einschließlich neuer Tests für Animationen, Höhenänderungen und tatsächlich verschobene Suchfelder.

Die laufende Version muss beendet und der neue Build geöffnet werden. Der automatische Mac-Oberflächenzugriff war beim Test weiterhin durch einen Timeout blockiert; daher ist die Darstellung nicht als pixelgleich mit Spotlight oder als auf dem Gerät gemessen ruckelfrei verifiziert.

## Version 0.4 – feste Leiste unter der Menüleiste

Ersetzt die an Spotlight angeheftete Positionierung vollständig:

- Mittig auf dem Bildschirm, auf dem Spotlight beim Öffnen erkannt wird: 10 Punkte unterhalb der nutzbaren oberen Bildschirmkante, maximal 1040 Punkte breit, 148 Punkte hoch. Auf schmaleren Displays bleiben seitlich jeweils 16 Punkte frei.
- Der Bildschirm bleibt bis zum Schließen von Spotlight festgelegt. Suchergebnisse, verschobenes Spotlight und Änderungen seiner Größe bewegen die Leiste nicht. Bei Abziehen des Displays wird ein verfügbarer Bildschirm gewählt.
- Ein rahmenloses Panel vermeidet Titelbereich-/Safe-Area-Abzüge. Zusätzliche Höhe und Innenabstände geben der unteren Buttonzeile Platz.
- System-Menümaterial statt Popover-Material, kontinuierliche 16-Punkt-Rundung, keine Glasbrechung. Der tatsächliche Farbabgleich mit Spotlight ist noch nicht visuell verifiziert.
- Favoriten, ihre Reihenfolge und die Spotlight-Kategoriebuttons bleiben bestehen. Die Leiste erscheint weiterhin nur bei sichtbarem Spotlight.

Build und 49 automatische Prüfungen bestehen. Die fünf Positionstests prüfen Bildschirmgrenzen, Zentrierung, oberen Abstand, versetzte und schmale Displays. Diese Tests ersetzen keinen visuellen Test des Layouts. Zum Ausprobieren die laufende App beenden und den Build mit Version 0.4.0 öffnen.

## Version 0.5 – ereignisgestütztes Ein-/Ausblenden, klares Glas

- ⌘Leertaste, Escape/Return bei offenem Spotlight, relevante Mausklicks, App-Aktivierungen und unterstützte Spotlight-Accessibility-Benachrichtigungen stoßen sofortige Prüfungen an. Weitere Prüfungen folgen nach 16, 32, 64, 100, 160 und 240 ms, weil Spotlight sein Fenster erst nach dem auslösenden Ereignis anlegt. Diese Zahlen sind geplante Prüfzeitpunkte, keine gemessenen Darstellungszeiten.
- Neue Ereignisse ersetzen ausstehende Prüfserien. Es läuft weiterhin höchstens eine Hintergrundabfrage zugleich. Die reguläre Abfrage bleibt als Rückfall bestehen, falls Spotlight keine passende AX-Benachrichtigung sendet.
- ⌘Leertaste zum Schließen und App-Starts blenden direkt aus; Escape/Return und Mausklicks prüfen zuerst die tatsächliche Sichtbarkeit, damit das Leeren einer Suche oder ein Klick auf die Favoritenleiste diese nicht fälschlich schließt.
- Der Inhalt wird bereits vor dem ersten Einblenden im versteckten Fenster angeordnet.
- Auf macOS 26 wird NSGlassEffectView mit dem Stil `clear` verwendet, ohne eigene Farbtönung. Symbole und Text werden nicht durch eine Fenster-Deckkraft reduziert. Auf älteren Systemen dient `underWindowBackground` als Rückfall.

Die feste Position, Breite und Inhaltshöhe aus Version 0.4 bleiben bestehen. Build und die bestehenden 49 Logikprüfungen bestehen. Die neuen AX-Ereignisse und tatsächliche Anzeigezeiten benötigen einen Integrationstest auf dem Mac; die automatischen Logiktests belegen keine gemessene Latenz oder Farbgleichheit. Zum Testen die laufende Version beenden und Version 0.5.0 öffnen.

## Version 0.5.1 – Dunkelblau aus dem Referenzbild

Die Glastönung auf macOS 26 verwendet nun ein Dunkelblau, abgeleitet aus 42 leeren Innenflächen-Pixeln des vom Nutzer bereitgestellten Spotlight-Screenshots (nach sRGB-Konvertierung im Mittel RGB 34/54/105, #223669). Der native klare Glaseffekt erhält diese Tönung mit Alpha 0,90. Das Panel verwendet Dark Aqua für lesbare helle Beschriftungen. Das Einstellungsfenster folgt weiterhin dem Systemdesign.

Dies ist eine Farbreferenz, keine Garantie für pixelgleiche Ausgabe: Der native Glaseffekt verrechnet Tönung und Desktop-Hintergrund. Position, Abmessungen, Icons, Inhalte und Ereignissteuerung bleiben unverändert. Auf Systemen vor macOS 26 bleibt das bisherige Ersatzmaterial bestehen, nun mit dunkler Panel-Darstellung.

## Version 0.5.2 – direkt gezeichneter Spotlight-Hintergrund

Die System-Glastönung aus 0.5.1 hat beim Nutzer nicht die gewünschte dunkle Fläche erzeugt. NSGlassEffectView und dessen Farbverrechnung werden deshalb vollständig aus dem Panel entfernt.

Eine eigene NSView zeichnet einen nahezu deckenden dunkelblauen Verlauf (98 % Alpha) aus den sRGB-Farbproben des neuen Spotlight-Nahbildes: RGB 29/53/109 bis 41/56/102. Eine dunkle Außenkontur und eine dünne blaue Innenkontur entsprechen der Richtung der Referenz. Die Fläche verwendet 24-Punkt-Rundungen. Text und Symbole werden unabhängig vom Hintergrund gezeichnet und bleiben vollständig deckend. Der echte Hintergrund ist jetzt höchstens zu zwei Prozent sichtbar; es wird kein Glas-/Weichzeichnereffekt mehr verwendet.

Die Darstellung ist absichtlich unabhängig von einer Material-Tönung, die macOS aufhellen könnte. Vier neue Tests zeichnen die tatsächliche Hintergrundfunktion in ein Bitmap und prüfen dunkle Farbwerte, hohe Deckkraft, Blauanteil und transparente Ecken. Zusammen mit den 49 bisherigen Prüfungen bestehen 53 Checks. Position, Abmessungen, Favoriten und Ereignissteuerung bleiben unverändert.

Zum Ausprobieren die laufende App beenden und Version 0.5.2 öffnen. Die Version ist in den Einstellungen sichtbar.

## Version 0.6 – adaptive Schreibtischfarbe und App-Icon

Der Hintergrund verwendet jetzt die markante Farbe des auf dem jeweiligen Bildschirm eingestellten Schreibtischbilds. Die App liest dessen von NSWorkspace bereitgestellte Datei lokal und berechnet im Hintergrund ein maximal 64 Pixel großes Vorschaubild. Eine nach Fläche und Sättigung gewichtete Farbverteilung bestimmt den dominanten Farbton. Der Farbton wird für Hintergrund und Kontur übernommen; die Helligkeit bleibt bewusst niedrig. Einfarbige graue/weiße Hintergründe ergeben eine neutrale dunkle Leiste. Die Opazität bleibt 98 Prozent.

- Keine Bildschirmaufnahme, keine zusätzlichen Berechtigungen, kein Netzwerkzugriff.
- Die Leiste erscheint sofort mit der zuletzt ermittelten Farbe; die Bildanalyse blockiert nicht das Öffnen.
- Ergebnisse werden nach Dateipfad und Änderungsdatum zwischengespeichert. Bei sichtbarer Leiste wird höchstens alle drei Sekunden geprüft, ob sich das hinterlegte Bild geändert hat.
- Falls macOS kein lesbares Bild liefert (beispielsweise manche Video-/dynamischen Hintergründe), bleibt ein dunkles Blau als Ersatz. Die Auswahl analysiert die gesamte Bilddatei, nicht den sichtbaren Ausschnitt oder die aktuelle Videoframe. Sie ist eine eigene Annäherung an den gewünschten Effekt, keine Nachbildung bekannter Spotlight-Interna.

Das App-Paket enthält nun `AppIcon.icns` mit zehn Größen bis 1024 Pixel. Das Motiv ist eine helle Lupe mit Plus auf einer dunkelblauen Kachel. Die auflösungsunabhängige Zeichenquelle liegt in `scripts/make-icon.swift`, die PNG-Vorschau in `Resources/AppIcon.png`. Neu erzeugen mit:

```sh
xcrun swift -module-cache-path build/module-cache scripts/make-icon.swift
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
bash scripts/build.sh
```

Der Build übernimmt das Icon aus Resources ins App-Paket und referenziert es über CFBundleIconFile. Der reine Menüleistenknopf bleibt ein gut lesbares monochromes System-Symbol.

60 Prüfungen bestehen: 49 Verhaltenstests, vier Prüfungen der gerenderten Fläche und sieben Tests zur Farbauswahl inklusive echter PNG-Thumbnail-Dekodierung. Die tatsächliche Wallpaper-Dateizuordnung und der Wechsel dynamischer Hintergründe müssen auf dem Nutzergerät geprüft werden. Zum Ausprobieren die laufende App beenden und Version 0.6.0 öffnen.

## Version 0.6.1 – feste Wunschfarbe und Icon-Anzeige

Die adaptive Wallpaper-Auswertung ist entfernt. Der Hintergrund zeichnet ausschließlich sRGB #0e1145 mit 90 Prozent Deckkraft über einem dunklen NSVisualEffectView (`underWindowBackground`, `behindWindow`). So bleibt der Farbton stabil und der Hintergrund scheint weichgezeichnet durch. Aufgrund der Transparenz entspricht das zusammengesetzte Bild nicht überall exakt dem reinen Hex-Farbwert. Position, Höhe und schnelle Ereignissteuerung bleiben erhalten.

Das App-Icon hat einen neuen Ressourcennamen `SpotlightPlusIcon-v2.icns` in CFBundleIconFile, um alte Ressourcenzuordnungen zu vermeiden. Beim Start wird es zusätzlich an NSApplication.applicationIconImage übergeben; auch die Einstellungen zeigen es nun an. Der Menüleistenknopf erhält ein eigenes, monochromes Lupe-Plus-Motiv als Template-Image. Die App bleibt eine Menüleisten-App ohne dauerhaftes Dock-Symbol.

54 reguläre Prüfungen bestehen, darunter die gerenderte Wunschfarbe und ihre Teiltransparenz. Zwei weitere Icon-Prüfungen bestehen außerhalb der Sandbox. Diese lassen sich optional mit `--self-test --check-icons` ausführen; Apples ICNS-Dekoder benötigte hier Zugriff auf die Desktop-Sitzung. Die regulären Build-Tests bleiben ohne diesen Zugriff lauffähig.

Nach dem Beenden der bisherigen App Version 0.6.1 öffnen. Bei einer separaten Kopie unter Programme muss diese Kopie aktualisiert werden; der neue Build liegt weiterhin im build-Ordner.

## Version 0.6.2 – letzte Materialänderung zurückgenommen

Der zusätzliche NSVisualEffectView-Weichzeichner aus 0.6.1 ist wieder entfernt. Das Panel verwendet wieder ausschließlich die direkt gezeichnete dunkle Fläche. #0e1145 bleibt als Grundton bei 98 Prozent Deckkraft mit der bisherigen dezenten Kontur; Position, Größe, Inhalt und Ereignissteuerung bleiben erhalten.

Das App-Bundle wurde mit LaunchServices neu registriert. Anschließend wurde das von NSWorkspace für exakt `build/Spotlight Plus.app` aufgelöste Dateisymbol ausgelesen und als `build/finder-icon-check.png` geprüft: macOS liefert das korrekte blaue Lupe-Plus-Icon. Damit ist die Icon-Zuordnung dieser App-Datei bestätigt, nicht nur das Dekodieren ihrer Icon-Ressource. Eine möglicherweise separat installierte Kopie muss gesondert aktualisiert werden.

Künftige Builds aktualisieren zusätzlich den Änderungszeitpunkt des äußeren App-Verzeichnisses, damit Änderungen am bestehenden Paket für Metadatenleser erkennbar sind. 54 reguläre Prüfungen und die Signaturprüfung bestehen.

## Version 0.6.3 – weniger Text, mehr Transparenz, feine Kontur

Der Slogan unter dem App-Namen und der Erklärungstext unterhalb der Versionsangabe sind entfernt. Der Overlay-Grundton bleibt #0e1145; seine Deckkraft ist von 98 auf 84 Prozent reduziert, sodass der Hintergrund deutlicher durchscheint. Es wird kein zusätzlicher Weichzeichner eingeführt. Die bisherige doppelte Umrandung ist durch eine einzelne dezente 0,5-Punkt-Kontur ersetzt. App-Icon, Position und Ereignissteuerung bleiben erhalten. Build, Signaturprüfung und 54 reguläre Prüfungen bestehen.

## Version 0.6.4 – Alacritty-Hintergrundfarbe

Der Overlay-Grundton ist jetzt #1d1530 (RGB 29/21/48), entsprechend `[colors.primary].background` in der vom Nutzer verwendeten `~/.config/alacritty/custom.toml`. Diese Datei wird von `alacritty.toml` importiert. Die Farbe wurde einmalig übernommen; es gibt keine laufende Kopplung an Alacritty. 84 Prozent Deckkraft, feine Kontur, Icon und Verhalten bleiben unverändert. Der zusammengesetzte Farbeindruck kann wegen der Transparenz vom Terminal abweichen. Build, Signaturprüfung und 54 reguläre Prüfungen bestehen.

## Version 0.6.5 – Breite nach Anzahl der Favoriten

Die Mindestbreite beträgt 480 Punkte, damit die vier Kategoriebuttons und Einstellungen Platz behalten. Darüber berechnet sich die Breite aus 80 Punkten pro App, 8 Punkten Abstand und je 20 Punkten Innenabstand. Beispielsweise sind es 480 Punkte für eine bis fünf Apps, 560 für sechs und 824 für neun Apps. Die App-Gruppe bleibt mittig mit kompakten Abständen; wenige Apps werden nicht über die ganze Fensterbreite verteilt. Auf schmaleren Displays werden Fenster und Kacheln begrenzt, damit sie hineinpassen.

Die obere Kante und horizontale Zentrierung bleiben beim Größenwechsel erhalten. Farbe, Transparenz, Kontur und Icon sind unverändert. 59 Prüfungen bestehen, einschließlich fünf neuer Tests für Mindestbreite, Wachstum, Platz für neun Apps und feste Verankerung beim Größenwechsel.
