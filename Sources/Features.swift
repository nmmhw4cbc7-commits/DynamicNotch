import SwiftUI
import AppKit
import IOKit.pwr_mgt
import Darwin

// MARK: - Tabs & Datentypen

enum NotchTab: String, CaseIterable, Identifiable {
    case home, media, tools, clipboard, shelf, system, settings
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .media: return "music.note"
        case .tools: return "wrench.and.screwdriver.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .shelf: return "tray.full.fill"
        case .system: return "cpu.fill"
        case .settings: return "gearshape.fill"
        }
    }
    var title: String {
        switch self {
        case .home: return "Übersicht"
        case .media: return "Medien"
        case .tools: return "Werkzeuge"
        case .clipboard: return "Zwischenablage"
        case .shelf: return "Ablage"
        case .system: return "System"
        case .settings: return "Einstellungen"
        }
    }
}

struct EventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
}

// MARK: - Akzentfarbe

let accentOptions: [(String, String)] = [("orange", "Orange"), ("green", "Grün"), ("blue", "Blau"),
                                         ("pink", "Pink"), ("purple", "Lila"), ("red", "Rot")]

func accentColor(_ n: String) -> Color {
    switch n {
    case "green": return .green
    case "blue": return .blue
    case "pink": return .pink
    case "purple": return .purple
    case "red": return .red
    default: return .orange
    }
}

// MARK: - Prozess-Helfer

@discardableResult
func runProcess(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

func spawn(_ path: String, _ args: [String]) {
    DispatchQueue.global().async { _ = runProcess(path, args) }
}

// MARK: - Medien-Player (Spotify + Apple Music per AppleScript)

struct Track: Equatable {
    var app = ""
    var title = ""
    var artist = ""
    var album = ""
    var playing = false
    var duration: Double = 0
}

final class NowPlayingMonitor: ObservableObject {
    @Published var track: Track?
    @Published var position: Double = 0
    @Published var artwork: NSImage?

    var isPlaying: Bool { track?.playing ?? false }

    private let queue = DispatchQueue(label: "dynamicnotch.nowplaying")
    private var busy = false
    private var artKey = ""
    private var artCache: [String: NSImage] = [:]

    func start() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let t = self.track, t.playing else { return }
            self.position += 1
            if t.duration > 0 { self.position = min(self.position, t.duration) }
        }
        poll()
    }

    private func poll() {
        if busy { return }
        let ids = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        let spotify = ids.contains("com.spotify.client") && Model.flag("spotifyOn", true)
        let music = ids.contains("com.apple.Music") && Model.flag("musicOn", true)
        guard spotify || music else {
            if track != nil { track = nil; artwork = nil; artKey = "" }
            return
        }
        busy = true
        queue.async { [weak self] in
            var results: [(Track, Double, String?)] = []
            if spotify, let r = NowPlayingMonitor.query(app: "Spotify") { results.append(r) }
            if music, let r = NowPlayingMonitor.query(app: "Music") { results.append(r) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                let best = results.first(where: { $0.0.playing }) ?? results.first
                self.apply(best)
            }
        }
    }

    static func query(app: String) -> (Track, Double, String?)? {
        let artLine = app == "Spotify" ? "(artwork url of current track)" : "\"\""
        let script = """
        tell application "\(app)"
          if player state is stopped then return "stopped"
          set st to player state as string
          set t to current track
          return st & "|||" & (name of t) & "|||" & (artist of t) & "|||" & (album of t) & "|||" & (player position as string) & "|||" & ((duration of t) as string) & "|||" & \(artLine)
        end tell
        """
        let out = runProcess("/usr/bin/osascript", ["-e", script])
        let parts = out.components(separatedBy: "|||")
        guard parts.count >= 7 else { return nil }
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        var dur = num(parts[5])
        if app == "Spotify" { dur /= 1000 }
        let t = Track(app: app, title: parts[1], artist: parts[2], album: parts[3],
                      playing: parts[0] == "playing", duration: dur)
        return (t, num(parts[4]), parts[6].isEmpty ? nil : parts[6])
    }

    private func apply(_ r: (Track, Double, String?)?) {
        guard let r else { track = nil; artwork = nil; artKey = ""; return }
        if track != r.0 { track = r.0 }
        position = r.1
        let key = r.0.title + "|" + r.0.artist
        if key != artKey {
            artKey = key
            loadArtwork(key: key, url: r.2, t: r.0)
        }
    }

    private func loadArtwork(key: String, url: String?, t: Track) {
        if let img = artCache[key] { artwork = img; return }
        artwork = nil
        if let url, let u = URL(string: url) { fetch(u, key: key); return }
        // Apple Music liefert kein Cover per URL: über die iTunes-Suche holen
        guard var c = URLComponents(string: "https://itunes.apple.com/search") else { return }
        c.queryItems = [URLQueryItem(name: "term", value: t.artist + " " + t.title),
                        URLQueryItem(name: "entity", value: "song"),
                        URLQueryItem(name: "limit", value: "1")]
        guard let u = c.url else { return }
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            guard let data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let res = (j["results"] as? [[String: Any]])?.first,
                  let art = res["artworkUrl100"] as? String,
                  let au = URL(string: art.replacingOccurrences(of: "100x100", with: "300x300")) else { return }
            DispatchQueue.main.async { self?.fetch(au, key: key) }
        }.resume()
    }

    private func fetch(_ u: URL, key: String) {
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.artCache[key] = img
                if self?.artKey == key { self?.artwork = img }
            }
        }.resume()
    }

    // Steuerung
    func playPause() {
        send("playpause")
        if var t = track { t.playing.toggle(); track = t }
    }
    func next() { send("next track") }
    func previous() { send("previous track") }

    func seek(to s: Double) {
        guard let app = track?.app else { return }
        spawn("/usr/bin/osascript", ["-e", "tell application \"\(app)\" to set player position to \(Int(s))"])
        position = s
    }

    private func send(_ cmd: String) {
        guard let app = track?.app else { return }
        spawn("/usr/bin/osascript", ["-e", "tell application \"\(app)\" to \(cmd)"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.poll() }
    }
}

// MARK: - Zwischenablage-Verlauf (nur im Speicher, Passwortmanager-Einträge werden ignoriert)

final class ClipboardMonitor: ObservableObject {
    @Published var items: [String] = []
    private var lastCount = NSPasteboard.general.changeCount

    func start() {
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.check() }
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        guard Model.flag("clipboardEnabled", true) else { return }
        let types = pb.types ?? []
        let secret = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
        if types.contains(where: { secret.contains($0.rawValue) }) { return }
        guard let s = pb.string(forType: .string) else { return }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count < 5000 else { return }
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        let cap = max(5, Model.pref("clipMax", 25))
        if items.count > cap { items.removeLast(items.count - cap) }
    }

    func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        lastCount = pb.changeCount
    }

    func clear() { items.removeAll() }
}

// MARK: - Systemstatus (CPU, RAM, Netzwerk)

final class SystemStats: ObservableObject {
    @Published var cpu: Double = 0
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 40)
    @Published var memUsed: Double = 0
    @Published var memTotal: Double = 1
    @Published var down: Double = 0
    @Published var up: Double = 0

    private var prevTicks: (UInt32, UInt32, UInt32, UInt32)?
    private var prevNet: (UInt64, UInt64)?
    private var prevTime = Date()

    func sample() {
        sampleCPU()
        sampleMem()
        sampleNet()
    }

    private func sampleCPU() {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let cap = Int(count)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: cap) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let cur = (info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3)
        if let p = prevTicks {
            let u = Double(cur.0 &- p.0), s = Double(cur.1 &- p.1)
            let i = Double(cur.2 &- p.2), n = Double(cur.3 &- p.3)
            let total = u + s + i + n
            if total > 0 {
                cpu = (u + s + n) / total
                cpuHistory.append(cpu)
                if cpuHistory.count > 40 { cpuHistory.removeFirst() }
            }
        }
        prevTicks = cur
    }

    private func sampleMem() {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var st = vm_statistics64_data_t()
        let cap = Int(count)
        let kr = withUnsafeMutablePointer(to: &st) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: cap) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        var ps: vm_size_t = 0
        host_page_size(mach_host_self(), &ps)
        let pages = Double(st.active_count) + Double(st.wire_count) + Double(st.compressor_page_count)
        memUsed = pages * Double(ps)
        memTotal = Double(ProcessInfo.processInfo.physicalMemory)
    }

    private func netBytes() -> (UInt64, UInt64) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return (0, 0) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                if name.hasPrefix("en") {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    rx += UInt64(d.ifi_ibytes)
                    tx += UInt64(d.ifi_obytes)
                }
            }
            ptr = ifa.ifa_next
        }
        freeifaddrs(first)
        return (rx, tx)
    }

    private func sampleNet() {
        let cur = netBytes()
        let now = Date()
        let dt = now.timeIntervalSince(prevTime)
        if let p = prevNet, dt > 0.2 {
            down = Double(cur.0 >= p.0 ? cur.0 - p.0 : 0) / dt
            up = Double(cur.1 >= p.1 ? cur.1 - p.1 : 0) / dt
        }
        prevNet = cur
        prevTime = now
    }
}

func formatRate(_ b: Double) -> String {
    if b >= 1_048_576 { return String(format: "%.1f MB/s", b / 1_048_576) }
    return String(format: "%.0f KB/s", b / 1024)
}

func formatGB(_ b: Double) -> String { String(format: "%.1f GB", b / 1_073_741_824) }

// MARK: - Koffein (Mac wach halten)

final class Caffeine: ObservableObject {
    @Published var on = false
    private var assertion: IOPMAssertionID = 0

    func set(_ v: Bool) {
        if v {
            let r = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "DynamicNotch Koffein" as CFString, &assertion)
            on = (r == kIOReturnSuccess)
        } else {
            if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
            on = false
        }
    }
    func toggle() { set(!on) }
}

// MARK: - Schnellaktionen

enum QuickActions {
    static var sampler: NSColorSampler?

    static func screenshot() { spawn("/usr/sbin/screencapture", ["-ic"]) }
    static func sleepDisplay() { spawn("/usr/bin/pmset", ["displaysleepnow"]) }
    static func screenSaver() { spawn("/usr/bin/open", ["-a", "ScreenSaverEngine"]) }

    static func toggleDarkMode() {
        spawn("/usr/bin/osascript", ["-e",
              "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"])
    }

    static func pickColor(_ done: @escaping (String) -> Void) {
        let s = NSColorSampler()
        sampler = s
        s.show { color in
            sampler = nil
            guard let c = color?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            done(hex)
        }
    }
}
