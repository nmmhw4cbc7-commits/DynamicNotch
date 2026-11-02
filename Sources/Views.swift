import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Kleine Bausteine

struct EqualizerView: View {
    var color: Color = .green
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(color)
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
    var color: Color = .white
    let onSeek: (Double) -> Void
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { g in
            let cur = dragging ?? value
            let frac: Double = total > 0 ? min(1, max(0, cur / total)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25)).frame(height: 5)
                Capsule().fill(color).frame(width: g.size.width * CGFloat(frac), height: 5)
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
    var height: CGFloat = 52
    let action: () -> Void
    @AppStorage("accent") private var accentName = "orange"
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: height < 50 ? 3 : 4) {
                Image(systemName: icon).font(.system(size: height < 50 ? 14 : 17))
                Text(title).font(.system(size: height < 50 ? 8.5 : 9)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 11)
                .fill(active ? notchAccent(accentName).opacity(0.85) : Color.white.opacity(hover ? 0.18 : 0.10)))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(title)
    }
}

struct Chip: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.28 : (active ? 0.22 : 0.10))))
            .contentShape(Capsule())
    }
}

struct SectionTitle: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundColor(.gray)
    }
}

func formatTime(_ s: Double) -> String {
    let i = max(0, Int(s))
    return String(format: "%d:%02d", i / 60, i % 60)
}

// MARK: - Haupt-View

enum LiveKind: Equatable { case none, timer, pomodoro, stopwatch, download, media }

struct NotchView: View {
    @ObservedObject var m: Model
    @ObservedObject var np: NowPlayingMonitor
    @ObservedObject var qt: QuickTimer
    @ObservedObject var sw: Stopwatch
    @ObservedObject var dl: DownloadsMonitor
    let notchW: CGFloat
    let notchH: CGFloat
    @State private var dropping = false
    @AppStorage("showMediaInNotch") private var showMediaInNotch = true
    @AppStorage("hoverOpen") private var hoverOpen = true
    @AppStorage("showEqualizer") private var showEq = true
    @AppStorage("artInNotch") private var artInNotch = true
    @AppStorage("accent") private var accentName = "orange"
    @AppStorage("hiddenTabs") private var hiddenTabs = ""
    @AppStorage("notchOutline") private var outline = false
    @AppStorage("liveTimers") private var liveTimers = true
    @AppStorage("liveDownloads") private var liveDownloads = true

    static let panelW: CGFloat = 580
    static let panelH: CGFloat = 320
    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)

    var accent: Color { notchAccent(accentName) }
    var open: Bool { (m.expanded || dropping) && !m.locked }
    var showHUD: Bool { !open && m.hud != .idle }
    var mediaLive: Bool { showMediaInNotch && np.isPlaying && !m.locked }

    var live: LiveKind {
        if m.locked { return .none }
        if liveTimers && qt.active { return .timer }
        if m.running { return .pomodoro }
        if liveTimers && sw.running { return .stopwatch }
        if liveDownloads && !dl.active.isEmpty { return .download }
        if mediaLive { return .media }
        return .none
    }

    var sideW: CGFloat {
        switch live {
        case .none: return 0
        case .timer, .stopwatch: return 54
        case .pomodoro: return 46
        case .download, .media: return 40
        }
    }

    var wing: CGFloat {
        if case .focus = m.hud { return 100 }
        if case .symbol = m.hud { return 116 }
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
            } else if live != .none {
                collapsedLive
            }
        }
        .frame(width: w, height: h)
        .overlay(alignment: .top) {
            if (m.hud == .locked && !open) || outline {
                shape.strokeBorder(Color.white.opacity(m.hud == .locked && !open ? 0.6 : 0.22), lineWidth: 1.2)
                    .mask(VStack(spacing: 0) { Color.clear.frame(height: 3); Color.black })
            }
        }
        .overlay(alignment: .bottom) {
            if !open && !showHUD && live == .timer {
                Capsule().fill(accent)
                    .frame(width: max(0, (w - 2 * radius) * CGFloat(qt.progress(m.now))), height: 2)
                    .padding(.bottom, 1)
                    .animation(.linear(duration: 0.5), value: m.now)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in m.hoverChanged(hovering, hoverOpen: hoverOpen) }
        .onTapGesture { if !open { m.setExpanded(true) } }
        .onDrop(of: [.fileURL], isTargeted: $dropping, perform: handleDrop)
        .onChange(of: dropping) { _, isOn in if isOn { m.tab = .shelf } }
        .animation(spring, value: open)
        .animation(spring, value: live)
        .animation(spring, value: m.hud)
        .contextMenu {
            Button(m.pinned ? "Notch lösen" : "Notch offen halten") { m.toggleOpen() }
            Menu("Timer starten") {
                ForEach([1, 5, 10, 15, 25, 30, 60], id: \.self) { n in
                    Button("\(n) Minuten") { qt.start(minutes: n) }
                }
                if qt.active { Divider(); Button("Timer abbrechen") { qt.cancel() } }
            }
            Button(m.caffeine.on ? "Koffein aus" : "Koffein an") { m.caffeine.toggle() }
            Divider()
            Button(MediaKeys.isActive ? "Tastenabfang aktiv ✓" : "Bedienungshilfen-Zugriff öffnen…") {
                if !MediaKeys.isActive,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Einstellungen…") { SettingsWindow.show() }
            Button("Nach Updates suchen") {
                m.updater.check { avail in
                    if avail { m.updater.openDownload() } else { m.show(.symbol("checkmark.seal.fill", "Aktuell (\(appVersion))")) }
                }
            }
            Button("DynamicNotch beenden") { NSApp.terminate(nil) }
        }
        .frame(width: Self.panelW, height: Self.panelH, alignment: .top)
    }

    // MARK: Eingeklappt mit Live-Inhalt

    var collapsedLive: some View {
        HStack(spacing: 0) {
            liveLeft.frame(width: sideW)
            Spacer(minLength: 0)
            liveRight.frame(width: sideW)
        }
        .frame(height: notchH)
    }

    @ViewBuilder var liveLeft: some View {
        switch live {
        case .timer:
            Image(systemName: qt.running ? "timer" : "pause.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(accent)
        case .pomodoro:
            Image(systemName: m.onBreak ? "cup.and.saucer.fill" : "brain.head.profile")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(accent)
        case .stopwatch:
            Image(systemName: "stopwatch")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(accent)
        case .download:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.blue)
                .symbolEffect(.pulse)
        case .media:
            if artInNotch { miniArt } else { Color.clear }
        case .none:
            Color.clear
        }
    }

    @ViewBuilder var liveRight: some View {
        switch live {
        case .timer:
            liveText(formatClock(qt.left(m.now)))
        case .pomodoro:
            liveText(m.timeString)
        case .stopwatch:
            liveText(formatClock(Int(sw.elapsed(m.now))))
        case .download:
            liveText(dl.active.count > 1 ? "\(dl.active.count)×" : "…", color: .blue)
        case .media:
            if showEq { EqualizerView(color: np.tint ?? .green) } else { Color.clear }
        case .none:
            Color.clear
        }
    }

    func liveText(_ s: String, color: Color? = nil) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundColor(color ?? accent)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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
                .font(.system(size: 13, weight: .semibold)).foregroundColor(accent)
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
                .truncationMode(.middle)
                .foregroundColor(.white)
                .padding(.trailing, 6)
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
        case .home: HomeTab(m: m, weather: m.weather)
        case .media: MediaTab(np: m.nowPlaying, m: m)
        case .timer: TimerTab(m: m, qt: qt, sw: sw)
        case .tools: ToolsTab(m: m, caffeine: m.caffeine)
        case .clipboard: ClipboardTab(clip: m.clipboard, m: m)
        case .shelf: ShelfTab(m: m, dl: dl, dropping: dropping)
        case .system: SystemTab(stats: m.stats)
        case .settings: SettingsTab(m: m, updater: m.updater)
        }
    }

    func badge(_ t: NotchTab) -> Bool {
        switch t {
        case .timer: return qt.active || sw.running
        case .media: return np.isPlaying
        case .shelf: return !dl.active.isEmpty
        default: return false
        }
    }

    var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.visible(hidden: hiddenTabs)) { t in
                Button { withAnimation(.easeInOut(duration: 0.18)) { m.tab = t } } label: {
                    Image(systemName: t.icon)
                        .font(.system(size: 13))
                        .frame(width: 34, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(m.tab == t ? Color.white.opacity(0.18) : Color.clear))
                        .foregroundColor(m.tab == t ? .white : .gray)
                        .overlay(alignment: .topTrailing) {
                            if badge(t) && m.tab != t {
                                Circle().fill(accent).frame(width: 5, height: 5).offset(x: -5, y: 4)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
            Spacer()
            Text(m.tab.title).font(.system(size: 10, weight: .medium)).foregroundColor(.gray)
            Button { m.togglePinned() } label: {
                Image(systemName: m.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 26)
                    .foregroundColor(m.pinned ? accent : .gray)
            }
            .buttonStyle(.plain)
            .help("Notch offen halten (⌃⌥N)")
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
                    m.show(.symbol("tray.and.arrow.down.fill", url.lastPathComponent), hideAfter: 1.4)
                }
            }
        }
        return true
    }
}
