# DynamicNotch

Eine Dynamic Island für die Mac-Notch: Maus an die Notch, und sie klappt auf.
Auf Macs **ohne** Notch wird automatisch eine virtuelle Notch oben in der Bildschirmmitte gezeichnet.

## Funktionen (Version 3.0)

Die Notch hat jetzt 8 Bereiche (Leiste unten, einzeln ausblendbar, Wechsel auch per Zwei-Finger-Wischen):

- **Übersicht:** Uhr, Datum, Akku, **Wetter** (Ort in den Einstellungen, Open-Meteo ohne Konto), nächste 3 Termine mit Countdown, **„Meeting beitreten"-Knopf** für Zoom/Meet/Teams/Webex/FaceTime, Pomodoro mit Fortschrittsbalken und „Phase überspringen"
- **Medien:** Spotify & Apple Music mit Cover, **Farbe passend zum Cover**, Spulen, Steuerung, **Lautstärkeregler**, Klick aufs Cover öffnet den Player
- **Timer (neu):** Kurzzeitwecker mit Ring und Schnellwahl (1 m … 1 h, +1 Min, Pause), **Stoppuhr mit Runden**; läuft live in der eingeklappten Notch mit Fortschrittslinie
- **Werkzeuge:** 12 Schnellaktionen – Screenshot, Farbwähler, Koffein (mit Zeitlimit per Rechtsklick), Dunkelmodus, **Sperren**, Display aus, **Ruhezustand**, Bildschirmschoner, **Mikrofon stumm**, **WLAN an/aus**, **Schreibtisch-Icons ausblenden**, **versteckte Dateien zeigen**; dazu **Taschenrechner** (Enter kopiert das Ergebnis) und Notizblock
- **Zwischenablage:** Verlauf mit **Suche**, **Anheften** (Angeheftetes bleibt gespeichert), Rechtsklick: Einfügen, Link öffnen, Entfernen; optional fügt ein Klick direkt in die vordere App ein
- **Ablage & Downloads:** Drag & Drop Shelf (**bleibt nach Neustart erhalten**), AirDrop, **ZIP auf dem Schreibtisch**, Quick Look, Pfad kopieren; **Downloads-Ansicht** mit laufenden (Safari, Chrome, Firefox …) und letzten Downloads
- **System:** CPU-Verlauf, RAM, **SSD-Belegung**, Netzwerk, **Laufzeit**, **Akku-Zustand und Ladezyklen**
- **Einstellungen:** Schnellschalter, Update-Prüfung
- **Live-Anzeigen in der eingeklappten Notch:** Timer, Pomodoro, Stoppuhr, Downloads, Musik mit Equalizer in Coverfarbe
- **Hinweise:** Lautstärke, Helligkeit, Fokus, Sperrbildschirm, Netzteil, Akku niedrig, Termine, Pomodoro, **Timer fertig**, **Download fertig**, **Bluetooth-Geräte (AirPods, Tastatur, Maus) verbunden/getrennt**, **Update verfügbar**
- **Im Vollbild automatisch ausgeblendet** (Videos, Spiele, Präsentationen), optionaler **Umriss** um die Notch, 10 Akzentfarben
- **Einstellungsfenster** mit neuem Bereich „Widgets", Bereiche ein-/ausblenden, **Einstellungen exportieren/importieren**, **Update-Prüfung** über GitHub-Releases
- **Pin:** Notch offen halten (Stecknadel oder `⌃⌥N`), Rechtsklick auf die Notch: Timer starten, Koffein, Updates, Einstellungen
- **Funktionstasten in der Notch:** F1/F2 Helligkeit, F3 Mission Control, F4 Spotlight/Launchpad, F5 Diktieren, F6 Fokus,
F7/F8/F9 Zurück/Wiedergabe/Vor, F10 Stumm, F11/F12 Leiser/Lauter

### Behoben in 3.0
- Spotify/Musik wurden nach dem Beenden durch die Abfrage wieder gestartet
- Pomodoro lief nach dem Ruhezustand falsch (rechnet jetzt mit Enddatum)
- Timer/Uhr blieben stehen, solange ein Menü offen war
- Koffein konnte doppelt aktiviert werden und blieb dann hängen
- Macs ohne Akku zeigten „100 %"
- `⌃⌥N` funktionierte nicht, wenn das Einstellungsfenster vorne war
- Hover öffnete die Notch auch auf dem Sperrbildschirm
- Uhr erzeugte jede Sekunde neue Datumsformatierer (unnötige CPU-Last)

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
