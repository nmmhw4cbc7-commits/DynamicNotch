import SwiftUI
import AppKit
import ServiceManagement

func formatTime(_ s: Double) -> String {
    let i = max(0, Int(s))
    return String(format: "%d:%02d", i / 60, i % 60)
}

func dateFormatter(_ format: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "de_DE")
    f.dateFormat = format
    return f
}

func openCalendarApp() {
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
}

/// Simuliert ⌘V in der vorderen App (braucht Bedienungshilfen)
func pasteIntoFrontApp() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

// MARK: - Tab: Übersicht

struct HomeTab: View {
    @ObservedObject var m: Model
    @ObservedObject var weather: WeatherMonitor
    @AppStorage("accent") private var accentName = "orange"
    @AppStorage("clock24") private var clock24 = true
    @AppStorage("showSeconds") private var showSeconds = false
    @AppStorage("showDate") private var showDate = true

    static let c24 = dateFormatter("HH:mm")
    static let c24s = dateFormatter("HH:mm:ss")
    static let c12 = dateFormatter("h:mm")
    static let c12s = dateFormatter("h:mm:ss")
    static let dateFmt = dateFormatter("EEEE, d. MMMM")
    static let eventFmt = dateFormatter("EE HH:mm")

    var clockString: String {
        let f = clock24 ? (showSeconds ? Self.c24s : Self.c24) : (showSeconds ? Self.c12s : Self.c12)
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

    func relative(_ e: EventItem) -> String {
        if e.start <= m.now {
            let left = Int(e.end.timeIntervalSince(m.now) / 60)
            return "noch \(max(left, 1)) Min"
        }
        let mins = Int(e.start.timeIntervalSince(m.now) / 60)
        if mins < 60 { return "in \(max(mins, 1)) Min" }
        if Calendar.current.isDateInToday(e.start) { return "um " + Self.c24.string(from: e.start) }
        return Self.eventFmt.string(from: e.start)
    }

    var weatherLine: String {
        var parts = [weather.place, weatherText(weather.code)]
        if let h = weather.high, let l = weather.low { parts.append("\(Int(l.rounded()))°/\(Int(h.rounded()))°") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clockString)
                        .font(.system(size: showSeconds ? 34 : 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if showDate {
                        Text(Self.dateFmt.string(from: m.now))
                            .font(.system(size: 12)).foregroundColor(.gray)
                    }
                    HStack(spacing: 12) {
                        if m.hasBattery {
                            Label("\(m.battery)%", systemImage: batteryIcon)
                                .foregroundColor(m.battery < 15 && !m.charging ? .red : .white)
                        }
                        if let t = weather.temp {
                            Label("\(Int(t.rounded()))°", systemImage: weatherSymbol(weather.code))
                                .symbolRenderingMode(.multicolor)
                        }
                    }
                    .font(.system(size: 12))
                    if weather.temp != nil {
                        Text(weatherLine).font(.system(size: 10)).foregroundColor(.gray).lineLimit(1)
                    }
                }
                .frame(width: 185, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        SectionTitle("Termine")
                        Spacer()
                        Button { openCalendarApp() } label: { Image(systemName: "calendar").font(.system(size: 10)) }
                            .buttonStyle(.plain).foregroundColor(.gray).help("Kalender öffnen")
                    }
                    if m.events.isEmpty {
                        Text("Keine Termine in den nächsten 48 h")
                            .font(.system(size: 12)).foregroundColor(.gray)
                    } else {
                        ForEach(m.events.prefix(3)) { e in eventRow(e) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            pomodoro
        }
        .padding(.bottom, 8)
    }

    func eventRow(_ e: EventItem) -> some View {
        HStack(spacing: 8) {
            Circle().fill(e.color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.system(size: 12)).lineLimit(1)
                if !e.location.isEmpty && e.meeting == nil {
                    Text(e.location).font(.system(size: 9)).foregroundColor(.gray).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let u = e.meeting {
                Button { NSWorkspace.shared.open(u) } label: {
                    Image(systemName: "video.fill").font(.system(size: 9))
                }
                .buttonStyle(Chip(active: true))
                .help("Meeting beitreten")
            }
            Text(relative(e)).font(.system(size: 11)).foregroundColor(e.start <= m.now ? notchAccent(accentName) : .gray)
        }
        .contentShape(Rectangle())
        .onTapGesture { openCalendarApp() }
    }

    var pomodoroProgress: Double {
        let total = Double(m.onBreak ? m.breakSeconds : m.workSeconds)
        return total > 0 ? 1 - Double(m.remaining) / total : 0
    }

    var pomodoro: some View {
        HStack(spacing: 10) {
            Image(systemName: m.onBreak ? "cup.and.saucer.fill" : "brain.head.profile")
                .foregroundColor(notchAccent(accentName))
            Text(m.timeString).font(.system(size: 20, weight: .medium).monospacedDigit())
            Text(m.onBreak ? "Pause" : "Fokus").font(.caption).foregroundColor(.gray)
            if m.sessions > 0 {
                Text("· \(m.sessions) erledigt").font(.caption).foregroundColor(.gray)
            }
            Spacer()
            Button { m.running.toggle() } label: {
                Image(systemName: m.running ? "pause.fill" : "play.fill").frame(width: 28, height: 24)
            }.buttonStyle(.plain).help(m.running ? "Pausieren" : "Starten")
            Button { m.skipPhase() } label: {
                Image(systemName: "forward.end.fill").frame(width: 28, height: 24)
            }.buttonStyle(.plain).help("Phase überspringen")
            Button { m.resetTimer() } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 28, height: 24)
            }.buttonStyle(.plain).help("Zurücksetzen")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 12).fill(notchAccent(accentName).opacity(0.18))
                        .frame(width: g.size.width * CGFloat(min(1, max(0, pomodoroProgress))))
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Tab: Medien

struct MediaTab: View {
    @ObservedObject var np: NowPlayingMonitor
    let m: Model
    @State private var vol: Double = 0.5

    var body: some View {
        if let t = np.track {
            player(t)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note.list").font(.system(size: 30)).foregroundColor(.gray)
                Text("Starte Spotify oder Musik").font(.system(size: 13)).foregroundColor(.gray)
                Text("Beim ersten Mal fragt macOS nach Automations-Zugriff.")
                    .font(.system(size: 10)).foregroundColor(.gray.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func player(_ t: Track) -> some View {
        let tint = np.tint ?? .white
        return HStack(spacing: 18) {
            artwork
                .frame(width: 150, height: 150)
                .shadow(color: (np.tint ?? .clear).opacity(0.5), radius: 14)
                .onTapGesture { np.openPlayer() }
                .help("\(t.app) öffnen")
            VStack(alignment: .leading, spacing: 5) {
                Text(t.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text(t.artist).font(.system(size: 13)).foregroundColor(.gray).lineLimit(1)
                Text(t.album.isEmpty ? t.app : "\(t.album) · \(t.app)")
                    .font(.system(size: 10)).foregroundColor(.gray.opacity(0.7)).lineLimit(1)
                Spacer(minLength: 0)
                SeekBar(value: np.position, total: t.duration, color: tint) { np.seek(to: $0) }
                HStack {
                    Text(formatTime(np.position)).font(.system(size: 10).monospacedDigit())
                    Spacer()
                    Text("-" + formatTime(max(0, t.duration - np.position))).font(.system(size: 10).monospacedDigit())
                }.foregroundColor(.gray)
                HStack(spacing: 28) {
                    Spacer()
                    Button { np.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 18)) }
                    Button { np.playPause() } label: {
                        Image(systemName: t.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 34))
                    }
                    Button { np.next() } label: { Image(systemName: "forward.fill").font(.system(size: 18)) }
                    Spacer()
                }.buttonStyle(.plain)
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").font(.system(size: 9)).foregroundColor(.gray)
                    Slider(value: $vol, in: 0...1)
                        .controlSize(.mini)
                        .tint(tint)
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
            .frame(height: 170)
        }
        .padding(.top, 6)
        .onAppear { vol = Double(m.volume.level) }
        .onChange(of: vol) { _, v in
            if abs(Double(m.volume.level) - v) > 0.005 { m.volume.setLevel(Float(v)) }
        }
    }

    @ViewBuilder var artwork: some View {
        if let img = np.artwork {
            Image(nsImage: img).resizable().scaledToFill()
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.1))
                .overlay(Image(systemName: "music.note").font(.system(size: 34)).foregroundColor(.gray))
        }
    }
}

// MARK: - Tab: Timer & Stoppuhr

struct TimerTab: View {
    @ObservedObject var m: Model
    @ObservedObject var qt: QuickTimer
    @ObservedObject var sw: Stopwatch
    @AppStorage("accent") private var accentName = "orange"
    @AppStorage("lastTimerMin") private var customMin = 10

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            countdown.frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1).padding(.vertical, 4)
            stopwatch.frame(width: 175)
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    var countdown: some View {
        let accent = notchAccent(accentName)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Kurzzeitwecker")
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(qt.active ? qt.progress(m.now) : 1))
                        .stroke(qt.active ? accent : Color.white.opacity(0.25),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.4), value: m.now)
                    Text(formatClock(qt.active ? qt.left(m.now) : customMin * 60))
                        .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 8) {
                    if qt.active {
                        Text(qt.running ? "Läuft" : "Pausiert").font(.system(size: 11)).foregroundColor(.gray)
                        HStack(spacing: 6) {
                            Button { qt.toggle() } label: { Image(systemName: qt.running ? "pause.fill" : "play.fill") }
                                .buttonStyle(Chip(active: true))
                            Button("+1 Min") { qt.add(60) }.buttonStyle(Chip())
                            Button { qt.cancel() } label: { Image(systemName: "xmark") }.buttonStyle(Chip())
                        }
                    } else {
                        Stepper("\(customMin) Min", value: $customMin, in: 1...240)
                            .font(.system(size: 12))
                        Button { qt.start(minutes: customMin) } label: {
                            Label("Starten", systemImage: "play.fill")
                        }
                        .buttonStyle(Chip(active: true))
                    }
                }
            }
            HStack(spacing: 5) {
                ForEach([1, 3, 5, 10, 15, 30, 60], id: \.self) { n in
                    Button(n >= 60 ? "\(n / 60) h" : "\(n) m") { customMin = n; qt.start(minutes: n) }
                        .buttonStyle(Chip())
                }
            }
        }
    }

    var stopwatch: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Stoppuhr")
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                Text(formatStopwatch(sw.elapsed(ctx.date)))
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
            }
            HStack(spacing: 6) {
                Button(sw.running ? "Stopp" : "Start") { sw.toggle() }.buttonStyle(Chip(active: true))
                Button(sw.running ? "Runde" : "Zurücksetzen") { if sw.running { sw.lap() } else { sw.reset() } }
                    .buttonStyle(Chip())
                    .disabled(!sw.used)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(Array(sw.laps.enumerated()), id: \.offset) { i, t in
                        HStack {
                            Text("Runde \(sw.laps.count - i)").foregroundColor(.gray)
                            Spacer()
                            Text(formatStopwatch(t)).monospacedDigit()
                        }
                        .font(.system(size: 10))
                    }
                }
            }
        }
    }
}

// MARK: - Tab: Werkzeuge

struct ToolsTab: View {
    @ObservedObject var m: Model
    @ObservedObject var caffeine: Caffeine
    @AppStorage("note") private var note = ""
    @State private var expr = ""
    @State private var micMuted = false
    @State private var desktopHidden = false
    @State private var hiddenFiles = false

    var result: String? { Calc.eval(expr).map(Calc.format) }

    static let untilFmt = dateFormatter("HH:mm")

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ActionButton(icon: "camera.viewfinder", title: "Screenshot", height: 44) { QuickActions.screenshot() }
                ActionButton(icon: "eyedropper", title: "Farbwähler", height: 44) {
                    QuickActions.pickColor { hex in DispatchQueue.main.async { m.show(.symbol("eyedropper", hex)) } }
                }
                ActionButton(icon: "cup.and.saucer.fill",
                             title: caffeine.until.map { "bis " + Self.untilFmt.string(from: $0) } ?? "Koffein",
                             active: caffeine.on, height: 44) {
                    caffeine.toggle()
                    m.show(.symbol("cup.and.saucer.fill", caffeine.on ? "Bleibt wach" : "Normal"))
                }
                .contextMenu {
                    Button("15 Minuten") { caffeine.set(true, minutes: 15) }
                    Button("1 Stunde") { caffeine.set(true, minutes: 60) }
                    Button("3 Stunden") { caffeine.set(true, minutes: 180) }
                    Button("Unbegrenzt") { caffeine.set(true) }
                    Button("Aus") { caffeine.set(false) }
                }
                ActionButton(icon: "circle.lefthalf.filled", title: "Dunkelmodus", height: 44) { QuickActions.toggleDarkMode() }
                ActionButton(icon: "lock.fill", title: "Sperren", height: 44) { QuickActions.lockScreen() }
                ActionButton(icon: "display", title: "Display aus", height: 44) { QuickActions.sleepDisplay() }
                ActionButton(icon: "moon.zzz.fill", title: "Ruhezustand", height: 44) { QuickActions.sleepNow() }
                ActionButton(icon: "sparkles.tv", title: "Schoner", height: 44) { QuickActions.screenSaver() }
                ActionButton(icon: micMuted ? "mic.slash.fill" : "mic.fill", title: "Mikrofon",
                             active: micMuted, height: 44) {
                    QuickActions.toggleMic { muted in
                        micMuted = muted
                        m.show(.symbol(muted ? "mic.slash.fill" : "mic.fill", muted ? "Mikro stumm" : "Mikro an"))
                    }
                }
                ActionButton(icon: "wifi", title: "WLAN", height: 44) {
                    QuickActions.toggleWiFi { on in
                        guard let on else { return }
                        m.show(.symbol(on ? "wifi" : "wifi.slash", on ? "WLAN an" : "WLAN aus"))
                    }
                }
                ActionButton(icon: "menubar.dock.rectangle", title: "Schreibtisch",
                             active: desktopHidden, height: 44) {
                    QuickActions.toggleFinderFlag("CreateDesktop", defaultOn: true) { on in
                        desktopHidden = !on
                        m.show(.symbol("menubar.dock.rectangle", on ? "Icons sichtbar" : "Icons versteckt"))
                    }
                }
                ActionButton(icon: "eye.slash", title: "Versteckte", active: hiddenFiles, height: 44) {
                    QuickActions.toggleFinderFlag("AppleShowAllFiles", defaultOn: false) { on in
                        hiddenFiles = on
                        m.show(.symbol(on ? "eye" : "eye.slash", on ? "Alle Dateien" : "Versteckt"))
                    }
                }
            }
            .frame(width: 300)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "function").font(.system(size: 11)).foregroundColor(.gray)
                    TextField("Rechnen: 12*3+4", text: $expr)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit {
                            if let r = result {
                                m.clipboard.copy(r)
                                m.show(.symbol("function", "= \(r) kopiert"))
                            }
                        }
                    if let r = result {
                        Text("= \(r)").font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .lineLimit(1).foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))

                HStack {
                    SectionTitle("Notiz")
                    Spacer()
                    if !note.isEmpty {
                        Button { m.clipboard.copy(note); m.show(.symbol("doc.on.doc", "Notiz kopiert")) } label: {
                            Image(systemName: "doc.on.doc").font(.system(size: 10))
                        }.buttonStyle(.plain).foregroundColor(.gray).help("Notiz kopieren")
                    }
                }
                TextEditor(text: $note)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

// MARK: - Tab: Zwischenablage

struct ClipboardTab: View {
    @ObservedObject var clip: ClipboardMonitor
    @ObservedObject var m: Model
    @AppStorage("accent") private var accentName = "orange"
    @AppStorage("clipPaste") private var clipPaste = false
    @State private var query = ""

    var entries: [String] {
        let all = clip.pinned + clip.items.filter { !clip.pinned.contains($0) }
        return query.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    func use(_ s: String) {
        clip.copy(s)
        if clipPaste {
            m.pinned = false
            m.setExpanded(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { pasteIntoFrontApp() }
        } else {
            m.show(.symbol("doc.on.clipboard", "Kopiert"))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(.gray)
                TextField("Verlauf durchsuchen …", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 12))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundColor(.gray)
                }
                Text("\(clip.items.count)").font(.system(size: 10).monospacedDigit()).foregroundColor(.gray)
                if !clip.items.isEmpty {
                    Button("Löschen") { clip.clear() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))

            if entries.isEmpty {
                Text(query.isEmpty ? "Kopierte Texte erscheinen hier. Klick kopiert erneut, Rechtsklick zum Anheften."
                                   : "Nichts gefunden")
                    .font(.system(size: 12)).foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(entries, id: \.self) { s in row(s) }
                    }
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    func row(_ s: String) -> some View {
        let isPinned = clip.pinned.contains(s)
        return HStack(spacing: 6) {
            if isPinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(notchAccent(accentName))
            }
            Text(s.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 11)).lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { clip.togglePin(s) } label: {
                Image(systemName: isPinned ? "pin.slash" : "pin").font(.system(size: 10))
            }
            .buttonStyle(.plain).foregroundColor(.gray)
            .help(isPinned ? "Lösen" : "Anheften (bleibt gespeichert)")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(isPinned ? 0.12 : 0.08)))
        .contentShape(Rectangle())
        .onTapGesture { use(s) }
        .contextMenu {
            Button("Kopieren") { clip.copy(s) }
            Button("Einfügen") {
                clip.copy(s)
                m.pinned = false
                m.setExpanded(false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { pasteIntoFrontApp() }
            }
            Button(isPinned ? "Lösen" : "Anheften") { clip.togglePin(s) }
            if let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme?.hasPrefix("http") == true {
                Button("Link öffnen") { NSWorkspace.shared.open(u) }
            }
            Divider()
            Button("Entfernen") { clip.remove(s) }
        }
    }
}

// MARK: - Tab: Ablage & Downloads

struct FileTile: View {
    let url: URL
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 48, height: 48)
            Text(url.lastPathComponent)
                .font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).frame(width: 74)
        }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .help(url.path)
    }
}

struct ShelfTab: View {
    @ObservedObject var m: Model
    @ObservedObject var dl: DownloadsMonitor
    let dropping: Bool
    @State private var mode = 0

    var shelfTitle: String { m.shelf.isEmpty ? "Ablage" : "Ablage (" + String(m.shelf.count) + ")" }
    var downloadsTitle: String { dl.active.isEmpty ? "Downloads" : "Downloads ↓" + String(dl.active.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(shelfTitle) { mode = 0 }.buttonStyle(Chip(active: mode == 0))
                Button(downloadsTitle) { mode = 1 }.buttonStyle(Chip(active: mode == 1))
                Spacer()
                if mode == 0 && !m.shelf.isEmpty {
                    Button { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: m.shelf) } label: {
                        Label("AirDrop", systemImage: "dot.radiowaves.left.and.right")
                    }
                    Button {
                        QuickActions.zip(m.shelf) { out in
                            if let out {
                                NSWorkspace.shared.activateFileViewerSelecting([out])
                                m.show(.symbol("doc.zipper", "ZIP erstellt"))
                            } else {
                                m.show(.symbol("exclamationmark.triangle", "ZIP fehlgeschlagen"))
                            }
                        }
                    } label: { Label("ZIP", systemImage: "doc.zipper") }
                    Button("Leeren") { m.shelf.removeAll() }
                }
                if mode == 1 {
                    Button { NSWorkspace.shared.open(dl.folder) } label: { Label("Ordner", systemImage: "folder") }
                }
            }
            .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.gray)

            if mode == 0 { shelf } else { downloads }
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .onChange(of: dropping) { _, d in if d { mode = 0 } }
    }

    @ViewBuilder var shelf: some View {
        if m.shelf.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 22))
                Text("Dateien hierher ziehen – bleiben auch nach Neustart erhalten").font(.caption)
            }
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundColor(dropping ? .orange : .gray.opacity(0.6)))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(m.shelf, id: \.self) { url in
                        FileTile(url: url).contextMenu { fileMenu(url, inShelf: true) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder var downloads: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !dl.active.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Lädt: " + dl.active.joined(separator: ", "))
                        .font(.system(size: 11)).lineLimit(1)
                }
            }
            if dl.recent.isEmpty {
                Text(Model.flag("watchDownloads", true) ? "Noch keine Downloads" : "Downloads-Beobachtung ist aus (Einstellungen)")
                    .font(.caption).foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(dl.recent, id: \.self) { url in
                            FileTile(url: url).contextMenu { fileMenu(url, inShelf: false) }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder func fileMenu(_ url: URL, inShelf: Bool) -> some View {
        Button("Öffnen") { NSWorkspace.shared.open(url) }
        Button("Übersicht (Quick Look)") { spawn("/usr/bin/qlmanage", ["-p", url.path]) }
        Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Button("Pfad kopieren") { m.clipboard.copy(url.path) }
        Button("Per AirDrop senden") { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url]) }
        Divider()
        if inShelf {
            Button("Aus Ablage entfernen") { m.shelf.removeAll { $0 == url } }
        } else if !m.shelf.contains(url) {
            Button("In die Ablage") { m.shelf.append(url) }
        }
    }
}

// MARK: - Tab: System

struct SystemTab: View {
    @ObservedObject var stats: SystemStats

    func tile(_ icon: String, _ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.system(size: 9, weight: .semibold)).foregroundColor(.gray)
            Text(value).font(.system(size: 12, weight: .medium).monospacedDigit()).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
    }

    var batteryValue: String {
        var s = "\(stats.health) % · \(stats.cycles) Zyklen"
        if stats.timeLeft > 0 { s = formatUptime(stats.timeLeft) + " übrig" }
        return s
    }

    func bar(_ frac: Double, _ color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(color).frame(width: g.size.width * CGFloat(min(1, max(0, frac))))
            }
        }
        .frame(height: 6)
    }

    var cpuColor: Color { stats.cpu > 0.8 ? .red : (stats.cpu > 0.5 ? .yellow : .green) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("CPU", systemImage: "cpu").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.0f %%", stats.cpu * 100)).font(.system(size: 12).monospacedDigit())
                }
                ZStack {
                    Sparkline(values: stats.cpuHistory)
                        .stroke(cpuColor, lineWidth: 1.5)
                }
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("RAM", systemImage: "memorychip").font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("\(formatGB(stats.memUsed)) / \(formatGB(stats.memTotal))")
                            .font(.system(size: 10).monospacedDigit())
                    }
                    bar(stats.memUsed / max(stats.memTotal, 1), .orange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("SSD", systemImage: "internaldrive").font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("\(formatGB(stats.diskFree)) frei")
                            .font(.system(size: 10).monospacedDigit())
                    }
                    bar(1 - stats.diskFree / max(stats.diskTotal, 1), .blue)
                }
            }
            HStack(spacing: 8) {
                tile("arrow.down.circle.fill", "Download", formatRate(stats.down))
                tile("arrow.up.circle.fill", "Upload", formatRate(stats.up))
                tile("clock.arrow.circlepath", "Laufzeit", formatUptime(stats.uptime))
                if stats.hasBatteryInfo {
                    tile("battery.100", "Akku", batteryValue)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .onAppear { stats.sample() }
    }
}

// MARK: - Tab: Einstellungen (schnell)

struct SettingsTab: View {
    @ObservedObject var m: Model
    @ObservedObject var updater: Updater
    @AppStorage("hoverOpen") private var hoverOpen = true
    @AppStorage("haptic") private var haptic = true
    @AppStorage("showMediaInNotch") private var showMedia = true
    @AppStorage("notifyBattery") private var notifyBattery = true
    @AppStorage("notifyEvents") private var notifyEvents = true
    @AppStorage("clipboardEnabled") private var clipboardEnabled = true
    @AppStorage("lockScreenOverlay") private var lockOverlay = true
    @AppStorage("hideInFullscreen") private var hideFullscreen = true
    @AppStorage("notchOutline") private var outline = false
    @AppStorage("watchDownloads") private var watchDownloads = true
    @AppStorage("workMin") private var workMin = 25
    @AppStorage("breakMin") private var breakMin = 5
    @State private var autostart = SMAppService.mainApp.status == .enabled

    func toggle(_ title: String, _ b: Binding<Bool>) -> some View {
        Toggle(title, isOn: b).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button { SettingsWindow.show() } label: { Label("Alle Einstellungen…", systemImage: "gearshape") }
                        .buttonStyle(Chip(active: true))
                    if updater.available, let v = updater.latest {
                        Button { updater.openDownload() } label: { Label("Update \(v) laden", systemImage: "arrow.down.app") }
                            .buttonStyle(Chip(active: true))
                    } else {
                        Button { updater.check() } label: {
                            Label(updater.checking ? "Prüfe…" : "Nach Updates suchen", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(Chip())
                    }
                    Spacer()
                    Text("v\(appVersion)").font(.system(size: 10)).foregroundColor(.gray)
                }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    toggle("Beim Hover öffnen", $hoverOpen)
                    toggle("Haptisches Feedback", $haptic)
                    toggle("Musik in der Notch", $showMedia)
                    toggle("Akku-Hinweise", $notifyBattery)
                    toggle("Termin-Erinnerung", $notifyEvents)
                    toggle("Zwischenablage-Verlauf", $clipboardEnabled)
                    toggle("Über Sperrbildschirm", $lockOverlay)
                    toggle("Im Vollbild ausblenden", $hideFullscreen)
                    toggle("Umriss zeigen", $outline)
                    toggle("Downloads beobachten", $watchDownloads)
                    toggle("Beim Anmelden starten", Binding(get: { autostart }, set: { v in
                        do {
                            if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch { dlog("Autostart: \(error)") }
                        autostart = SMAppService.mainApp.status == .enabled
                    }))
                }
                HStack(spacing: 18) {
                    Stepper("Fokus: \(workMin) Min", value: $workMin, in: 5...120, step: 5)
                        .onChange(of: workMin) { _, _ in m.applyTimerSettings() }
                    Stepper("Pause: \(breakMin) Min", value: $breakMin, in: 1...30)
                        .onChange(of: breakMin) { _, _ in m.applyTimerSettings() }
                }
                .font(.system(size: 11))
                Text("⌃⌥N öffnet/fixiert die Notch · Wischen mit zwei Fingern wechselt den Bereich.")
                    .font(.system(size: 10)).foregroundColor(.gray)
            }
            .padding(.vertical, 6)
        }
    }
}
