import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Kleine Bausteine

struct EqualizerView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(Color.green)
                        .frame(width: 2.5, height: 4 + 10 * CGFloat(abs(sin(t * 4 + Double(i) * 1.3))))
                }
            }
            .frame(height: 16)
        }
    }
}

struct Sparkline: Shape {
    let values: [Double]
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard values.count > 1 else { return p }
        for (i, v) in values.enumerated() {
            let x = r.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = r.height * (1 - CGFloat(min(1, max(0, v))))
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

struct SeekBar: View {
    let value: Double
    let total: Double
    let onSeek: (Double) -> Void
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { g in
            let cur = dragging ?? value
            let frac: Double = total > 0 ? min(1, max(0, cur / total)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25)).frame(height: 5)
                Capsule().fill(Color.white).frame(width: g.size.width * CGFloat(frac), height: 5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let f = min(1, max(0, Double(v.location.x / max(g.size.width, 1))))
                        dragging = f * total
                    }
                    .onEnded { v in
                        let f = min(1, max(0, Double(v.location.x / max(g.size.width, 1))))
                        dragging = nil
                        onSeek(f * total)
                    }
            )
        }
        .frame(height: 14)
    }
}

struct ActionButton: View {
    let icon: String
    let title: String
    var active = false
    let action: () -> Void
    @AppStorage("accent") private var accentName = "orange"

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 17))
                Text(title).font(.system(size: 9)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(active ? accentColor(accentName).opacity(0.85) : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

func formatTime(_ s: Double) -> String {
    let i = max(0, Int(s))
    return String(format: "%d:%02d", i / 60, i % 60)
}

// MARK: - Tab: Übersicht

struct HomeTab: View {
    @ObservedObject var m: Model
    @AppStorage("accent") private var accentName = "orange"
    @AppStorage("clock24") private var clock24 = true
    @AppStorage("showSeconds") private var showSeconds = false
    @AppStorage("showDate") private var showDate = true

    var clockString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        let base = clock24 ? "HH:mm" : "h:mm"
        f.dateFormat = showSeconds ? base + ":ss" : base
        return f.string(from: m.now)
    }

    static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM"
        return f
    }()
    static let clockFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    static let eventFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EE HH:mm"
        return f
    }()

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
        let mins = Int(e.start.timeIntervalSince(m.now) / 60)
        if e.start <= m.now { return "läuft" }
        if mins < 60 { return "in \(max(mins, 1)) Min" }
        return HomeTab.eventFmt.string(from: e.start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clockString)
                        .font(.system(size: showSeconds ? 34 : 40, weight: .semibold, design: .rounded))
                    if showDate {
                        Text(HomeTab.dateFmt.string(from: m.now))
                            .font(.system(size: 12)).foregroundColor(.gray)
                    }
                    Label("\(m.battery)%", systemImage: batteryIcon)
                        .font(.system(size: 12))
                        .foregroundColor(m.battery < 15 && !m.charging ? .red : .white)
                }
                .frame(width: 170, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Termine").font(.system(size: 10, weight: .semibold)).foregroundColor(.gray)
                    if m.events.isEmpty {
                        Text("Keine Termine in den nächsten 48 h")
                            .font(.system(size: 12)).foregroundColor(.gray)
                    } else {
                        ForEach(m.events.prefix(3)) { e in
                            HStack(spacing: 8) {
                                Circle().fill(e.color).frame(width: 7, height: 7)
                                Text(e.title).font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(relative(e)).font(.system(size: 11)).foregroundColor(.gray)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            pomodoro
        }
        .padding(.bottom, 8)
    }

    var pomodoro: some View {
        HStack(spacing: 10) {
            Image(systemName: m.onBreak ? "cup.and.saucer.fill" : "brain.head.profile")
                .foregroundColor(accentColor(accentName))
            Text(m.timeString).font(.system(size: 20, weight: .medium).monospacedDigit())
            Text(m.onBreak ? "Pause" : "Fokus").font(.caption).foregroundColor(.gray)
            if m.sessions > 0 {
                Text("· \(m.sessions) erledigt").font(.caption).foregroundColor(.gray)
            }
            Spacer()
            Button { m.running.toggle() } label: {
                Image(systemName: m.running ? "pause.fill" : "play.fill").frame(width: 28, height: 24)
            }.buttonStyle(.plain)
            Button { m.resetTimer() } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 28, height: 24)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
    }
}

// MARK: - Tab: Medien

struct MediaTab: View {
    @ObservedObject var np: NowPlayingMonitor

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
        HStack(spacing: 18) {
            artwork.frame(width: 130, height: 130)
            VStack(alignment: .leading, spacing: 6) {
                Text(t.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                Text(t.artist).font(.system(size: 13)).foregroundColor(.gray).lineLimit(1)
                Text(t.app).font(.system(size: 10)).foregroundColor(.gray.opacity(0.7))
                Spacer(minLength: 0)
                SeekBar(value: np.position, total: t.duration) { np.seek(to: $0) }
                HStack {
                    Text(formatTime(np.position)).font(.system(size: 10).monospacedDigit())
                    Spacer()
                    Text(formatTime(t.duration)).font(.system(size: 10).monospacedDigit())
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
            }
            .frame(maxHeight: 130)
        }
        .padding(.top, 6)
    }

    @ViewBuilder var artwork: some View {
        if let img = np.artwork {
            Image(nsImage: img).resizable().scaledToFill()
                .frame(width: 130, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.1))
                .overlay(Image(systemName: "music.note").font(.system(size: 34)).foregroundColor(.gray))
        }
    }
}

// MARK: - Tab: Werkzeuge

struct ToolsTab: View {
    @ObservedObject var m: Model
    @ObservedObject var caffeine: Caffeine
    @AppStorage("note") private var note = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ActionButton(icon: "camera.viewfinder", title: "Screenshot") { QuickActions.screenshot() }
                ActionButton(icon: "eyedropper", title: "Farbwähler") {
                    QuickActions.pickColor { hex in
                        DispatchQueue.main.async { m.show(.symbol("eyedropper", hex)) }
                    }
                }
                ActionButton(icon: "cup.and.saucer.fill", title: "Koffein", active: caffeine.on) {
                    caffeine.toggle()
                    m.show(.symbol("cup.and.saucer.fill", caffeine.on ? "Wach" : "Normal"))
                }
                ActionButton(icon: "circle.lefthalf.filled", title: "Dunkelmodus") { QuickActions.toggleDarkMode() }
                ActionButton(icon: "display", title: "Display aus") { QuickActions.sleepDisplay() }
                ActionButton(icon: "moon.stars.fill", title: "Schoner") { QuickActions.screenSaver() }
            }
            .frame(width: 250)

            VStack(alignment: .leading, spacing: 5) {
                Text("Notiz").font(.system(size: 10, weight: .semibold)).foregroundColor(.gray)
                TextEditor(text: $note)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 130)
        .padding(.top, 8)
    }
}

// MARK: - Tab: Zwischenablage

struct ClipboardTab: View {
    @ObservedObject var clip: ClipboardMonitor
    @ObservedObject var m: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Zwischenablage").font(.system(size: 10, weight: .semibold)).foregroundColor(.gray)
                Spacer()
                if !clip.items.isEmpty {
                    Button("Löschen") { clip.clear() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.gray)
                }
            }
            if clip.items.isEmpty {
                Text("Kopierte Texte erscheinen hier. Klick kopiert erneut.")
                    .font(.system(size: 12)).foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(Array(clip.items.enumerated()), id: \.offset) { _, s in
                            Button {
                                clip.copy(s)
                                m.show(.symbol("doc.on.clipboard", "Kopiert"))
                            } label: {
                                Text(s).font(.system(size: 11)).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Tab: Ablage

struct ShelfTab: View {
    @ObservedObject var m: Model
    let dropping: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Datei-Ablage").font(.system(size: 10, weight: .semibold)).foregroundColor(.gray)
                Spacer()
                if !m.shelf.isEmpty {
                    Button { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: m.shelf) } label: {
                        Label("AirDrop", systemImage: "dot.radiowaves.left.and.right")
                    }
                    Button("Leeren") { m.shelf.removeAll() }
                }
            }
            .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.gray)

            if m.shelf.isEmpty {
                Text("Dateien hierher ziehen")
                    .font(.caption).foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundColor(dropping ? .orange : .gray.opacity(0.6)))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(m.shelf, id: \.self) { url in
                            VStack(spacing: 4) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 48, height: 48)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 10)).lineLimit(2).frame(width: 74)
                            }
                            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                            .onTapGesture { NSWorkspace.shared.open(url) }
                            .contextMenu {
                                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                Button("Entfernen") { m.shelf.removeAll { $0 == url } }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Tab: System

struct SystemTab: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("CPU", systemImage: "cpu").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.0f %%", stats.cpu * 100)).font(.system(size: 12).monospacedDigit())
                }
                Sparkline(values: stats.cpuHistory)
                    .stroke(Color.green, lineWidth: 1.5)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Arbeitsspeicher", systemImage: "memorychip").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("\(formatGB(stats.memUsed)) / \(formatGB(stats.memTotal))")
                        .font(.system(size: 11).monospacedDigit())
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    GeometryReader { g in
                        Capsule().fill(Color.orange)
                            .frame(width: g.size.width * CGFloat(min(1, stats.memUsed / max(stats.memTotal, 1))))
                    }
                }.frame(height: 6)
            }
            HStack(spacing: 20) {
                Label(formatRate(stats.down), systemImage: "arrow.down.circle.fill")
                Label(formatRate(stats.up), systemImage: "arrow.up.circle.fill")
                Spacer()
            }
            .font(.system(size: 12).monospacedDigit())
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .onAppear { stats.sample() }
    }
}

// MARK: - Tab: Einstellungen

struct SettingsTab: View {
    @ObservedObject var m: Model
    @AppStorage("hoverOpen") private var hoverOpen = true
    @AppStorage("haptic") private var haptic = true
    @AppStorage("showMediaInNotch") private var showMedia = true
    @AppStorage("notifyBattery") private var notifyBattery = true
    @AppStorage("notifyEvents") private var notifyEvents = true
    @AppStorage("clipboardEnabled") private var clipboardEnabled = true
    @AppStorage("lockScreenOverlay") private var lockOverlay = true
    @AppStorage("workMin") private var workMin = 25
    @AppStorage("breakMin") private var breakMin = 5
    @State private var autostart = SMAppService.mainApp.status == .enabled

    func toggle(_ title: String, _ b: Binding<Bool>) -> some View {
        Toggle(title, isOn: b).toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                Button("Alle Einstellungen…") { SettingsWindow.show() }
                toggle("Beim Hover öffnen (sonst Klick)", $hoverOpen)
                toggle("Haptisches Feedback beim Öffnen", $haptic)
                toggle("Musik-Anzeige in der Notch", $showMedia)
                toggle("Akku-Hinweise (Laden, niedrig)", $notifyBattery)
                toggle("Termin-Erinnerung (5 Min vorher)", $notifyEvents)
                toggle("Zwischenablage-Verlauf", $clipboardEnabled)
                toggle("Anzeige über dem Sperrbildschirm", $lockOverlay)
                toggle("Beim Anmelden starten", Binding(get: { autostart }, set: { v in
                    do {
                        if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { dlog("Autostart: \(error)") }
                    autostart = SMAppService.mainApp.status == .enabled
                }))
                Stepper("Fokus-Dauer: \(workMin) Min", value: $workMin, in: 5...90, step: 5)
                    .font(.system(size: 12))
                    .onChange(of: workMin) { _, _ in m.applyTimerSettings() }
                Stepper("Pausen-Dauer: \(breakMin) Min", value: $breakMin, in: 1...30)
                    .font(.system(size: 12))
                    .onChange(of: breakMin) { _, _ in m.applyTimerSettings() }
                Text("⌃⌥N öffnet/fixiert die Notch (braucht Bedienungshilfen).")
                    .font(.system(size: 10)).foregroundColor(.gray)
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Haupt-View

struct NotchView: View {
    @ObservedObject var m: Model
    @ObservedObject var np: NowPlayingMonitor
    let notchW: CGFloat
    let notchH: CGFloat
    @State private var dropping = false
    @AppStorage("showMediaInNotch") private var showMediaInNotch = true
    @AppStorage("hoverOpen") private var hoverOpen = true
    @AppStorage("showEqualizer") private var showEq = true
    @AppStorage("artInNotch") private var artInNotch = true
    @AppStorage("accent") private var accentName = "orange"

    static let panelW: CGFloat = 540
    static let panelH: CGFloat = 300
    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)

    var open: Bool { (m.expanded || dropping) && !m.locked }
    var showHUD: Bool { !open && m.hud != .idle }
    var mediaLive: Bool { showMediaInNotch && np.isPlaying && !m.locked }
    var sideW: CGFloat { m.running ? 45 : (mediaLive ? 40 : 0) }
    var wing: CGFloat {
        if case .focus = m.hud { return 100 }
        if case .symbol = m.hud { return 112 }
        return 56
    }
    var w: CGFloat {
        if open { return Self.panelW }
        if showHUD { return notchW + 2 * wing }
        return notchW + 2 * sideW
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
            } else if m.running || mediaLive {
                collapsedLive
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
        .onHover { hovering in m.hoverChanged(hovering, hoverOpen: hoverOpen) }
        .onTapGesture { if !open { m.setExpanded(true) } }
        .onDrop(of: [.fileURL], isTargeted: $dropping, perform: handleDrop)
        .onChange(of: dropping) { _, isOn in if isOn { m.tab = .shelf } }
        .animation(spring, value: open)
        .animation(spring, value: m.running)
        .animation(spring, value: mediaLive)
        .animation(spring, value: m.hud)
        .contextMenu {
            Button(MediaKeys.isActive ? "Tastenabfang aktiv ✓" : "Bedienungshilfen-Zugriff öffnen…") {
                if !MediaKeys.isActive,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Einstellungen…") { SettingsWindow.show() }
            Button("DynamicNotch beenden") { NSApp.terminate(nil) }
        }
        .frame(width: Self.panelW, height: Self.panelH, alignment: .top)
    }

    // MARK: Eingeklappt mit Live-Inhalt

    var collapsedLive: some View {
        HStack(spacing: 0) {
            Group {
                if mediaLive && artInNotch { miniArt } else { Color.clear }
            }.frame(width: sideW)
            Spacer(minLength: 0)
            Group {
                if m.running {
                    Text(m.timeString)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(accentColor(accentName))
                } else if showEq {
                    EqualizerView()
                } else {
                    Color.clear
                }
            }.frame(width: sideW)
        }
        .frame(height: notchH)
    }

    @ViewBuilder var miniArt: some View {
        if let img = np.artwork {
            Image(nsImage: img).resizable().scaledToFill()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "music.note").font(.system(size: 12)).foregroundColor(.green)
        }
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

    var expandedContent: some View {
        VStack(spacing: 0) {
            tabContent
                .padding(.top, notchH + 2)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            tabBar
        }
        .foregroundColor(.white)
    }

    @ViewBuilder var tabContent: some View {
        switch m.tab {
        case .home: HomeTab(m: m)
        case .media: MediaTab(np: m.nowPlaying)
        case .tools: ToolsTab(m: m, caffeine: m.caffeine)
        case .clipboard: ClipboardTab(clip: m.clipboard, m: m)
        case .shelf: ShelfTab(m: m, dropping: dropping)
        case .system: SystemTab(stats: m.stats)
        case .settings: SettingsTab(m: m)
        }
    }

    var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases) { t in
                Button { m.tab = t } label: {
                    Image(systemName: t.icon)
                        .font(.system(size: 13))
                        .frame(width: 34, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(m.tab == t ? Color.white.opacity(0.18) : Color.clear))
                        .foregroundColor(m.tab == t ? .white : .gray)
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
            Spacer()
            Button { m.togglePinned() } label: {
                Image(systemName: m.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 26)
                    .foregroundColor(m.pinned ? accentColor(accentName) : .gray)
            }
            .buttonStyle(.plain)
            .help("Notch offen halten")
        }
        .padding(.horizontal, 18)
        .frame(height: 38)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    if !m.shelf.contains(url) { m.shelf.append(url) }
                    m.tab = .shelf
                }
            }
        }
        return true
    }
}
