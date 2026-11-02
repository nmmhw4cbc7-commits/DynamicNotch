import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Eigenes Einstellungsfenster "DynamicNotch Einstellungen"

enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "DynamicNotch Einstellungen"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsRoot())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsRoot: View {
    // Allgemein
    @AppStorage("hoverOpen") private var hoverOpen = true
    @AppStorage("openDelayMs") private var openDelay = 0
    @AppStorage("closeDelayMs") private var closeDelay = 250
    @AppStorage("haptic") private var haptic = true
    @AppStorage("rememberTab") private var rememberTab = true
    @AppStorage("defaultTab") private var defaultTab = "home"
    @AppStorage("hotkeyOn") private var hotkeyOn = true
    @AppStorage("showMenuBarIcon") private var menuIcon = true
    // Darstellung
    @AppStorage("accent") private var accent = "orange"
    @AppStorage("clock24") private var clock24 = true
    @AppStorage("showSeconds") private var showSeconds = false
    @AppStorage("showDate") private var showDate = true
    @AppStorage("hudSeconds") private var hudSeconds = 1.6
    // Medien
    @AppStorage("showMediaInNotch") private var showMedia = true
    @AppStorage("spotifyOn") private var spotifyOn = true
    @AppStorage("musicOn") private var musicOn = true
    @AppStorage("showEqualizer") private var showEq = true
    @AppStorage("artInNotch") private var artInNotch = true
    // Timer
    @AppStorage("workMin") private var workMin = 25
    @AppStorage("breakMin") private var breakMin = 5
    @AppStorage("longBreakMin") private var longBreakMin = 15
    @AppStorage("longBreakEvery") private var longEvery = 4
    @AppStorage("autoStartBreak") private var autoBreak = false
    @AppStorage("autoStartWork") private var autoWork = false
    @AppStorage("timerSound") private var timerSound = true
    @AppStorage("timerSoundName") private var soundName = "Glass"
    // Hinweise
    @AppStorage("hudVolume") private var hudVolume = true
    @AppStorage("hudBrightness") private var hudBrightness = true
    @AppStorage("hudFocus") private var hudFocus = true
    @AppStorage("notifyBattery") private var notifyBattery = true
    @AppStorage("lowBattery") private var lowBattery = 20
    @AppStorage("notifyEvents") private var notifyEvents = true
    @AppStorage("eventLead") private var eventLead = 5
    // Datenschutz
    @AppStorage("clipboardEnabled") private var clipEnabled = true
    @AppStorage("clipMax") private var clipMax = 25
    // Erweitert
    @AppStorage("lockScreenOverlay") private var lockOverlay = true
    @AppStorage("captureKeys") private var captureKeys = true
    // Neu in 3.0
    @AppStorage("hiddenTabs") private var hiddenTabs = ""
    @AppStorage("notchOutline") private var outline = false
    @AppStorage("hideInFullscreen") private var hideFullscreen = true
    @AppStorage("swipeTabs") private var swipeTabs = true
    @AppStorage("watchDownloads") private var watchDownloads = true
    @AppStorage("notifyDownloads") private var notifyDownloads = true
    @AppStorage("downloadsToShelf") private var downloadsToShelf = false
    @AppStorage("liveDownloads") private var liveDownloads = true
    @AppStorage("liveTimers") private var liveTimers = true
    @AppStorage("weatherOn") private var weatherOn = true
    @AppStorage("weatherCity") private var weatherCity = ""
    @AppStorage("notifyBluetooth") private var notifyBluetooth = true
    @AppStorage("checkUpdates") private var checkUpdates = true
    @AppStorage("welcomeHUD") private var welcomeHUD = true
    @AppStorage("clipPaste") private var clipPaste = false
    @AppStorage("chargeSound") private var chargeSound = false
    @State private var cityDraft = UserDefaults.standard.string(forKey: "weatherCity") ?? ""
    @State private var updateText = ""
    @State private var autostart = SMAppService.mainApp.status == .enabled

    var hiddenSet: Set<String> { Set(hiddenTabs.split(separator: ",").map(String.init)) }

    func tabBinding(_ t: NotchTab) -> Binding<Bool> {
        Binding(get: { !hiddenSet.contains(t.rawValue) }, set: { on in
            var set = hiddenSet
            if on { set.remove(t.rawValue) } else { set.insert(t.rawValue) }
            hiddenTabs = set.sorted().joined(separator: ",")
        })
    }

    func model() -> Model? { (NSApp.delegate as? AppDelegate)?.model }

    var body: some View {
        TabView {
            general.tabItem { Label("Allgemein", systemImage: "gearshape") }
            look.tabItem { Label("Darstellung", systemImage: "paintbrush") }
            widgets.tabItem { Label("Widgets", systemImage: "square.grid.2x2") }
            media.tabItem { Label("Medien", systemImage: "music.note") }
            timer.tabItem { Label("Timer", systemImage: "timer") }
            alerts.tabItem { Label("Hinweise", systemImage: "bell") }
            privacy.tabItem { Label("Datenschutz", systemImage: "hand.raised") }
            advanced.tabItem { Label("Erweitert", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 640, height: 540)
    }

    var general: some View {
        Form {
            Section("Öffnen & Schließen") {
                Toggle("Beim Darüberfahren öffnen (sonst Klick)", isOn: $hoverOpen)
                Stepper("Öffnungsverzögerung: \(openDelay) ms", value: $openDelay, in: 0...1000, step: 50)
                Stepper("Schließverzögerung: \(closeDelay) ms", value: $closeDelay, in: 0...1500, step: 50)
                Toggle("Haptisches Feedback beim Öffnen", isOn: $haptic)
                Toggle("Zuletzt genutzten Bereich merken", isOn: $rememberTab)
                Picker("Start-Bereich", selection: $defaultTab) {
                    ForEach(NotchTab.allCases) { t in Text(t.title).tag(t.rawValue) }
                }.disabled(rememberTab)
                Toggle("Tastenkürzel ⌃⌥N (Notch fixieren)", isOn: $hotkeyOn)
                Toggle("Zwei-Finger-Wischen wechselt den Bereich", isOn: $swipeTabs)
                Toggle("Im Vollbild ausblenden (Videos, Spiele, Präsentationen)", isOn: $hideFullscreen)
            }
            Section("Bereiche in der Notch") {
                ForEach(NotchTab.allCases.filter { $0 != .settings }) { t in
                    Toggle(isOn: tabBinding(t)) { Label(t.title, systemImage: t.icon) }
                }
            }
            Section("System") {
                Toggle("Beim Anmelden starten", isOn: Binding(get: { autostart }, set: { v in
                    do {
                        if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { dlog("Autostart: \(error)") }
                    autostart = SMAppService.mainApp.status == .enabled
                }))
                Toggle("Symbol in der Menüleiste", isOn: $menuIcon)
                Toggle("Begrüßung beim Start", isOn: $welcomeHUD)
            }
        }.formStyle(.grouped)
    }

    var look: some View {
        Form {
            Section("Aussehen") {
                Picker("Akzentfarbe", selection: $accent) {
                    ForEach(accentOptions, id: \.0) { o in Text(o.1).tag(o.0) }
                }
                Toggle("24-Stunden-Uhr", isOn: $clock24)
                Toggle("Sekunden anzeigen", isOn: $showSeconds)
                Toggle("Datum anzeigen", isOn: $showDate)
                Toggle("Umriss um die Notch", isOn: $outline)
            }
            Section("Live-Anzeigen in der eingeklappten Notch") {
                Toggle("Timer und Stoppuhr", isOn: $liveTimers)
                Toggle("Laufende Downloads", isOn: $liveDownloads)
            }
            Section("Anzeigen in der Notch") {
                HStack {
                    Text("Dauer: \(String(format: "%.1f", hudSeconds)) s")
                    Slider(value: $hudSeconds, in: 1...5, step: 0.5)
                }
            }
        }.formStyle(.grouped)
    }

    var widgets: some View {
        Form {
            Section("Wetter (Open-Meteo, ohne Konto)") {
                Toggle("Wetter in der Übersicht", isOn: $weatherOn)
                HStack {
                    TextField("Ort, z. B. Berlin", text: $cityDraft)
                        .onSubmit { saveCity() }
                    Button("Übernehmen") { saveCity() }
                }
                if let t = model()?.weather.temp, let place = model()?.weather.place, !place.isEmpty {
                    Text("Aktuell: \(Int(t.rounded()))° in \(place)").font(.footnote).foregroundColor(.secondary)
                }
            }
            Section("Downloads") {
                Toggle("Downloads-Ordner beobachten", isOn: $watchDownloads)
                Toggle("Hinweis, wenn ein Download fertig ist", isOn: $notifyDownloads)
                Toggle("Fertige Downloads automatisch in die Ablage", isOn: $downloadsToShelf)
            }
            Section("Geräte") {
                Toggle("Bluetooth-Geräte verbunden/getrennt anzeigen (Neustart nötig)", isOn: $notifyBluetooth)
                Toggle("Ton beim Anstecken des Netzteils", isOn: $chargeSound)
            }
            Section("Zwischenablage") {
                Toggle("Klick auf Eintrag fügt direkt ein (braucht Bedienungshilfen)", isOn: $clipPaste)
            }
        }.formStyle(.grouped)
    }

    func saveCity() {
        weatherCity = cityDraft.trimmingCharacters(in: .whitespaces)
        model()?.weather.refresh(force: true)
    }

    var media: some View {
        Form {
            Section("Wiedergabe") {
                Toggle("Musik in der eingeklappten Notch zeigen", isOn: $showMedia)
                Toggle("Cover in der Notch", isOn: $artInNotch)
                Toggle("Equalizer-Animation", isOn: $showEq)
            }
            Section("Quellen") {
                Toggle("Spotify", isOn: $spotifyOn)
                Toggle("Apple Music", isOn: $musicOn)
            }
        }.formStyle(.grouped)
    }

    var timer: some View {
        Form {
            Section("Pomodoro") {
                Stepper("Fokus: \(workMin) Min", value: $workMin, in: 5...120, step: 5)
                Stepper("Kurze Pause: \(breakMin) Min", value: $breakMin, in: 1...30)
                Stepper("Lange Pause: \(longBreakMin) Min", value: $longBreakMin, in: 5...60, step: 5)
                Stepper("Lange Pause nach \(longEvery) Runden", value: $longEvery, in: 2...8)
                Toggle("Pause automatisch starten", isOn: $autoBreak)
                Toggle("Nächste Runde automatisch starten", isOn: $autoWork)
            }
            Section("Ton") {
                Toggle("Ton am Ende", isOn: $timerSound)
                Picker("Klang", selection: $soundName) {
                    ForEach(["Glass", "Ping", "Hero", "Submarine", "Funk", "Pop", "Tink"], id: \.self) { Text($0) }
                }
                Button("Testen") { NSSound(named: NSSound.Name(soundName))?.play() }
            }
        }
        .formStyle(.grouped)
        .onChange(of: workMin) { _, _ in model()?.applyTimerSettings() }
        .onChange(of: breakMin) { _, _ in model()?.applyTimerSettings() }
    }

    var alerts: some View {
        Form {
            Section("Anzeige in der Notch für …") {
                Toggle("Lautstärke", isOn: $hudVolume)
                Toggle("Helligkeit", isOn: $hudBrightness)
                Toggle("Fokus-Modus", isOn: $hudFocus)
            }
            Section("Akku") {
                Toggle("Hinweise (Laden / niedrig)", isOn: $notifyBattery)
                Stepper("Niedrig ab \(lowBattery) %", value: $lowBattery, in: 5...50, step: 5)
            }
            Section("Termine") {
                Toggle("Erinnerung", isOn: $notifyEvents)
                Stepper("\(eventLead) Min vorher", value: $eventLead, in: 1...30)
            }
        }.formStyle(.grouped)
    }

    var privacy: some View {
        Form {
            Section("Zwischenablage") {
                Toggle("Verlauf speichern (nur im Speicher)", isOn: $clipEnabled)
                Stepper("Max. Einträge: \(clipMax)", value: $clipMax, in: 5...50, step: 5)
                Button("Verlauf jetzt löschen") { model()?.clipboard.clear() }
            }
            Section {
                Text("Passwortmanager-Einträge werden nie gespeichert. Nichts wird auf die Festplatte geschrieben.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }.formStyle(.grouped)
    }

    var advanced: some View {
        Form {
            Section("Erweitert") {
                Toggle("Anzeige über dem Sperrbildschirm", isOn: $lockOverlay)
                Toggle("Medientasten abfangen (Neustart nötig)", isOn: $captureKeys)
            }
            Section("Updates") {
                Toggle("Beim Start nach Updates suchen", isOn: $checkUpdates)
                HStack {
                    Button("Jetzt prüfen") {
                        updateText = "Prüfe…"
                        model()?.updater.check { avail in
                            let latest = model()?.updater.latest ?? "?"
                            updateText = avail ? "Version \(latest) ist verfügbar" : "Du hast die neueste Version (\(appVersion))"
                        }
                    }
                    if model()?.updater.available == true {
                        Button("Herunterladen") { model()?.updater.openDownload() }
                    }
                    Text(updateText).font(.footnote).foregroundColor(.secondary)
                }
            }
            Section("Einstellungen sichern") {
                HStack {
                    Button("Exportieren…") { SettingsIO.export() }
                    Button("Importieren…") {
                        if SettingsIO.importFile() {
                            cityDraft = UserDefaults.standard.string(forKey: "weatherCity") ?? ""
                            model()?.applyTimerSettings()
                            model()?.weather.refresh(force: true)
                        }
                    }
                }
            }
            Section("Hilfe") {
                Button("Bedienungshilfen öffnen") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(u)
                    }
                }
                Button("Log öffnen") { NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/dynamicnotch.log")) }
                Button("Alle Einstellungen zurücksetzen") {
                    if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
                    cityDraft = ""
                    model()?.applyTimerSettings()
                }
                Button("DynamicNotch beenden") { NSApp.terminate(nil) }
            }
            Section { Text("DynamicNotch \(appVersion)").font(.footnote).foregroundColor(.secondary) }
        }.formStyle(.grouped)
    }
}
