import SwiftUI
import AppKit
import EventKit
import IOKit.ps

// MARK: - Model

final class Model: ObservableObject {
    @Published var expanded = false
    @Published var now = Date()
    @Published var battery = 100
    @Published var charging = false
    @Published var nextEvent = "Kein Termin"
    @Published var shelf: [URL] = []
    @Published var remaining = 25 * 60
    @Published var running = false
    @Published var onBreak = false
    @Published var hud: HUD = .idle
    @Published var locked = false
    @Published var tab: NotchTab = .home
    @Published var pinned = false
    @Published var pluggedIn = false
    @Published var events: [EventItem] = []
    @Published var sessions = 0

    let nowPlaying = NowPlayingMonitor()
    let clipboard = ClipboardMonitor()
    let stats = SystemStats()
    let caffeine = Caffeine()
    private var collapseWork: DispatchWorkItem?
    private var isHovering = false
    private var lastPlugged: Bool?
    private var lowWarned = false
    private var notifiedEvents = Set<String>()

    static func pref(_ k: String, _ d: Int) -> Int { UserDefaults.standard.object(forKey: k) as? Int ?? d }
    static func flag(_ k: String, _ d: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? d }

    private let store = EKEventStore()
    private let volume = VolumeMonitor()
    private let bright = BrightnessMonitor()
    private var ticks = 0
    private var hudTimer: Timer?
    private var lastBrightness: Float = -1
    private var focusKnown = false
    private var lastFocus: String?

    init() {
        readBattery()
        requestCalendar()
        lastBrightness = bright.read() ?? -1
        volume.onChange = { [weak self] v, muted in self?.volumeChanged(v, muted) }
        volume.start()
        MediaKeys.handler = { [weak self] code, down, fine in self?.handleMediaKey(code, down: down, fine: fine) ?? false }
        if Model.flag("captureKeys", true) { MediaKeys.start() }
        remaining = workSeconds
        nowPlaying.start()
        clipboard.start()
        stats.sample()
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if Model.flag("hotkeyOn", true), f == [.control, .option], e.charactersIgnoringModifiers?.lowercased() == "n" { self?.toggleOpen() }
        }

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.pollBrightness() }

        let dc = DistributedNotificationCenter.default()
        dc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.locked = true
            self.expanded = false
            self.show(.locked, hideAfter: nil)
        }
        dc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.locked = false
            self.show(.unlocked, hideAfter: 1.8)
        }
    }

    // HUD anzeigen
    static var hudSeconds: Double { UserDefaults.standard.object(forKey: "hudSeconds") as? Double ?? 1.6 }

    func show(_ h: HUD, hideAfter: TimeInterval? = Model.hudSeconds) {
        switch h {
        case .volume: if !Model.flag("hudVolume", true) { return }
        case .brightness: if !Model.flag("hudBrightness", true) { return }
        case .focus: if !Model.flag("hudFocus", true) { return }
        default: break
        }
        hudTimer?.invalidate()
        hud = h
        if let t = hideAfter {
            hudTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.hud = self.locked ? .locked : .idle
            }
        }
    }

    func volumeChanged(_ v: Float, _ muted: Bool) {
        show(.volume(v, muted))
    }

    // true = Taste wurde von uns verarbeitet (System-Anzeige wird unterdrückt)
    func handleMediaKey(_ code: Int, down: Bool, fine: Bool) -> Bool {
        switch code {
        case 0, 1:
            guard volume.canControl else { return false }
            if down, let r = volume.step(up: code == 0, fine: fine) { show(.volume(r.0, r.1)) }
            return true
        case 7:
            guard volume.canControl else { return false }
            if down, let r = volume.toggleMute() { show(.volume(r.0, r.1)) }
            return true
        case 2, 3:
            guard bright.canSet, let b = bright.read() else { return false }
            if down {
                let st: Float = fine ? 1.0 / 64 : 1.0 / 16
                let raw = max(0, min(1, b + (code == 2 ? st : -st)))
                let nb = max(0, min(1, (raw / st).rounded() * st))
                bright.set(nb)
                lastBrightness = nb
                show(.brightness(nb))
            }
            return true
        case 16, 17, 18, 19, 20, 1160, 1131, 1177, 1176, 1178:
            guard down else { return false }
            switch code {
            case 16: show(.symbol("playpause.fill", "Wiedergabe"))
            case 17, 19: show(.symbol("forward.fill", "Nächster Titel"))
            case 18, 20: show(.symbol("backward.fill", "Voriger Titel"))
            case 1160: show(.symbol("rectangle.3.group", "Mission Control"))
            case 1131: show(.symbol("square.grid.3x3.fill", "Launchpad"))
            case 1177: show(.symbol("magnifyingglass", "Spotlight"))
            case 1176: show(.symbol("mic.fill", "Diktieren"))
            default: if !focusKnown { show(.symbol("moon.fill", "Fokus")) }
            }
            return false   // Taste normal weiterreichen, macOS führt die Aktion selbst aus
        default:
            return false
        }
    }

    func pollBrightness() {
        guard let b = bright.read() else { return }
        defer { lastBrightness = b }
        if lastBrightness >= 0, abs(b - lastBrightness) > 0.01 { show(.brightness(b)) }
    }

    // Fokus: liest die Do-Not-Disturb-Datenbank (braucht "Voller Festplattenzugriff")
    func checkFocus() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else { return }
        let records = arr.first?["storeAssertionRecords"] as? [[String: Any]] ?? []
        var name: String?
        if let r = records.first,
           let d = r["assertionDetails"] as? [String: Any],
           let id = d["assertionDetailsModeIdentifier"] as? String {
            name = Model.focusName(id)
        }
        if !focusKnown { focusKnown = true; lastFocus = name; return }
        if name != lastFocus {
            if locked == false {
                if let n = name { show(.focus(n, true)) } else { show(.focus(lastFocus ?? "Fokus", false)) }
            }
            lastFocus = name
        }
    }

    static func focusName(_ id: String) -> String {
        switch id {
        case "com.apple.donotdisturb.mode.default": return "Nicht stören"
        case "com.apple.sleep.sleep-mode": return "Schlafen"
        case "com.apple.focus.work": return "Arbeit"
        case "com.apple.focus.personal-time": return "Persönlich"
        case "com.apple.focus.reading": return "Lesen"
        case "com.apple.focus.gaming": return "Gaming"
        case "com.apple.focus.mindfulness": return "Achtsamkeit"
        case "com.apple.donotdisturb.mode.driving": return "Fahren"
        default: return "Fokus"
        }
    }

    func tick() {
        now = Date()
        ticks += 1
        if ticks % 5 == 0 { readBattery() }
        if ticks % 30 == 0 { loadEvent() }
        if expanded && tab == .system && ticks % 2 == 0 { stats.sample() }
        if ticks % 2 == 0 { checkFocus() }
        if running {
            remaining -= 1
            if remaining <= 0 { finish() }
        }
    }

    var workSeconds: Int { max(1, Model.pref("workMin", 25)) * 60 }
    var breakSeconds: Int {
        let every = max(2, Model.pref("longBreakEvery", 4))
        let long = sessions > 0 && sessions % every == 0
        return max(1, Model.pref(long ? "longBreakMin" : "breakMin", long ? 15 : 5)) * 60
    }

    func finish() {
        if Model.flag("timerSound", true) {
            let n = UserDefaults.standard.string(forKey: "timerSoundName") ?? "Glass"
            NSSound(named: NSSound.Name(n))?.play()
        }
        if !onBreak { sessions += 1 }
        onBreak.toggle()
        remaining = onBreak ? breakSeconds : workSeconds
        running = onBreak ? Model.flag("autoStartBreak", false) : Model.flag("autoStartWork", false)
        show(.symbol(onBreak ? "cup.and.saucer.fill" : "brain.head.profile",
                     onBreak ? "Pause!" : "Weiter gehts"), hideAfter: 4)
    }

    func resetTimer() {
        running = false
        onBreak = false
        remaining = workSeconds
    }

    func applyTimerSettings() {
        if !running { remaining = onBreak ? breakSeconds : workSeconds }
    }

    // Öffnen / Schließen
    func setExpanded(_ v: Bool) {
        guard expanded != v else { return }
        if v && !Model.flag("rememberTab", true) {
            tab = NotchTab(rawValue: UserDefaults.standard.string(forKey: "defaultTab") ?? "home") ?? .home
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { expanded = v }
        if v && Model.flag("haptic", true) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func hoverChanged(_ hovering: Bool, hoverOpen: Bool) {
        isHovering = hovering
        collapseWork?.cancel()
        if hovering {
            if hoverOpen {
                let d = Double(Model.pref("openDelayMs", 0)) / 1000
                if d <= 0 { setExpanded(true) } else {
                    let w = DispatchWorkItem { [weak self] in self?.setExpanded(true) }
                    collapseWork = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: w)
                }
            }
        } else if !pinned {
            let w = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
            collapseWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(Model.pref("closeDelayMs", 250)) / 1000, execute: w)
        }
    }

    func togglePinned() {
        pinned.toggle()
        if !pinned && !isHovering { setExpanded(false) }
    }

    func toggleOpen() {
        if expanded { pinned = false; setExpanded(false) }
        else { setExpanded(true); pinned = true }
    }

    var timeString: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }

    func readBattery() {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            if let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any] {
                let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
                let mx = max(d[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
                battery = cur * 100 / mx
                charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
                pluggedIn = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                batteryEvents()
                return
            }
        }
    }

    func requestCalendar() {
        let handler: (Bool, Error?) -> Void = { [weak self] ok, _ in
            if ok { DispatchQueue.main.async { self?.loadEvent() } }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: handler)
        } else {
            store.requestAccess(to: .event, completion: handler)
        }
    }

    func batteryEvents() {
        if let last = lastPlugged, last != pluggedIn, Model.flag("notifyBattery", true), !locked {
            show(.symbol(pluggedIn ? "bolt.fill" : "powerplug", pluggedIn ? "Lädt \(battery) %" : "Akku \(battery) %"), hideAfter: 2.4)
        }
        lastPlugged = pluggedIn
        if battery <= Model.pref("lowBattery", 20) && !pluggedIn && !lowWarned && Model.flag("notifyBattery", true) {
            lowWarned = true
            show(.symbol("battery.25", "Akku \(battery) %"), hideAfter: 4)
        }
        if battery > Model.pref("lowBattery", 20) + 5 || pluggedIn { lowWarned = false }
    }

    func loadEvent() {
        let start = Date()
        let end = start.addingTimeInterval(48 * 3600)
        let list = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { !$0.isAllDay && $0.endDate > start }
            .sorted { $0.startDate < $1.startDate }
        events = list.prefix(6).map {
            EventItem(id: ($0.eventIdentifier ?? UUID().uuidString) + "\($0.startDate.timeIntervalSince1970)",
                      title: $0.title ?? "Ohne Titel", start: $0.startDate, end: $0.endDate,
                      color: Color(nsColor: $0.calendar.color ?? NSColor.systemOrange))
        }
        if let e = events.first {
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_DE")
            f.dateFormat = "EE HH:mm"
            nextEvent = "\(f.string(from: e.start))  \(e.title)"
            let mins = Int(e.start.timeIntervalSinceNow / 60)
            if mins >= 0 && mins <= Model.pref("eventLead", 5) && !notifiedEvents.contains(e.id)
                && Model.flag("notifyEvents", true) && !locked {
                notifiedEvents.insert(e.id)
                show(.symbol("calendar.badge.clock", mins == 0 ? "Jetzt" : "In \(mins) Min"), hideAfter: 4)
            }
        } else {
            nextEvent = "Kein Termin in den nächsten 48 h"
        }
    }
}

