# DynamicNotch

Eine Dynamic Island für die Mac-Notch: Maus an die Notch, und sie klappt auf.
Auf Macs **ohne** Notch wird automatisch eine virtuelle Notch oben in der Bildschirmmitte gezeichnet.

## Funktionen

Die Notch hat jetzt 7 Bereiche (Leiste unten im aufgeklappten Panel):

- **Übersicht:** Uhr, Datum, Akku, die nächsten 3 Termine mit Countdown, Pomodoro (Dauer einstellbar, zählt erledigte Runden)
- **Medien:** Spotify & Apple Music mit Cover, Titel, Fortschritt (zum Spulen klicken/ziehen), Play/Pause/Vor/Zurück. Live-Anzeige mit Cover und Equalizer auch in der eingeklappten Notch
- **Werkzeuge:** Screenshot in die Zwischenablage, Farbwähler (Hex wird kopiert), Koffein (Mac wach halten), Dunkelmodus, Display aus, Bildschirmschoner, Notizblock
- **Zwischenablage:** Verlauf der letzten 25 Texte (nur im Speicher, Passwortmanager-Einträge werden ignoriert), Klick kopiert erneut
- **Ablage:** Drag & Drop Shelf, per AirDrop senden, im Finder zeigen, wieder herausziehen
- **System:** CPU mit Verlaufsgrafik, Arbeitsspeicher, Netzwerk-Geschwindigkeit
- **Einstellungen:** Hover oder Klick zum Öffnen, Haptik, Hinweise ein/aus, Autostart, Timer-Dauer
- **Lautstärke- und Helligkeits-Animation**, **Fokus-Anzeige**, **Sperrbildschirm-Schloss** (wie bisher)
- **Hinweise in der Notch:** Netzteil verbunden/getrennt, Akku niedrig, Termin in 5 Minuten, Pomodoro fertig
- **Eigenes Einstellungsfenster „DynamicNotch Einstellungen“** (Menüleisten-Symbol oder Rechtsklick auf die Notch → Einstellungen…): Öffnen/Schließen mit Verzögerung, Start-Bereich, Akzentfarbe, 12/24-h-Uhr, Sekunden, Datum, Anzeigedauer, Musik-Quellen einzeln, Equalizer/Cover, Pomodoro mit langer Pause, Auto-Start und Klang, Anzeigen einzeln abschaltbar, Akku-Schwelle, Termin-Vorlauf, Zwischenablage-Limit, Reset
- **Pin:** Notch offen halten (Stecknadel oder `⌃⌥N`)
- **Funktionstasten in der Notch:** F1/F2 Helligkeit, F3 Mission Control, F4 Spotlight/Launchpad, F5 Diktieren, F6 Fokus,
F7/F8/F9 Zurück/Wiedergabe/Vor, F10 Stumm, F11/F12 Leiser/Lauter (Anzeige je nach Tastatur-Modell)
- Rechtsklick auf die Notch → Beenden (zeigt auch, ob der Tastenabfang aktiv ist)

## Hinweise
- **Fokus** braucht „Voller Festplattenzugriff": Systemeinstellungen → Datenschutz & Sicherheit → Voller Festplattenzugriff → DynamicNotch hinzufügen.
- **Sperrbildschirm-Anzeige** und **Helligkeit** nutzen private macOS-Schnittstellen und können sich mit macOS-Updates ändern.
  Sperrbildschirm-Overlay abschalten: `defaults write local.dynamicnotch lockScreenOverlay -bool false`
- **System-Anzeige ausblenden:** Lautstärke-, Helligkeits- und Stumm-Tasten werden von DynamicNotch selbst verarbeitet,
  die normale macOS-Anzeige erscheint dann nicht mehr. Dafür unter Systemeinstellungen → Datenschutz & Sicherheit → **Bedienungshilfen**
  DynamicNotch aktivieren (die App fragt beim Start danach). Nach einem neuen Build ggf. mit „–" entfernen und neu hinzufügen.
  Mit ⇧⌥ zusammen geht es in Viertelschritten.
- Datenschutz: Für F3–F6 sieht die App Tastendrücke, reagiert aber nur auf diese Sondertasten und speichert nichts (siehe `Sources/Hardware.swift`).
- **Medien** brauchen beim ersten Mal die Freigabe „Automation“ (Spotify bzw. Musik).
- Fehlersuche: Log unter `/tmp/dynamicnotch.log`.

## Installation
1. `DynamicNotch.dmg` aus den [Releases](../../releases) laden
2. App nach „Programme" ziehen
3. Beim ersten Start: **Rechtsklick → Öffnen** (nicht notarisiert), oder `xattr -cr /Applications/DynamicNotch.app`

Autostart: Systemeinstellungen → Allgemein → Anmeldeobjekte.

## Selbst bauen
Voraussetzung: macOS 14+, Xcode.

    bash build.sh

## Lizenz
MIT
