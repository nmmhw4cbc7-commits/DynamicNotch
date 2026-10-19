# DynamicNotch

Eine Dynamic Island für die Mac-Notch: Maus an die Notch, und sie klappt auf.
Auf Macs **ohne** Notch wird automatisch eine virtuelle Notch oben in der Bildschirmmitte gezeichnet.

## Funktionen
- Uhr, Akkustand, nächster Kalendertermin (Kalenderzugriff erlauben)
- Pomodoro-Timer (25/5), File Shelf (Drag & Drop)
- **Lautstärke- und Helligkeits-Animation** direkt in der Notch
- **Fokus-Anzeige** (Nicht stören, Arbeit, Schlafen …)
- **Sperrbildschirm:** weißes Schloss mit leicht weißem Rand, beim Entsperren kurz das offene Schloss
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
- Datenschutz: Für F3–F6 sieht die App Tastendrücke, reagiert aber nur auf diese Sondertasten und speichert nichts (siehe `Sources/main.swift`).
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
