import AppKit

// Animated Gen 5 battle sprites from Pokemon Showdown (sprites/), personal use only.
struct Sprite {
    var frames: [CGImage] = [], delay = 0.08
    init(_ name: String) {
        let dir = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("sprites")
        let url = ["gif", "png"].map { dir.appendingPathComponent(name + "." + $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
        guard let url, let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        frames = (0..<CGImageSourceGetCount(src)).compactMap { CGImageSourceCreateImageAtIndex(src, $0, nil) }
        if let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let g = p[kCGImagePropertyGIFDictionary] as? [CFString: Any], let d = g[kCGImagePropertyGIFDelayTime] as? Double, d > 0 { delay = d }
    }
    var aspect: CGFloat { frames.first.map { CGFloat($0.width) / CGFloat($0.height) } ?? 1 }
    func frame(at t: Double) -> CGImage? { frames.isEmpty ? nil : frames[Int(t / delay) % frames.count] }
}

struct Particle { var p: CGPoint, v: CGVector, life: CGFloat, r: CGFloat, c: NSColor }

final class BattleView: NSView {
    struct Mon {
        let name: String, sprite: Sprite, h: CGFloat, team: Int, types: Set<String>, moves: [String], bulk: CGFloat
        var hp: CGFloat = 1, rect = NSRect.zero, mouth = CGPoint.zero, faintT = -1
        var out: Bool { hp <= 0 }
    }
    // Double battle: Charizard + Pikachu (left, back sprites) vs Kyogre (right, front sprite)
    var mons = [
        Mon(name: "Charizard", sprite: Sprite("ani-back_charizard"), h: 30, team: 0, types: ["Fire", "Flying"], moves: ["Flamethrower", "Solar Beam", "Solar Beam"], bulk: 1),
        Mon(name: "Pikachu", sprite: Sprite("ani-back_pikachu"), h: 20, team: 0, types: ["Electric"], moves: ["Thunderbolt"], bulk: 0.85),
        Mon(name: "Kyogre", sprite: Sprite("ani_kyogre"), h: 22, team: 1, types: ["Water"], moves: ["Hydro Pump", "Thunder", "Water Spout"], bulk: 1.9),
    ]
    let ash = Sprite("trainer_ash") // Ash commands the left side
    var ashRect = NSRect(x: 0, y: 0, width: 30, height: 30)
    let order = [1, 0, 2] // Pikachu is fastest, then Charizard, then Kyogre
    var clock = 0.0, f = 0, oi = 0, att = 0, targets: [Int] = [], move = "", stage = 0 // 0 pause, 1 charge, 2 attack, 3 over
    var shake = 0, flash = 0, text = "", over = false
    var parts: [Particle] = []

    override func layout() {
        super.layout()
        func w(_ i: Int) -> CGFloat { mons[i].h * mons[i].sprite.aspect }
        mons[0].rect = NSRect(x: 30, y: 0, width: w(0), height: mons[0].h)
        mons[1].rect = NSRect(x: 66, y: 0, width: w(1), height: mons[1].h)
        mons[2].rect = NSRect(x: bounds.width - w(2) - 6, y: 3, width: w(2), height: mons[2].h)
        mons[0].mouth = CGPoint(x: mons[0].rect.maxX - w(0) * 0.15, y: 22) // back sprites face up-right
        mons[1].mouth = CGPoint(x: mons[1].rect.maxX - 3, y: 13)
        mons[2].mouth = CGPoint(x: mons[2].rect.minX + w(2) * 0.2, y: 12)
    }

    static let moveType = ["Flamethrower": "Fire", "Solar Beam": "Grass", "Thunderbolt": "Electric", "Hydro Pump": "Water", "Thunder": "Electric", "Water Spout": "Water"]
    static let power: [String: CGFloat] = ["Flamethrower": 0.17, "Solar Beam": 0.2, "Thunderbolt": 0.17, "Hydro Pump": 0.2, "Thunder": 0.2, "Water Spout": 0.15]
    func eff(_ m: String, _ t: Int) -> CGFloat { // the real type chart, for these types only
        let chart: [String: [String: CGFloat]] = ["Fire": ["Water": 0.5, "Fire": 0.5], "Grass": ["Water": 2, "Fire": 0.5, "Flying": 0.5],
            "Electric": ["Water": 2, "Flying": 2, "Electric": 0.5], "Water": ["Fire": 2, "Water": 0.5]]
        return mons[t].types.reduce(1) { $0 * (chart[Self.moveType[m]!]?[$1] ?? 1) }
    }

    func tick() {
        clock += 1 / 30; f += 1
        if shake > 0 { shake -= 1 }; if flash > 0 { flash -= 1 }
        for i in mons.indices where mons[i].faintT >= 0 { mons[i].faintT += 1 }
        parts = parts.compactMap { var q = $0; q.p.x += q.v.dx; q.p.y += q.v.dy; q.life -= 1; return q.life > 0 ? q : nil }
        switch stage {
        case 0 where f > 40:
            if over { for i in mons.indices { mons[i].hp = 1; mons[i].faintT = -1 }; over = false; oi = 0 }
            while mons[order[oi % 3]].out { oi += 1 }
            att = order[oi % 3]; oi += 1
            let foes = mons.indices.filter { mons[$0].team != mons[att].team && !mons[$0].out }
            move = mons[att].moves.randomElement()!
            targets = move == "Water Spout" ? foes : [foes.randomElement()!]
            text = "\(mons[att].name) used \(move)!"
            stage = move == "Solar Beam" ? 1 : 2; f = 0
            if mons[att].team == 0 { text = "Ash: \"\(mons[att].name), \(move)!\""; stage = 4 } // trainer calls the move first
        case 4 where f > 28:
            text = "\(mons[att].name) used \(move)!"; stage = move == "Solar Beam" ? 1 : 2; f = 0
        case 1: // Solar Beam charge: gather light
            let A = mons[att]
            for _ in 0..<2 {
                let ang = CGFloat.random(in: 0..<(2 * .pi))
                parts.append(Particle(p: CGPoint(x: A.mouth.x + cos(ang) * 14, y: A.mouth.y + sin(ang) * 14), v: CGVector(dx: -cos(ang) * 1.2, dy: -sin(ang) * 1.2), life: 11, r: 2, c: NSColor(red: 0.85, green: 1, blue: 0.6, alpha: 1)))
            }
            if f > 35 { stage = 2; f = 0 }
        case 2:
            let A = mons[att], stream = ["Flamethrower", "Hydro Pump", "Water Spout"].contains(move)
            let far = targets.map { abs(mons[$0].rect.midX - A.mouth.x) }.max()!, travel = stream ? Int(far / 9) : 10
            if f < 22 && stream {
                let cs: [NSColor] = move == "Flamethrower" ? [.systemRed, .systemOrange, .systemYellow] : [NSColor(red: 0.3, green: 0.55, blue: 1, alpha: 1), NSColor(red: 0.7, green: 0.9, blue: 1, alpha: 1), .white]
                for _ in 0..<3 {
                    let D = mons[targets.randomElement()!], dist = abs(D.rect.midX - A.mouth.x), n = max(1, dist / 9)
                    let dir: CGFloat = D.rect.midX > A.mouth.x ? 1 : -1
                    parts.append(Particle(p: A.mouth, v: CGVector(dx: dir * 9, dy: (D.rect.midY - A.mouth.y) / n + .random(in: -0.25...0.25)), life: n + 2, r: .random(in: 1.2...3), c: cs.randomElement()!))
                }
            }
            if f == travel {
                shake = 16; flash = 8
                for t in targets { mons[t].hp = max(0, mons[t].hp - Self.power[move]! * eff(move, t) * .random(in: 0.85...1.15) / mons[t].bulk) }
            }
            if f == travel + 8 {
                let e = targets.map { eff(move, $0) }.max()!
                text = e > 1 ? "It's super effective!" : e < 1 ? "It's not very effective..." : ""
            }
            if f == travel + 30 {
                let down = targets.filter { mons[$0].out }
                for t in down { mons[t].faintT = 0 }
                if !down.isEmpty { text = down.map { mons[$0].name }.joined(separator: " and ") + " fainted!" }
            }
            if f > travel + 50 {
                f = 0
                if Set(mons.filter { !$0.out }.map(\.team)).count < 2 { over = true; stage = 3; text = mons[2].out ? "Ash: \"We did it!\"" : "Kyogre won! Ash is out of usable Pokemon..." } else { stage = 0 }
            }
        case 3 where f > 80: stage = 0; f = 0; text = ""
        default: break
        }
        needsDisplay = true
    }

    override func draw(_ r: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if flash > 4 { NSColor.white.withAlphaComponent(0.12).setFill(); bounds.fill() }
        NSGraphicsContext.current?.imageInterpolation = .high
        let hit = stage == 2 ? Set(targets) : []
        let cheer = (stage == 4 && f < 14) || (stage == 3 && mons[2].out)
        if let img = ash.frame(at: 0) { ctx.draw(img, in: ashRect.offsetBy(dx: 0, dy: cheer ? abs(sin(CGFloat(f) * 0.5)) * 2.5 : 0)) }
        for (i, m) in mons.enumerated() {
            var rc = m.rect
            if m.out && m.faintT < 0 && !hit.contains(i) { continue } // already fainted
            if shake > 0 && hit.contains(i) { rc.origin.x += CGFloat((shake % 4) - 2) }
            if m.faintT >= 0 { let k = min(1, CGFloat(m.faintT) / 30); rc.origin.y -= k * rc.height; ctx.setAlpha(1 - k) }
            if let img = m.sprite.frame(at: clock), !(flash > 0 && hit.contains(i) && flash % 2 == 0) { ctx.draw(img, in: rc) }
            ctx.setAlpha(1)
            let bx: CGFloat = m.team == 0 ? 100 : m.rect.minX - 44, by: CGFloat = m.team == 0 ? (i == 0 ? 25 : 20) : 25
            NSColor(white: 0.25, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: 40, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
            (m.hp > 0.5 ? NSColor.systemGreen : m.hp > 0.2 ? .systemYellow : .systemRed).setFill()
            NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: 40 * m.hp, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
        }
        for q in parts { q.c.withAlphaComponent(0.85).setFill(); NSBezierPath(ovalIn: NSRect(x: q.p.x - q.r, y: q.p.y - q.r, width: q.r * 2, height: q.r * 2)).fill() }
        if stage == 2 && f < 22, let t = targets.first {
            let A = mons[att], D = mons[t]
            func bolt(from a: CGPoint, to b: CGPoint) {
                let p = NSBezierPath(); p.move(to: a); let n = 8
                for k in 1...n { let u = CGFloat(k) / CGFloat(n); p.line(to: CGPoint(x: a.x + (b.x - a.x) * u + (k < n ? .random(in: -4...4) : 0), y: a.y + (b.y - a.y) * u + (k < n ? .random(in: -4...4) : 0))) }
                NSColor(red: 0.55, green: 0.8, blue: 1, alpha: 0.9).setStroke(); p.lineWidth = 3.5; p.stroke()
                NSColor(red: 1, green: 0.95, blue: 0.4, alpha: 1).setStroke(); p.lineWidth = 1.5; p.stroke()
            }
            switch move {
            case "Solar Beam":
                let p = NSBezierPath(); p.move(to: A.mouth); p.line(to: CGPoint(x: D.rect.midX, y: D.rect.midY)); p.lineCapStyle = .round
                NSColor(red: 0.6, green: 1, blue: 0.4, alpha: 0.6).setStroke(); p.lineWidth = 7 + sin(CGFloat(f)) * 2; p.stroke()
                NSColor.white.setStroke(); p.lineWidth = 2.5; p.stroke()
            case "Thunder" where f > 8: bolt(from: CGPoint(x: D.rect.midX, y: 30), to: CGPoint(x: D.rect.midX, y: D.rect.midY))
            case "Thunderbolt" where f > 4: bolt(from: A.mouth, to: CGPoint(x: D.rect.midX, y: D.rect.midY))
            default: break
            }
        }
        if !text.isEmpty {
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor(white: 0.9, alpha: 1)]
            let s = text as NSString, w = s.size(withAttributes: a).width
            s.draw(at: CGPoint(x: bounds.midX - w / 2, y: 19), withAttributes: a)
        }
    }
}
