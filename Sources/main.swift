import SwiftUI
import AppKit
import EventKit
import IOKit.ps
import CoreAudio
import Darwin
import ApplicationServices

// MARK: - HUD-Zustände

enum HUD: Equatable {
    case idle
    case volume(Float, Bool)   // Pegel, stumm
    case brightness(Float)
    case focus(String, Bool)   // Name, an/aus
    case locked
    case unlocked
    case symbol(String, String)   // Symbolname, Text
}

// MARK: - Lautstärke (CoreAudio)

final class VolumeMonitor {
    var onChange: ((Float, Bool) -> Void)?
    private var last: (Float, Bool)?

    func start() {
        last = read()
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
            self?.attach(); self?.fire()
        }
        attach()
    }

    private func device() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private func attach() {
        let dev = device()
        guard dev != 0 else { return }
        let combos: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
            (kAudioDevicePropertyVolumeScalar, 2),
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain)
        ]
        for (sel, el) in combos {
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioDevicePropertyScopeOutput, mElement: el)
            if AudioObjectHasProperty(dev, &a) {
                AudioObjectAddPropertyListenerBlock(dev, &a, DispatchQueue.main) { [weak self] _, _ in self?.fire() }
            }
        }
    }

    private func fire() {
        guard let cur = read() else { return }
        if let l = last, l.0 == cur.0, l.1 == cur.1 { return }
        last = cur
        onChange?(cur.0, cur.1)
    }

    var canControl: Bool { read() != nil }

    func step(up: Bool, fine: Bool) -> (Float, Bool)? {
        guard let cur = read() else { return nil }
        let st: Float = fine ? 1.0 / 64 : 1.0 / 16
        let raw = max(0, min(1, cur.0 + (up ? st : -st)))
        let v = max(0, min(1, (raw / st).rounded() * st))
        writeVolume(v)
        if cur.1 { writeMute(false) }
        return (v, false)
    }

    func toggleMute() -> (Float, Bool)? {
        guard let cur = read() else { return nil }
        writeMute(!cur.1)
        return (cur.0, !cur.1)
    }

    private func writeVolume(_ v: Float32) {
        let dev = device()
        var val = v
        let sz = UInt32(MemoryLayout<Float32>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                           mScope: kAudioDevicePropertyScopeOutput,
                                           mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(dev, &a),
           AudioObjectSetPropertyData(dev, &a, 0, nil, sz, &val) == noErr { return }
        for ch in [UInt32(1), UInt32(2)] {
            var c = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioDevicePropertyScopeOutput, mElement: ch)
            var x = v
            if AudioObjectHasProperty(dev, &c) { _ = AudioObjectSetPropertyData(dev, &c, 0, nil, sz, &x) }
        }
    }

    private func writeMute(_ on: Bool) {
        let dev = device()
        var val: UInt32 = on ? 1 : 0
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                           mScope: kAudioDevicePropertyScopeOutput,
                                           mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(dev, &a) {
            _ = AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &val)
        }
    }

    private func read() -> (Float, Bool)? {
        let dev = device()
        guard dev != 0 else { return nil }
        var vol: Float32 = 0
        var got = false
        var size = UInt32(MemoryLayout<Float32>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                           mScope: kAudioDevicePropertyScopeOutput,
                                           mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(dev, &a),
           AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &vol) == noErr {
            got = true
        } else {
            var sum: Float32 = 0, n: Float32 = 0
            for ch in [UInt32(1), UInt32(2)] {
                var c = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                   mScope: kAudioDevicePropertyScopeOutput, mElement: ch)
                var v: Float32 = 0
                var s = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectHasProperty(dev, &c),
                   AudioObjectGetPropertyData(dev, &c, 0, nil, &s, &v) == noErr { sum += v; n += 1 }
            }
            if n > 0 { vol = sum / n; got = true }
        }
        guard got else { return nil }
        var muted: UInt32 = 0
        var ms = UInt32(MemoryLayout<UInt32>.size)
        var m = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                           mScope: kAudioDevicePropertyScopeOutput,
                                           mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(dev, &m) { AudioObjectGetPropertyData(dev, &m, 0, nil, &ms, &muted) }
        return (vol, muted != 0)
    }
}

// MARK: - Log (Fehlersuche: /tmp/dynamicnotch.log)

func dlog(_ text: String) {
    guard let d = "\(Date()) \(text)\n".data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/dynamicnotch.log")
    if let fh = try? FileHandle(forWritingTo: url) {
        fh.seekToEndOfFile(); fh.write(d); try? fh.close()
    } else {
        try? d.write(to: url)
    }
}

// MARK: - Helligkeit (DisplayServices, private API per dlsym)

final class BrightnessMonitor {
    typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFn = @convention(c) (UInt32, Float) -> Int32
    private var getFn: GetFn?
    private var setFn: SetFn?
    private var display: CGDirectDisplayID = CGMainDisplayID()

    init() {
        if let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            if let p = dlsym(h, "DisplayServicesGetBrightness") { getFn = unsafeBitCast(p, to: GetFn.self) }
            if let p = dlsym(h, "DisplayServicesSetBrightness") { setFn = unsafeBitCast(p, to: SetFn.self) }
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &n)
        for i in 0..<Int(n) where CGDisplayIsBuiltin(ids[i]) != 0 { display = ids[i] }
    }

    func read() -> Float? {
        guard let getFn else { return nil }
        var b: Float = 0
        return getFn(display, &b) == 0 ? b : nil
    }

    func set(_ v: Float) { _ = setFn?(display, max(0, min(1, v))) }
    var canSet: Bool { setFn != nil && read() != nil }
}

// MARK: - Medientasten abfangen (blendet die System-Anzeige aus; braucht "Bedienungshilfen")

enum MediaKeys {
    static var handler: ((Int, Bool, Bool) -> Bool)?
    fileprivate static var tap: CFMachPort?
    static var isActive: Bool { tap != nil }

    static func start(prompt: Bool = true) {
        guard tap == nil else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) {
            let callback: CGEventTapCallBack = { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let t = MediaKeys.tap { CGEvent.tapEnable(tap: t, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                if type == .keyDown {
                    // Nur Funktionsreihen-Sondertasten beachten, alles andere unberührt durchreichen
                    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                       !event.flags.contains(.maskCommand), !event.flags.contains(.maskControl) {
                        let kc = Int(event.getIntegerValueField(.keyboardEventKeycode))
                        if [160, 131, 177, 176, 178].contains(kc) { _ = MediaKeys.handler?(1000 + kc, true, false) }
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard type.rawValue == 14,
                      let ns = NSEvent(cgEvent: event),
                      ns.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
                let data1 = ns.data1
                let code = (data1 & 0xFFFF0000) >> 16
                let flags = data1 & 0x0000FFFF
                let down = ((flags & 0xFF00) >> 8) == 0xA
                let fine = ns.modifierFlags.contains([.shift, .option])
                if [0, 1, 2, 3, 7, 16, 17, 18, 19, 20].contains(code), MediaKeys.handler?(code, down, fine) == true {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                    options: .defaultTap, eventsOfInterest: CGEventMask((1 << 14) | (1 << 10)),
                                    callback: callback, userInfo: nil)
            if let t = tap {
                let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
                CGEvent.tapEnable(tap: t, enable: true)
                dlog("Medientasten-Tap aktiv")
            }
        }
        if tap == nil {
            // Rechte fehlen noch: alle 3 s erneut versuchen, ohne neuen Dialog
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { start(prompt: false) }
        }
    }
}

// MARK: - Fenster über den Sperrbildschirm (private SkyLight-API, best effort)

enum LockSpace {
    private static var space = 0

    static func attach(_ window: NSWindow) {
        let sel = NSSelectorFromString("setCanBecomeVisibleWithoutLogin:")
        if window.responds(to: sel) { window.setValue(true, forKey: "canBecomeVisibleWithoutLogin") }

        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            dlog("SkyLight nicht ladbar"); return
        }
        func sym<T>(_ n: String, _ t: T.Type) -> T? {
            guard let p = dlsym(h, n) else { dlog("Symbol fehlt: \(n)"); return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let conn = sym("SLSMainConnectionID", (@convention(c) () -> Int32).self),
              let create = sym("SLSSpaceCreate", (@convention(c) (Int32, Int, CFDictionary?) -> Int).self),
              let setLevel = sym("SLSSpaceSetAbsoluteLevel", (@convention(c) (Int32, Int, Int32) -> Int32).self),
              let addExclusive = sym("SLSSpaceAddWindowsAndRemoveFromSpaces", (@convention(c) (Int32, Int, CFArray, Int32) -> Int32).self),
              let show = sym("SLSShowSpaces", (@convention(c) (Int32, CFArray) -> Void).self)
        else { return }
        let cid = conn()
        if space == 0 {
            space = create(cid, 1, nil) & 0xFFFFFFFF
            _ = setLevel(cid, space, 400)
        }
        show(cid, [space] as CFArray)
        // Fenster ausschließlich in diesen Space verschieben (7 = aus allen anderen entfernen)
        let result = addExclusive(cid, space, [window.windowNumber] as CFArray, 7)
        dlog("addExclusive Ergebnis \(result)")
        dlog("Sperrbildschirm-Space \(space), Fenster \(window.windowNumber)")
    }
}

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
        MediaKeys.start()

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
    func show(_ h: HUD, hideAfter: TimeInterval? = 1.6) {
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
        if ticks % 30 == 0 { readBattery(); loadEvent() }
        if ticks % 2 == 0 { checkFocus() }
        if running {
            remaining -= 1
            if remaining <= 0 { finish() }
        }
    }

    func finish() {
        NSSound(named: "Glass")?.play()
        onBreak.toggle()
        remaining = onBreak ? 5 * 60 : 25 * 60
        running = false
    }

    func resetTimer() {
        running = false
        onBreak = false
        remaining = 25 * 60
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

    func loadEvent() {
        let start = Date()
        let end = start.addingTimeInterval(48 * 3600)
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { !$0.isAllDay && $0.endDate > start }
            .sorted { $0.startDate < $1.startDate }
        if let e = events.first {
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_DE")
            f.dateFormat = "EE HH:mm"
            nextEvent = "\(f.string(from: e.startDate))  \(e.title ?? "")"
        } else {
            nextEvent = "Kein Termin in den nächsten 48 h"
        }
    }
}

// MARK: - View

struct NotchView: View {
    @ObservedObject var m: Model
    let notchW: CGFloat
    let notchH: CGFloat
    @State private var dropping = false

    static let panelW: CGFloat = 460
    static let panelH: CGFloat = 250
    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)

    var open: Bool { (m.expanded || dropping) && !m.locked }
    var showHUD: Bool { !open && m.hud != .idle }
    var wing: CGFloat {
        if case .focus = m.hud { return 100 }
        if case .symbol = m.hud { return 112 }
        return 56
    }
    var w: CGFloat {
        if open { return Self.panelW }
        if showHUD { return notchW + 2 * wing }
        return notchW + (m.running ? 90 : 0)
    }
    var h: CGFloat { open ? Self.panelH : notchH }
    var radius: CGFloat { open ? 26 : (showHUD ? 14 : 10) }
    var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            if open {
                expandedContent.transition(.opacity)
            } else if showHUD {
                hudContent.transition(.opacity)
            } else if m.running {
                HStack {
                    Spacer()
                    Text(m.timeString)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(.orange)
                        .frame(width: 45)
                }
                .frame(height: notchH)
            }
        }
        .frame(width: w, height: h)
        .overlay(alignment: .top) {
            if m.hud == .locked && !open {
                shape.strokeBorder(Color.white.opacity(0.6), lineWidth: 1.2)
                    .mask(VStack(spacing: 0) { Color.clear.frame(height: 3); Color.black })
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(spring) { m.expanded = hovering }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping, perform: handleDrop)
        .animation(spring, value: open)
        .animation(spring, value: m.running)
        .animation(spring, value: m.hud)
        .contextMenu {
            Button(MediaKeys.isActive ? "Tastenabfang aktiv ✓" : "Bedienungshilfen-Zugriff öffnen…") {
                if !MediaKeys.isActive,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("DynamicNotch beenden") { NSApp.terminate(nil) }
        }
        .frame(width: Self.panelW, height: Self.panelH, alignment: .top)
    }

    // MARK: HUD

    var hudContent: some View {
        HStack(spacing: 0) {
            hudIcon.frame(width: wing)
            Spacer(minLength: 0)
            hudRight.frame(width: wing)
        }
        .frame(height: notchH)
    }

    @ViewBuilder var hudIcon: some View {
        switch m.hud {
        case .volume(let v, let muted):
            Image(systemName: (muted || v <= 0) ? "speaker.slash.fill"
                  : v < 0.34 ? "speaker.wave.1.fill"
                  : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
        case .brightness:
            Image(systemName: "sun.max.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
        case .focus(_, let on):
            Image(systemName: "moon.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(on ? Color.purple : Color.gray)
        case .locked:
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
        case .unlocked:
            Image(systemName: "lock.open.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
        case .symbol(let name, _):
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder var hudRight: some View {
        switch m.hud {
        case .volume(let v, let muted): levelBar(muted ? 0 : v)
        case .brightness(let b): levelBar(b)
        case .focus(let name, let on):
            Text(on ? name : "Aus")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundColor(.white)
        case .symbol(_, let label):
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundColor(.white)
        default: EmptyView()
        }
    }

    func levelBar(_ v: Float) -> some View {
        let p = CGFloat(max(0, min(1, v)))
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.25))
            Capsule().fill(Color.white).frame(width: 36 * p)
        }
        .frame(width: 36, height: 4)
        .animation(.easeOut(duration: 0.1), value: v)
    }

    // MARK: Aufgeklappt

    var clock: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: m.now)
    }

    var batteryIcon: String {
        if m.charging { return "battery.100.bolt" }
        switch m.battery {
        case 0..<15: return "battery.0"
        case 15..<40: return "battery.25"
        case 40..<65: return "battery.50"
        case 65..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(clock).font(.system(size: 34, weight: .semibold, design: .rounded))
                Spacer()
                Label("\(m.battery)%", systemImage: batteryIcon)
                    .foregroundColor(m.battery < 15 && !m.charging ? .red : .white)
            }
            Label(m.nextEvent, systemImage: "calendar")
                .font(.system(size: 13))
                .lineLimit(1)
            HStack(spacing: 10) {
                Image(systemName: m.onBreak ? "cup.and.saucer.fill" : "brain.head.profile")
                    .foregroundColor(.orange)
                Text(m.timeString).font(.system(size: 18, weight: .medium).monospacedDigit())
                Text(m.onBreak ? "Pause" : "Fokus").font(.caption).foregroundColor(.gray)
                Spacer()
                Button { m.running.toggle() } label: {
                    Image(systemName: m.running ? "pause.fill" : "play.fill")
                }.buttonStyle(.plain)
                Button { m.resetTimer() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }.buttonStyle(.plain)
            }
            shelfView
        }
        .padding(.top, notchH + 4)
        .padding(.horizontal, 24)
        .foregroundColor(.white)
    }

    var shelfView: some View {
        Group {
            if m.shelf.isEmpty {
                Text("Dateien hierher ziehen")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundColor(dropping ? .orange : .gray.opacity(0.6)))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(m.shelf, id: \.self) { url in
                            VStack(spacing: 2) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 32, height: 32)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 9)).lineLimit(1).frame(width: 56)
                            }
                            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                            .onTapGesture { NSWorkspace.shared.open(url) }
                            .contextMenu {
                                Button("Entfernen") { m.shelf.removeAll { $0 == url } }
                            }
                        }
                    }
                }
                .frame(height: 56)
            }
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    if !m.shelf.contains(url) { m.shelf.append(url) }
                }
            }
        }
        return true
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    let model = Model()

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        reposition()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.reposition() }
        panel.orderFrontRegardless()
        attachLock()
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.attachLock()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.attachLock() }
        }
    }

    // Abschalten: defaults write local.dynamicnotch lockScreenOverlay -bool false
    func attachLock() {
        guard UserDefaults.standard.object(forKey: "lockScreenOverlay") as? Bool ?? true else { return }
        panel.orderFrontRegardless()
        LockSpace.attach(panel)
    }

    func reposition() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        // Ohne echte Notch wird automatisch eine "virtuelle" Notch gezeichnet.
        var notchW: CGFloat = 188
        var notchH: CGFloat = 32
        if screen.safeAreaInsets.top > 0,
           let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchW = screen.frame.width - l.width - r.width
            notchH = screen.safeAreaInsets.top
        }
        panel.contentView = NSHostingView(rootView: NotchView(m: model, notchW: notchW, notchH: notchH))
        let size = NSSize(width: NotchView.panelW, height: NotchView.panelH)
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
