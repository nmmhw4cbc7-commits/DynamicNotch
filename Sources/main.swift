import SwiftUI
import AppKit

// MARK: - Panel (kann Tastatureingaben annehmen, ohne die App zu aktivieren)

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NotchPanel!
    var model: Model!
    var statusItem: NSStatusItem?
    var notchScreen: NSScreen?
    private var swipeAcc: CGFloat = 0
    private var hiddenForFullscreen = false

    func applicationDidFinishLaunching(_ n: Notification) {
        UserDefaults.standard.register(defaults: [
            "hoverOpen": true, "haptic": true, "showMediaInNotch": true,
            "notifyBattery": true, "notifyEvents": true, "clipboardEnabled": true,
            "lockScreenOverlay": true, "workMin": 25, "breakMin": 5, "longBreakMin": 15, "longBreakEvery": 4,
            "openDelayMs": 0, "closeDelayMs": 250, "rememberTab": true, "defaultTab": "home", "hotkeyOn": true,
            "showMenuBarIcon": true, "accent": "orange", "clock24": true, "showSeconds": false, "showDate": true,
            "hudSeconds": 1.6, "spotifyOn": true, "musicOn": true, "showEqualizer": true, "artInNotch": true,
            "autoStartBreak": false, "autoStartWork": false, "timerSound": true, "timerSoundName": "Glass",
            "hudVolume": true, "hudBrightness": true, "hudFocus": true, "lowBattery": 20, "eventLead": 5,
            "clipMax": 25, "captureKeys": true,
            // neu in 3.0
            "hiddenTabs": "", "notchOutline": false, "hideInFullscreen": true, "swipeTabs": true,
            "watchDownloads": true, "notifyDownloads": true, "downloadsToShelf": false, "liveDownloads": true,
            "liveTimers": true, "weatherOn": true, "weatherCity": "", "notifyBluetooth": true,
            "checkUpdates": true, "welcomeHUD": true, "clipPaste": false, "chargeSound": false, "lastTimerMin": 10
        ])
        model = Model()
        panel = NotchPanel(contentRect: .zero,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        reposition()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.reposition() }
        panel.orderFrontRegardless()
        setupStatusItem()
        setupSwipe()
        every(1) { [weak self] in self?.checkFullscreen() }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.statusItem?.isVisible = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        }
        attachLock()
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.attachLock()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.attachLock() }
        }
    }

    // Menüleisten-Symbol mit Zugang zu den Einstellungen
    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "DynamicNotch")
        let menu = NSMenu()
        let s = NSMenuItem(title: "Einstellungen…", action: #selector(openSettings), keyEquivalent: ",")
        s.target = self
        let o = NSMenuItem(title: "Notch öffnen / fixieren", action: #selector(toggleNotch), keyEquivalent: "")
        o.target = self
        let t = NSMenuItem(title: "Timer 5 Minuten", action: #selector(timer5), keyEquivalent: "")
        t.target = self
        let u = NSMenuItem(title: "Nach Updates suchen…", action: #selector(checkUpdates), keyEquivalent: "")
        u.target = self
        let q = NSMenuItem(title: "DynamicNotch beenden", action: #selector(quit), keyEquivalent: "q")
        q.target = self
        let v = NSMenuItem(title: "DynamicNotch \(appVersion)", action: nil, keyEquivalent: "")
        v.isEnabled = false
        menu.addItem(v); menu.addItem(.separator())
        menu.addItem(s); menu.addItem(o); menu.addItem(t); menu.addItem(u); menu.addItem(.separator()); menu.addItem(q)
        item.menu = menu
        item.isVisible = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        statusItem = item
    }

    @objc func openSettings() { SettingsWindow.show() }
    @objc func toggleNotch() { model.toggleOpen() }
    @objc func timer5() { model.quickTimer.start(minutes: 5) }
    @objc func checkUpdates() {
        model.updater.check { [weak self] avail in
            guard let self else { return }
            if avail {
                self.model.updater.openDownload()
            } else {
                let a = NSAlert()
                a.messageText = "DynamicNotch ist aktuell"
                a.informativeText = "Du nutzt Version \(appVersion)."
                NSApp.activate(ignoringOtherApps: true)
                a.runModal()
            }
        }
    }

    // Zwei-Finger-Wischen im offenen Panel wechselt den Bereich
    func setupSwipe() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, e.window === self.panel, self.model.expanded,
                  Model.flag("swipeTabs", true), self.model.tab != .shelf else { return e }
            if e.phase == .began { self.swipeAcc = 0 }
            if abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) { self.swipeAcc += e.scrollingDeltaX }
            if e.phase == .ended || e.phase == .cancelled {
                if abs(self.swipeAcc) > 60 { self.model.switchTab(by: self.swipeAcc < 0 ? 1 : -1) }
                self.swipeAcc = 0
            }
            return e
        }
    }

    // Im Vollbild (Video, Spiele, Präsentationen) die Notch ausblenden
    func checkFullscreen() {
        let hide = Model.flag("hideInFullscreen", true) && !model.expanded && FullscreenCheck.active(on: notchScreen)
        guard hide != hiddenForFullscreen else { return }
        hiddenForFullscreen = hide
        panel.ignoresMouseEvents = hide
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            self.panel.animator().alphaValue = hide ? 0 : 1
        }
    }
    @objc func quit() { NSApp.terminate(nil) }

    // Abschalten: in den Einstellungen oder: defaults write local.dynamicnotch lockScreenOverlay -bool false
    func attachLock() {
        guard UserDefaults.standard.object(forKey: "lockScreenOverlay") as? Bool ?? true else { return }
        panel.orderFrontRegardless()
        LockSpace.attach(panel)
    }

    func reposition() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        notchScreen = screen
        // Ohne echte Notch wird automatisch eine "virtuelle" Notch gezeichnet.
        var notchW: CGFloat = 188
        var notchH: CGFloat = 32
        if screen.safeAreaInsets.top > 0,
           let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchW = screen.frame.width - l.width - r.width
            notchH = screen.safeAreaInsets.top
        }
        panel.contentView = NSHostingView(rootView: NotchView(m: model, np: model.nowPlaying,
                                                              qt: model.quickTimer, sw: model.stopwatch,
                                                              dl: model.downloads,
                                                              notchW: notchW, notchH: notchH))
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
