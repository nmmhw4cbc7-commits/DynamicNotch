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

