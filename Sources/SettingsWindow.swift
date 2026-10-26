import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Eigenes Einstellungsfenster "DynamicNotch Einstellungen"

enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 480),
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
    @State private var autostart = SMAppService.mainApp.status == .enabled

    func model() -> Model? { (NSApp.delegate as? AppDelegate)?.model }

    var body: some View {
        TabView {
            general.tabItem { Label("Allgemein", systemImage: "gearshape") }
            look.tabItem { Label("Darstellung", systemImage: "paintbrush") }
            media.tabItem { Label("Medien", systemImage: "music.note") }
            timer.tabItem { Label("Timer", systemImage: "timer") }
            alerts.tabItem { Label("Hinweise", systemImage: "bell") }
            privacy.tabItem { Label("Datenschutz", systemImage: "hand.raised") }
            advanced.tabItem { Label("Erweitert", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 580, height: 480)
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
            }
            Section("System") {
                Toggle("Beim Anmelden starten", isOn: Binding(get: { autostart }, set: { v in
                    do {
                        if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { dlog("Autostart: \(error)") }
                    autostart = SMAppService.mainApp.status == .enabled
                }))
                Toggle("Symbol in der Menüleiste", isOn: $menuIcon)
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
            }
            Section("Anzeigen in der Notch") {
                HStack {
                    Text("Dauer: \(String(format: "%.1f", hudSeconds)) s")
                    Slider(value: $hudSeconds, in: 1...5, step: 0.5)
                }
            }
        }.formStyle(.grouped)
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
            Section("Hilfe") {
                Button("Bedienungshilfen öffnen") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(u)
                    }
                }
                Button("Log öffnen") { NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/dynamicnotch.log")) }
                Button("Alle Einstellungen zurücksetzen") {
                    if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
                }
                Button("DynamicNotch beenden") { NSApp.terminate(nil) }
            }
            Section { Text("DynamicNotch 2.1").font(.footnote).foregroundColor(.secondary) }
        }.formStyle(.grouped)
    }
}
