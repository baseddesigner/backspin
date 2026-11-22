// Backspin — a tiny helper that reverses and smooths scrolling for wheel mice only.
// Trackpad / Magic Mouse (continuous) events pass through untouched.
//
// Settings (read at launch):  defaults write io.github.baseddesigner.backspin <key> <value>
//   reverseVertical   bool   (default true)
//   reverseHorizontal bool   (default true)
//   smooth            bool   (default true)
//   step              float  minimum pixels per wheel notch (default 35)
//   speed             float  multiplier on the system's accelerated delta (default 3)
//   smoothing         float  easing time constant in seconds (default 0.08; higher = glidier)
// Run with --debug to log every wheel event.

import AppKit
import QuartzCore
import ApplicationServices

let MAGIC: Int64 = 0x4253_504E // "BSPN": marks events we synthesize so the tap ignores them

struct Config {
    var reverseVertical = true
    var reverseHorizontal = true
    var smooth = true
    var step = 35.0
    var speed = 3.0
    var smoothing = 0.08
    var debug = false

    static func load() -> Config {
        let d = UserDefaults.standard // domain = bundle id "io.github.baseddesigner.backspin"
        var c = Config()
        func b(_ k: String, _ v: inout Bool) { if d.object(forKey: k) != nil { v = d.bool(forKey: k) } }
        func n(_ k: String, _ v: inout Double) { if d.object(forKey: k) != nil { v = d.double(forKey: k) } }
        b("reverseVertical", &c.reverseVertical)
        b("reverseHorizontal", &c.reverseHorizontal)
        b("smooth", &c.smooth)
        n("step", &c.step)
        n("speed", &c.speed)
        n("smoothing", &c.smoothing)
        c.smoothing = max(0.005, c.smoothing)
        c.debug = CommandLine.arguments.contains("--debug")
        return c
    }
}

let cfg = Config.load()

func log(_ s: String) {
    FileHandle.standardError.write(("[Backspin] " + s + "\n").data(using: .utf8)!)
}

// MARK: - Smooth animator

/// The screen the mouse pointer is on (falls back to the main screen).
@MainActor func screenUnderCursor() -> NSScreen? {
    if let p = CGEvent(source: nil)?.location {
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(p, 1, &id, &count) == .success, count > 0,
           let s = NSScreen.screens.first(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
           }) {
            return s
        }
    }
    return NSScreen.main
}

/// Delivers held-back wheel notches as small pixel steps, one per frame of the
/// display the pointer is on (120 Hz on ProMotion, 60 Hz on most externals).
@MainActor final class Smoother: NSObject {
    private var pendingX = 0.0, pendingY = 0.0   // pixels still to deliver
    private var residX = 0.0, residY = 0.0       // sub-pixel carry
    private var flags: CGEventFlags = []
    private var link: CADisplayLink?
    private var lastTarget: CFTimeInterval = 0
    private var frameDuration = 1.0 / 60.0

    nonisolated override init() { super.init() }

    func add(dx: Double, dy: Double, flags: CGEventFlags) {
        // Reversing direction mid-glide: drop the old momentum so it feels snappy.
        if dy != 0, pendingY != 0, (dy > 0) != (pendingY > 0) { pendingY = 0; residY = 0 }
        if dx != 0, pendingX != 0, (dx > 0) != (pendingX > 0) { pendingX = 0; residX = 0 }
        pendingY += dy
        pendingX += dx
        self.flags = flags
        start()
    }

    private func start() {
        guard link == nil, let screen = screenUnderCursor() else { return }
        let fps = Float(max(screen.maximumFramesPerSecond, 30))
        frameDuration = 1.0 / Double(fps)
        let l = screen.displayLink(target: self, selector: #selector(frame(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, fps), maximum: fps, preferred: fps)
        l.add(to: .main, forMode: .common)
        link = l
        lastTarget = 0
        step(dt: frameDuration) // move on the very first notch, don't wait a frame
    }

    @objc private func frame(_ l: CADisplayLink) {
        let dt = lastTarget == 0 ? l.targetTimestamp - l.timestamp : l.targetTimestamp - lastTarget
        lastTarget = l.targetTimestamp
        step(dt: dt > 0 ? dt : frameDuration)
    }

    private func stop() {
        link?.invalidate()
        link = nil
        pendingX = 0; pendingY = 0; residX = 0; residY = 0
    }

    private func step(dt rawDt: Double) {
        let dt = min(max(rawDt, 1.0 / 480.0), 1.0 / 30.0)
        let k = 1 - exp(-dt / cfg.smoothing)

        var sy = pendingY * k, sx = pendingX * k
        if abs(pendingY) < 1 { sy = pendingY }
        if abs(pendingX) < 1 { sx = pendingX }
        pendingY -= sy; pendingX -= sx
        residY += sy; residX += sx

        let iy = residY.rounded(.towardZero), ix = residX.rounded(.towardZero)
        residY -= iy; residX -= ix
        if iy != 0 || ix != 0 { post(dx: Int32(ix), dy: Int32(iy)) }

        if pendingY == 0 && pendingX == 0 { stop() }
    }

    private func post(dx: Int32, dy: Int32) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                              wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: MAGIC)
        e.flags = flags
        e.post(tap: .cgSessionEventTap)
    }
}

@MainActor let smoother = Smoother()

// MARK: - Event tap

func negateAxis1(_ e: CGEvent) {
    let d = e.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    let f = e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
    let p = e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    e.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -d)
    e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -f)
    e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -p)
}

func negateAxis2(_ e: CGEvent) {
    let d = e.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let f = e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
    let p = e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
    e.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -d)
    e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -f)
    e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -p)
}

/// Pixels to scroll for one wheel event on one axis.
func pixels(line: Double, point: Double) -> Double {
    let ref = point != 0 ? point : line
    if ref == 0 { return 0 }
    return (ref > 0 ? 1 : -1) * max(abs(point) * cfg.speed, cfg.step)
}

@MainActor func handleWheel(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    var ly = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
    var lx = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
    var py = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
    var px = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
    let flags = event.flags

    if cfg.debug {
        log("wheel line=(\(ly),\(lx)) point=(\(py),\(px)) flags=\(String(flags.rawValue, radix: 16))")
    }

    if cfg.reverseVertical { ly = -ly; py = -py }
    if cfg.reverseHorizontal { lx = -lx; px = -px }

    // Cmd / Ctrl / Option + scroll is usually zoom or a special action: keep it un-smoothed.
    let zoomish = !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
    if !cfg.smooth || zoomish {
        if cfg.reverseVertical { negateAxis1(event) }
        if cfg.reverseHorizontal { negateAxis2(event) }
        return Unmanaged.passUnretained(event)
    }

    var dy = pixels(line: ly, point: py)
    var dx = pixels(line: lx, point: px)
    var outFlags = flags
    if flags.contains(.maskShift) {
        // Shift + wheel = horizontal scroll. Do the swap ourselves, since apps
        // don't swap precise (pixel) scroll events.
        if dx == 0 { dx = dy; dy = 0 }
        outFlags.remove(.maskShift)
    }
    smoother.add(dx: dx, dy: dy, flags: outFlags)
    return nil // swallow the original notch
}

var tap: CFMachPort?

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        log("tap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
        return Unmanaged.passUnretained(event)
    }
    guard type == .scrollWheel,
          event.getIntegerValueField(.eventSourceUserData) != MAGIC,
          event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 // trackpad / Magic Mouse
    else { return Unmanaged.passUnretained(event) }
    return MainActor.assumeIsolated { handleWheel(event) } // tap runs on the main run loop
}

func installTap() -> Bool {
    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                    options: .defaultTap, eventsOfInterest: mask,
                                    callback: callback, userInfo: nil) else { return false }
    tap = t
    let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    CGEvent.tapEnable(tap: t, enable: true)
    log("running — reverseV=\(cfg.reverseVertical) reverseH=\(cfg.reverseHorizontal) smooth=\(cfg.smooth) step=\(cfg.step) speed=\(cfg.speed) smoothing=\(cfg.smoothing)")
    return true
}

// MARK: - Main

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
    log("waiting for Accessibility permission (System Settings → Privacy & Security → Accessibility)")
}

// Retry until permission is granted and the tap is created.
func tryStart() {
    if AXIsProcessTrusted() && installTap() { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { tryStart() }
}
tryStart()

let app = NSApplication.shared
app.setActivationPolicy(.prohibited) // no Dock icon, no menu bar
app.run()
