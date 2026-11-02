import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import IOBluetooth
import UniformTypeIdentifiers

let appVersion = "3.0"
let repoSlug = "nmmhw4cbc7-commits/DynamicNotch"

// MARK: - Timer, der auch bei offenen Menüs weiterläuft (RunLoop .common)

@discardableResult
func every(_ seconds: TimeInterval, _ block: @escaping () -> Void) -> Timer {
    let t = Timer(timeInterval: seconds, repeats: true) { _ in block() }
    RunLoop.main.add(t, forMode: .common)
    return t
}

func formatClock(_ s: Int) -> String {
    let v = max(0, s)
    if v >= 3600 { return String(format: "%d:%02d:%02d", v / 3600, (v / 60) % 60, v % 60) }
    return String(format: "%02d:%02d", v / 60, v % 60)
}

func formatStopwatch(_ t: TimeInterval) -> String {
    let tenths = Int(max(0, t) * 10)
    let h = tenths / 36000, m = (tenths / 600) % 60, s = (tenths / 10) % 60, d = tenths % 10
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%02d:%02d,%d", m, s, d)
}

func formatUptime(_ t: TimeInterval) -> String {
    let mins = Int(t / 60)
    let d = mins / 1440, h = (mins / 60) % 24, m = mins % 60
    if d > 0 { return "\(d) T \(h) Std" }
    if h > 0 { return "\(h) Std \(m) Min" }
    return "\(m) Min"
}

// MARK: - Kurzzeitwecker (überlebt Ruhezustand, da mit Enddatum gerechnet wird)

final class QuickTimer: ObservableObject {
    @Published var total = 0
    @Published var endDate: Date?
    @Published var pausedLeft: Int?
    var onFinish: (() -> Void)?

    var active: Bool { endDate != nil || pausedLeft != nil }
    var running: Bool { endDate != nil }

    func left(_ now: Date = Date()) -> Int {
        if let e = endDate { return max(0, Int(ceil(e.timeIntervalSince(now)))) }
        return pausedLeft ?? 0
    }

    func progress(_ now: Date = Date()) -> Double {
        total > 0 ? min(1, max(0, Double(left(now)) / Double(total))) : 0
    }

    func start(minutes: Int) { start(seconds: minutes * 60) }

    func start(seconds: Int) {
        total = max(1, seconds)
        pausedLeft = nil
        endDate = Date().addingTimeInterval(TimeInterval(total))
    }

    func add(_ s: Int) {
        if let e = endDate {
            endDate = e.addingTimeInterval(TimeInterval(s)); total += s
        } else if let p = pausedLeft {
            pausedLeft = p + s; total += s
        } else {
            start(seconds: s)
        }
    }

    func toggle() {
        if let e = endDate {
            pausedLeft = max(0, Int(ceil(e.timeIntervalSinceNow)))
            endDate = nil
        } else if let p = pausedLeft {
            endDate = Date().addingTimeInterval(TimeInterval(p))
            pausedLeft = nil
        }
    }

    func cancel() { endDate = nil; pausedLeft = nil; total = 0 }

    func tick() {
        if let e = endDate, e <= Date() {
            endDate = nil; pausedLeft = nil
            onFinish?()
        }
    }
}

// MARK: - Stoppuhr

final class Stopwatch: ObservableObject {
    @Published var startDate: Date?
    @Published var accumulated: TimeInterval = 0
    @Published var laps: [TimeInterval] = []

    var running: Bool { startDate != nil }
    var used: Bool { running || accumulated > 0 }

    func elapsed(_ now: Date = Date()) -> TimeInterval {
        accumulated + (startDate.map { now.timeIntervalSince($0) } ?? 0)
    }

    func toggle() {
        if let s = startDate {
            accumulated += Date().timeIntervalSince(s)
            startDate = nil
        } else {
            startDate = Date()
        }
    }

    func lap() {
        guard running else { return }
        laps.insert(elapsed(), at: 0)
        if laps.count > 30 { laps.removeLast() }
    }

    func reset() { startDate = nil; accumulated = 0; laps = [] }
}

// MARK: - Downloads beobachten (Safari, Chrome, Firefox, Arc …)

final class DownloadsMonitor: ObservableObject {
    @Published var active: [String] = []
    @Published var recent: [URL] = []
    var onFinished: ((URL) -> Void)?

    private var known: Set<String>?
    private var busy = false
    private let partial: Set<String> = ["crdownload", "download", "part", "partial", "opdownload", "tmp"]
    private let queue = DispatchQueue(label: "dynamicnotch.downloads")

    var folder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads") }

    func start() {
        every(2) { [weak self] in self?.scan() }
        scan()
    }

    private func isPartial(_ u: URL) -> Bool { partial.contains(u.pathExtension.lowercased()) }

    private func scan() {
        guard Model.flag("watchDownloads", true) else {
            if !active.isEmpty { active = [] }
            known = nil
            return
        }
        if busy { return }
        busy = true
        let dir = folder
        queue.async { [weak self] in
            let items = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
            let dated: [(URL, Date)] = items.map {
                ($0, (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
            }
            DispatchQueue.main.async {
                self?.busy = false
                self?.apply(dated)
            }
        }
    }

    private func apply(_ items: [(URL, Date)]) {
        let names = Set(items.map { $0.0.lastPathComponent })
        let running = items.map { $0.0 }.filter(isPartial)
            .map { $0.deletingPathExtension().lastPathComponent }.sorted()
        if running != active { active = running }
        if let k = known {
            for (u, _) in items where !k.contains(u.lastPathComponent) && !isPartial(u) {
                recent.removeAll { $0 == u }
                recent.insert(u, at: 0)
                onFinished?(u)
            }
            recent.removeAll { !names.contains($0.lastPathComponent) }
        } else {
            recent = items.filter { !isPartial($0.0) }.sorted { $0.1 > $1.1 }.prefix(8).map { $0.0 }
        }
        if recent.count > 8 { recent.removeLast(recent.count - 8) }
        known = names
    }
}

// MARK: - Wetter (Open-Meteo, ohne Konto/Schlüssel, Ort in den Einstellungen)

func weatherSymbol(_ code: Int) -> String {
    switch code {
    case 0: return "sun.max.fill"
    case 1, 2: return "cloud.sun.fill"
    case 3: return "cloud.fill"
    case 45, 48: return "cloud.fog.fill"
    case 51...57: return "cloud.drizzle.fill"
    case 61...67, 80...82: return "cloud.rain.fill"
    case 71...77, 85, 86: return "cloud.snow.fill"
    case 95...99: return "cloud.bolt.rain.fill"
    default: return "cloud.fill"
    }
}

func weatherText(_ code: Int) -> String {
    switch code {
    case 0: return "Klar"
    case 1, 2: return "Leicht bewölkt"
    case 3: return "Bewölkt"
    case 45, 48: return "Nebel"
    case 51...57: return "Niesel"
    case 61...67, 80...82: return "Regen"
    case 71...77, 85, 86: return "Schnee"
    case 95...99: return "Gewitter"
    default: return "–"
    }
}

final class WeatherMonitor: ObservableObject {
    @Published var temp: Double?
    @Published var code = 0
    @Published var high: Double?
    @Published var low: Double?
    @Published var place = ""

    private var last = Date.distantPast
    private var lastCity = ""

    func refresh(force: Bool = false) {
        guard Model.flag("weatherOn", true) else { temp = nil; return }
        let city = (UserDefaults.standard.string(forKey: "weatherCity") ?? "").trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty else { temp = nil; place = ""; return }
        if !force && city == lastCity && Date().timeIntervalSince(last) < 1800 { return }
        last = Date()
        lastCity = city
        guard var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search") else { return }
        c.queryItems = [URLQueryItem(name: "name", value: city),
                        URLQueryItem(name: "count", value: "1"),
                        URLQueryItem(name: "language", value: "de")]
        guard let u = c.url else { return }
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            guard let data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let r = (j["results"] as? [[String: Any]])?.first,
                  let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else {
                dlog("Wetter: Ort nicht gefunden")
                return
            }
            let name = r["name"] as? String ?? city
            self?.forecast(lat: lat, lon: lon, name: name)
        }.resume()
    }

    private func forecast(lat: Double, lon: Double, name: String) {
        guard var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else { return }
        c.queryItems = [URLQueryItem(name: "latitude", value: String(lat)),
                        URLQueryItem(name: "longitude", value: String(lon)),
                        URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
                        URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                        URLQueryItem(name: "timezone", value: "auto"),
                        URLQueryItem(name: "forecast_days", value: "1")]
        guard let u = c.url else { return }
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            guard let data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = j["current"] as? [String: Any] else { return }
            let t = cur["temperature_2m"] as? Double
            let code = cur["weather_code"] as? Int ?? 0
            let daily = j["daily"] as? [String: Any]
            let hi = (daily?["temperature_2m_max"] as? [Double])?.first
            let lo = (daily?["temperature_2m_min"] as? [Double])?.first
            DispatchQueue.main.async {
                guard let self else { return }
                self.temp = t
                self.code = code
                self.high = hi
                self.low = lo
                self.place = name
            }
        }.resume()
    }
}

// MARK: - Bluetooth-Geräte verbunden / getrennt

final class BluetoothWatcher: NSObject {
    var onChange: ((String, Bool) -> Void)?
    private var connectNote: IOBluetoothUserNotification?
    private var started = Date()

    func start() {
        started = Date()
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(connected(_:device:)))
    }

    @objc func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        _ = device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        // Beim Start meldet macOS alle schon verbundenen Geräte: die ignorieren
        if Date().timeIntervalSince(started) > 4 { onChange?(device.name ?? "Gerät", true) }
    }

    @objc func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onChange?(device.name ?? "Gerät", false)
    }

    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("keyboard") || n.contains("tastatur") { return "keyboard" }
        if n.contains("mouse") || n.contains("maus") { return "magicmouse" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if n.contains("beats") || n.contains("buds") || n.contains("head") || n.contains("wh-") { return "headphones" }
        if n.contains("controller") || n.contains("xbox") || n.contains("dualsense") { return "gamecontroller.fill" }
        return "dot.radiowaves.left.and.right"
    }
}

// MARK: - Update-Prüfung (GitHub Releases)

func versionNewer(_ a: String, than b: String) -> Bool {
    let pa = a.split(separator: ".").map { Int($0) ?? 0 }
    let pb = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0
        let y = i < pb.count ? pb[i] : 0
        if x != y { return x > y }
    }
    return false
}

final class Updater: ObservableObject {
    @Published var latest: String?
    @Published var downloadURL: URL?
    @Published var checking = false

    var available: Bool {
        guard let l = latest else { return false }
        return versionNewer(l, than: appVersion)
    }

    func check(_ done: ((Bool) -> Void)? = nil) {
        guard let u = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest") else { return }
        checking = true
        var r = URLRequest(url: u)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            var tag: String?
            var url: URL?
            if let data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let t = j["tag_name"] as? String {
                tag = t.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let assets = j["assets"] as? [[String: Any]] ?? []
                let dmg = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.hasSuffix(".dmg") }
                if let s = dmg ?? (j["html_url"] as? String) { url = URL(string: s) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                if let tag { self.latest = tag; self.downloadURL = url }
                done?(self.available)
            }
        }.resume()
    }

    func openDownload() {
        let fallback = URL(string: "https://github.com/\(repoSlug)/releases/latest")
        if let u = downloadURL ?? fallback { NSWorkspace.shared.open(u) }
    }
}

// MARK: - Taschenrechner (eigener Parser, kein NSExpression → kein Absturz bei Tippfehlern)

enum Calc {
    static func eval(_ input: String) -> Double? {
        let cleaned = input
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ":", with: "/")
            .filter { !$0.isWhitespace }
        guard !cleaned.isEmpty, cleaned.contains(where: { "+-*/^%()".contains($0) }) || Double(cleaned) == nil else { return nil }
        var p = Parser(Array(cleaned))
        guard let v = p.expr(), p.i == p.c.count, v.isFinite else { return nil }
        return v
    }

    static func format(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 8
        f.usesGroupingSeparator = abs(v) >= 10000
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    struct Parser {
        let c: [Character]
        var i = 0
        init(_ c: [Character]) { self.c = c }

        func peek() -> Character? { i < c.count ? c[i] : nil }

        mutating func expr() -> Double? {
            guard var v = term() else { return nil }
            while let ch = peek(), ch == "+" || ch == "-" {
                i += 1
                guard let r = term() else { return nil }
                v = ch == "+" ? v + r : v - r
            }
            return v
        }

        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while let ch = peek(), ch == "*" || ch == "/" || ch == "%" {
                i += 1
                guard let r = power() else { return nil }
                switch ch {
                case "*": v *= r
                case "/": v /= r
                default: v = v.truncatingRemainder(dividingBy: r)
                }
            }
            return v
        }

        mutating func power() -> Double? {
            guard let b = unary() else { return nil }
            if peek() == "^" {
                i += 1
                guard let e = power() else { return nil }
                return pow(b, e)
            }
            return b
        }

        mutating func unary() -> Double? {
            if peek() == "-" { i += 1; return unary().map { -$0 } }
            if peek() == "+" { i += 1; return unary() }
            return atom()
        }

        mutating func atom() -> Double? {
            if peek() == "(" {
                i += 1
                let v = expr()
                guard peek() == ")" else { return nil }
                i += 1
                return v
            }
            let start = i
            while let ch = peek(), ch.isASCII, ch.isNumber || ch == "." { i += 1 }
            guard i > start else { return nil }
            return Double(String(c[start..<i]))
        }
    }
}

// MARK: - Vollbild erkennen (Notch dann ausblenden)

enum FullscreenCheck {
    static func active(on screen: NSScreen?) -> Bool {
        guard let screen,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid(),
              app.bundleIdentifier != "com.apple.finder",
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        let pid = Int(app.processIdentifier)
        let sf = screen.frame
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? Int) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            if abs(b.width - sf.width) < 1 && abs(b.height - sf.height) < 1 { return true }
        }
        return false
    }
}

// MARK: - Akku-Zustand (Ladezyklen, Kapazität)

func readBatteryHealth() -> (cycles: Int, health: Int)? {
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard svc != 0 else { return nil }
    defer { IOObjectRelease(svc) }
    func prop(_ k: String) -> Int? {
        IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
    }
    let cycles = prop("CycleCount") ?? 0
    let maxCap = prop("AppleRawMaxCapacity") ?? prop("NominalChargeCapacity") ?? 0
    let design = prop("DesignCapacity") ?? 0
    let health = design > 0 ? min(100, maxCap * 100 / design) : 0
    return (cycles, health)
}

// MARK: - Farbe aus dem Cover

func averageColor(_ img: NSImage) -> Color? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
    NSGraphicsContext.restoreGraphicsState()
    guard let c = rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return nil }
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    if s < 0.12 { return Color(white: 0.85) }
    return Color(hue: Double(h), saturation: Double(min(1, s * 1.25)), brightness: Double(max(0.8, b)))
}

// MARK: - Einstellungen exportieren / importieren

enum SettingsIO {
    static func export() {
        guard let id = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: id) else { return }
        var out: [String: Any] = [:]
        for (k, v) in domain where JSONSerialization.isValidJSONObject([k: v]) { out[k] = v }
        let p = NSSavePanel()
        p.nameFieldStringValue = "DynamicNotch-Einstellungen.json"
        p.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url,
              let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) else { return }
        do { try data.write(to: url) } catch { dlog("Export: \(error)") }
    }

    @discardableResult
    static func importFile() -> Bool {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        p.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        for (k, v) in dict { UserDefaults.standard.set(v, forKey: k) }
        return true
    }
}
