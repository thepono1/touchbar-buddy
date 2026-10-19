import AppKit

// Private DFRFoundation hooks (same ones MTMR/Pock use) to pin an item in the Control Strip.
let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)
typealias SetPresence = @convention(c) (NSString, Bool) -> Void
typealias CloseBox = @convention(c) (Bool) -> Void
typealias Present = @convention(c) (AnyObject, Selector, NSTouchBar, Int64, NSString) -> Void
typealias Dismiss = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void

func sym<T>(_ n: String, _ t: T.Type) -> T? { dlsym(dfr, n).map { unsafeBitCast($0, to: t) } }

let trayID = NSTouchBarItem.Identifier("com.touchbarbuddy.tray")
let bigID = NSTouchBarItem.Identifier("com.touchbarbuddy.big")

final class Pikachu: NSView {
    var walking = false
    var x: CGFloat = 40, dir: CGFloat = 1, phase: CGFloat = 0, t: CGFloat = 0
    var hop = 0, shock = 0, said = 0, blink = 0, mode = 0, modeT = 90 // mode 0 crawl, 1 idle
    var line: String?
    var bolts: [[CGPoint]] = [] // offsets from a cheek, regenerated per frame so they flicker
    override var isFlipped: Bool { false }

    func zap() { shock = 18; hop = 10; line = ["Pika!", "Pikachu!", "Pika pika!", "Chuuu!"].randomElement(); said = 60 }
    override func mouseDown(with e: NSEvent) { zap() }

    func tick() {
        t += 0.2
        if walking {
            phase += mode == 0 ? 0.45 : mode == 2 ? 0.9 : 0
            modeT -= 1
            if modeT <= 0 {
                let r = Int.random(in: 0..<10); mode = r < 5 ? 0 : (r < 8 ? 1 : 2)
                modeT = mode == 1 ? .random(in: 70...130) : mode == 2 ? .random(in: 40...70) : .random(in: 90...170)
                if mode != 1 && Bool.random() { dir = -dir }
                if mode == 1 && Bool.random() { zap() } // spontaneous spark while resting
            }
            if mode != 1 {
                x += dir * (mode == 2 ? 2.6 : 0.8)
                if x > bounds.width - 40 { dir = -1 } else if x < 30 { dir = 1 }
            }
        }
        if blink > 0 { blink -= 1 } else if Int.random(in: 0..<90) == 0 { blink = 5 }
        if hop > 0 { hop -= 1 }
        if said > 0 { said -= 1; if said == 0 { line = nil } }
        if shock > 0 {
            shock -= 1
            bolts = (0..<3).map { _ in
                var a = CGFloat.random(in: 0..<(2 * .pi)), p = CGPoint.zero
                return (0..<4).map { _ in a += .random(in: -0.8...0.8); p.x += cos(a) * 3.5; p.y += sin(a) * 3.5; return p }
            }
        } else { bolts = [] }
        needsDisplay = true
    }

    func drawBolts(from o: CGPoint, sign: CGFloat) {
        for b in bolts {
            let path = NSBezierPath(); path.move(to: o)
            for q in b { path.line(to: CGPoint(x: o.x + q.x * sign, y: o.y + q.y)) }
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor(red: 0.55, green: 0.8, blue: 1, alpha: 0.9).setStroke(); path.lineWidth = 2.2; path.stroke()
            NSColor(red: 1, green: 0.92, blue: 0.3, alpha: 1).setStroke(); path.lineWidth = 1.3; path.stroke()
            NSColor.white.setStroke(); path.lineWidth = 0.6; path.stroke()
        }
    }

    override func draw(_ r: NSRect) {
        if shock > 12 { NSColor.yellow.withAlphaComponent(0.12).setFill(); bounds.fill() }
        let yellow = NSColor(red: 1, green: 0.85, blue: 0.1, alpha: 1)
        let shade = NSColor(red: 0.85, green: 0.65, blue: 0.05, alpha: 1)
        let red = NSColor(red: 0.95, green: 0.2, blue: 0.15, alpha: 1)
        let brown = NSColor(red: 0.45, green: 0.27, blue: 0.1, alpha: 1)
        let jump = hop > 0 ? sin(CGFloat(hop) / 10 * .pi) * 3.5 : 0
        let bob = walking && mode == 0 ? abs(sin(phase)) * 0.8 : 0
        let cx = walking ? x : bounds.midX, f = walking ? dir : 1
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        if walking { let tr = NSAffineTransform(); tr.translateX(by: cx, yBy: 0); tr.scale(by: mode == 0 ? 0.95 : 0.82); tr.translateX(by: -cx, yBy: 0); tr.concat() } // fit the 30pt bar
        func at(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: cx + dx * f, y: 1 + jump + bob + dy) }
        func oval(_ dx: CGFloat, _ dy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
            let o = at(dx, dy); c.setFill(); NSBezierPath(ovalIn: NSRect(x: o.x - w / 2, y: o.y - h / 2, width: w, height: h)).fill()
        }
        func poly(_ pts: [(CGFloat, CGFloat)], _ c: NSColor) {
            let p = NSBezierPath(); p.move(to: at(pts[0].0, pts[0].1)); pts.dropFirst().forEach { p.line(to: at($0.0, $0.1)) }
            p.close(); c.setFill(); p.fill()
        }
        func leg(_ hx: CGFloat, _ ph: CGFloat, _ c: NSColor) {
            let swing = walking && mode == 0 ? sin(ph) * 4 : 0, lift = walking && mode == 0 ? max(0, -cos(ph)) * 2.5 : 0
            let p = NSBezierPath(); p.move(to: at(hx, 7)); p.line(to: at(hx + swing, lift - jump * 0.5))
            p.lineWidth = 3.2; p.lineCapStyle = .round; c.setStroke(); p.stroke()
        }

        if walking { // side view: crawl (sniffing, low), sit (upright, nibbling), run (stretched leap)
            let run = mode == 2, sit = mode == 1
            let wag = sin(t * (sit ? 2 : 1)) * 2.5
            let belly = NSColor(red: 1, green: 0.93, blue: 0.55, alpha: 1)
            func fur(_ dx: CGFloat, _ dy: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                oval(dx, dy, w, h, yellow)
                let o = at(dx, dy); shade.withAlphaComponent(0.7).setStroke()
                let q = NSBezierPath(ovalIn: NSRect(x: o.x - w / 2, y: o.y - h / 2, width: w, height: h)); q.lineWidth = 0.6; q.stroke()
            }
            let hx: CGFloat, hy: CGFloat
            if sit {
                hx = 2; hy = 19 + (said > 0 ? 0 : sin(t * 3) * 0.5)
                poly([(-5, 6), (-12 + wag, 10), (-9 + wag, 12), (-15 + wag, 18), (-10 + wag, 18), (-17 + wag, 25), (-5, 12)], yellow)
                fur(0, 8, 12, 14); oval(1, 6.5, 7, 8, belly)
                oval(-3, 1.5, 5, 3, shade); oval(3, 1.5, 5, 3, yellow) // feet
                oval(5, 10, 3.5, 3, yellow); oval(7.5, 10.5, 3.2, 3.2, red) // paws holding a berry
            } else {
                hx = run ? 14 : 12; hy = run ? 14 : 11.5 + sin(t * 2) * 0.8 // head low, sniffing
                func leg(_ lx: CGFloat, _ ph: CGFloat, _ c: NSColor) {
                    let amp: CGFloat = run ? 6 : 3.5, lift: CGFloat = run ? 4 : 2.5
                    let p = NSBezierPath(); p.move(to: at(lx, 7)); p.line(to: at(lx + sin(ph) * amp, max(0, -cos(ph)) * lift - jump * 0.5))
                    p.lineWidth = 3.4; p.lineCapStyle = .round; c.setStroke(); p.stroke()
                }
                let lx: CGFloat = run ? 8 : 6
                leg(-lx, phase + .pi, shade); leg(lx, phase, shade)
                let up: CGFloat = run ? 3 : 0
                poly([(-8, 10), (-13 + wag, 14 + up), (-10 + wag, 16 + up), (-17 + wag, 22 + up), (-12 + wag, 22 + up), (-19 + wag, 29 + up), (-8, 17)], yellow)
                poly([(-8, 10), (-12, 11), (-10, 13)], brown)
                fur(0, run ? 9.5 : 10, run ? 24 : 18, run ? 9.5 : 11)
                oval(1, run ? 7.5 : 8, run ? 14 : 10, 4, belly)
                for sx in [-4.0, -1.0] { let q = NSBezierPath(); q.move(to: at(sx, 14)); q.line(to: at(sx - 1.5, 11)); q.lineWidth = 1.2; brown.setStroke(); q.stroke() }
                leg(-lx, phase, yellow); leg(lx, phase + .pi, yellow)
            }
            // ears: flat back when running, perked when sitting/sniffing
            let tilt: CGFloat = mode == 0 ? 0 : sin(t * 0.7) * 1.5
            if run {
                poly([(hx - 3, hy + 4), (hx - 14, hy + 8), (hx - 1, hy + 6)], yellow); poly([(hx - 11, hy + 7), (hx - 14, hy + 8), (hx - 9, hy + 6.5)], .black)
            } else {
                let ey = hy + 5
                poly([(hx - 3, ey), (hx - 7 - tilt, ey + 10), (hx, ey + 2)], yellow); poly([(hx - 5, ey + 6.5), (hx - 7 - tilt, ey + 10), (hx - 3.5, ey + 8)], .black)
                poly([(hx, ey), (hx - 1 + tilt, ey + 10), (hx + 4, ey + 1)], yellow); poly([(hx - 0.5, ey + 6.5), (hx - 1 + tilt, ey + 10), (hx + 1.5, ey + 8)], .black)
            }
            fur(hx, hy, 12, 10.5)
            if blink > 0 { let q = NSBezierPath(); q.move(to: at(hx + 2, hy + 1)); q.line(to: at(hx + 4.5, hy + 1)); q.lineWidth = 1; NSColor.black.setStroke(); q.stroke() }
            else { oval(hx + 3, hy + 1, 3.6, 4, .black); oval(hx + 3.6, hy + 2.2, 1.3, 1.3, .white); oval(hx + 2.4, hy - 0.2, 0.7, 0.7, .white) } // glossy eye
            let ck = at(hx, hy - 2.5)
            if shock > 0 || mode == 2 && Int.random(in: 0..<6) == 0 { // cheek glow before/while sparking
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(ovalIn: NSRect(x: ck.x - 7, y: ck.y - 7, width: 14, height: 14)).addClip()
                NSGradient(colors: [red.withAlphaComponent(0.9), red.withAlphaComponent(0)])?.draw(in: NSRect(x: ck.x - 7, y: ck.y - 7, width: 14, height: 14), relativeCenterPosition: .zero)
                NSGraphicsContext.restoreGraphicsState()
            }
            oval(hx, hy - 2.5, 4, 4, red); oval(hx + 6, hy - 0.5, 1.6, 1.1, .black)
            drawBolts(from: ck, sign: f)
            if let l = line {
                (l as NSString).draw(at: CGPoint(x: cx + 24 * f - (f < 0 ? 40 : 0), y: 12), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.white])
            }
        } else { // front-facing head for the tray
            let hy: CGFloat = 12
            poly([(-6, hy + 6), (-11, hy + 16), (-2, hy + 10)], yellow); poly([(6, hy + 6), (11, hy + 16), (2, hy + 10)], yellow)
            poly([(-9.5, hy + 13.5), (-11, hy + 16), (-7.5, hy + 12.5)], .black); poly([(9.5, hy + 13.5), (11, hy + 16), (7.5, hy + 12.5)], .black)
            oval(0, hy, 18, 14, yellow)
            if blink > 0 { for ex in [-4.0, 4.0] { let p = NSBezierPath(); p.move(to: at(ex - 1.5, hy + 1)); p.line(to: at(ex + 1.5, hy + 1)); p.lineWidth = 1; NSColor.black.setStroke(); p.stroke() } }
            else { oval(-4, hy + 1, 3, 3.5, .black); oval(4, hy + 1, 3, 3.5, .black); oval(-3.5, hy + 2, 1.2, 1.2, .white); oval(4.5, hy + 2, 1.2, 1.2, .white) }
            oval(-7, hy - 2.5, 4, 4, red); oval(7, hy - 2.5, 4, 4, red); oval(0, hy - 0.5, 1.5, 1, .black)
            drawBolts(from: at(-7, hy - 2.5), sign: -1); drawBolts(from: at(7, hy - 2.5), sign: 1)
        }
    }
}

final class App: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    let tray = Pikachu(frame: NSRect(x: 0, y: 0, width: 36, height: 30))
    let big = Pikachu(frame: NSRect(x: 220, y: 0, width: 160, height: 30)) // referee, between the fighters
    let arena = BattleView(frame: NSRect(x: 0, y: 0, width: 600, height: 30))
    var bar: NSTouchBar!

    func touchBar(_ tb: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let it = NSCustomTouchBarItem(identifier: id)
        it.view = arena
        arena.widthAnchor.constraint(equalToConstant: 600).isActive = true
        return it
    }

    func open() {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        guard let m = class_getClassMethod(NSTouchBar.self, sel) else { return }
        let f = unsafeBitCast(method_getImplementation(m), to: Present.self)
        f(NSTouchBar.self, sel, bar, 0, trayID.rawValue as NSString)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        big.walking = true
        bar = NSTouchBar(); bar.delegate = self
        bar.defaultItemIdentifiers = [bigID]
        sym("DFRSystemModalShowsCloseBoxWhenFrontMost", CloseBox.self)?(true)

        let trayItem = NSCustomTouchBarItem(identifier: trayID)
        let btn = NSButton(title: "", target: self, action: #selector(tap)); btn.isBordered = false
        tray.addSubview(btn); btn.frame = tray.bounds
        tray.translatesAutoresizingMaskIntoConstraints = false
        tray.widthAnchor.constraint(equalToConstant: 40).isActive = true
        trayItem.view = tray
        _ = (NSTouchBarItem.self as AnyObject).perform(NSSelectorFromString("addSystemTrayItem:"), with: trayItem)
        sym("DFRElementSetControlStripPresenceForIdentifier", SetPresence.self)?(trayID.rawValue as NSString, true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.open() } // placement 0: left/app region
        Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { _ in self.tray.tick(); self.big.tick(); self.arena.tick() }
    }
    @objc func tap() { tray.zap(); open() } // reopens the arena after the ✕ closed it
}

if CommandLine.arguments.contains("--battle-snap") { // 8 moments of a fight, stacked
    let sc: CGFloat = 2, n = 8, a = BattleView(frame: NSRect(x: 0, y: 0, width: 600, height: 30)); a.layout()
    let img = NSImage(size: NSSize(width: 600 * sc, height: 30 * sc * CGFloat(n)))
    img.lockFocus(); NSColor.black.setFill(); NSRect(origin: .zero, size: img.size).fill()
    for i in 0..<n {
        for _ in 0..<(i == 0 ? 45 : 22) { a.tick() }
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: 0, yBy: CGFloat(n - 1 - i) * 30 * sc); t.scale(by: sc); t.concat()
        NSBezierPath(rect: a.bounds).addClip(); a.draw(a.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
    img.unlockFocus()
    try? NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/battle_snap.png"))
    exit(0)
}
if CommandLine.arguments.contains("--snap") { // dump a zoomed preview sheet of each pose, then exit
    let sc: CGFloat = 4, rows: [(Int, Int)] = [(0, 0), (1, 0), (2, 0), (0, 18), (1, 18), (2, 18)]
    let img = NSImage(size: NSSize(width: 260 * sc, height: 30 * sc * CGFloat(rows.count)))
    img.lockFocus(); NSColor.black.setFill(); NSRect(origin: .zero, size: img.size).fill()
    for (i, r) in rows.enumerated() {
        let v = Pikachu(frame: NSRect(x: 0, y: 0, width: 260, height: 30)); v.walking = true; v.mode = r.0; v.x = 130; v.phase = 1.0; v.shock = r.1
        v.bolts = (0..<3).map { _ in var a = CGFloat.random(in: 0..<(2 * .pi)), p = CGPoint.zero; return (0..<4).map { _ in a += .random(in: -0.8...0.8); p.x += cos(a) * 3.5; p.y += sin(a) * 3.5; return p } }
        if r.1 == 0 { v.bolts = [] }
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: 0, yBy: CGFloat(rows.count - 1 - i) * 30 * sc); t.scale(by: sc); t.concat()
        v.draw(v.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/pika_snap.png"))
    exit(0)
}
let app = NSApplication.shared
let d = App(); app.delegate = d
app.run()
