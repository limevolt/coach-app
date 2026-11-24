// ExerciseAnimation.swift — moteur d'animation des exercices (iPhone + montre, hors connexion)
// Personnage illustré vu de profil, squelette à 2 segments par membre (cinématique inverse),
// poses clés interpolées en douceur. Repère de dessin : 400 × 440, sol à y = 402.
// ⚠️ Ce fichier doit appartenir AUX DEUX cibles.

import SwiftUI

// MARK: - Géométrie

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    var length: CGFloat { (x * x + y * y).squareRoot() }

    func lerp(_ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: x + (b.x - x) * t, y: y + (b.y - y) * t)
    }
}

enum BodyGeo {
    static let shin: CGFloat = 92
    static let thigh: CGFloat = 98
    static let torso: CGFloat = 108
    static let neck: CGFloat = 12
    static let head: CGFloat = 25
    static let upper: CGFloat = 60
    static let fore: CGFloat = 54
    static let ground: CGFloat = 402
    static let flat: CGFloat = ground - 20          // cheville, pied à plat
    static let far = CGPoint(x: -8, y: 0)          // décalage des membres arrière

    static func rad(_ d: Double) -> CGFloat { CGFloat(d * .pi / 180) }

    /// Direction d'un angle mesuré depuis la verticale (haut), + = vers l'avant (droite).
    static func dir(_ a: Double) -> CGPoint { CGPoint(x: sin(rad(a)), y: -cos(rad(a))) }

    static func angle(of v: CGPoint) -> Double { Double(atan2(v.x, -v.y)) * 180 / .pi }

    static func shoulder(hip: CGPoint, torso: Double) -> CGPoint { hip + dir(torso) * self.torso }

    /// Position de la cheville quand la pointe du pied touche le sol en `toeX`, pied tourné de `a`°.
    static func ankleForToe(_ toeX: CGFloat, _ a: Double) -> CGPoint {
        let r = rad(a), lx: CGFloat = 50, ly: CGFloat = 20
        return CGPoint(x: toeX - (lx * cos(r) - ly * sin(r)), y: ground - (lx * sin(r) + ly * cos(r)))
    }

    /// Cinématique inverse à 2 segments. `s` = sens de pliage (-1 genoux vers l'avant, +1 coudes vers l'arrière).
    static func ik(_ a: CGPoint, _ t: CGPoint, _ l1: CGFloat, _ l2: CGFloat, _ s: CGFloat) -> (joint: CGPoint, end: CGPoint) {
        let dx = t.x - a.x, dy = t.y - a.y
        let d = min(max((dx * dx + dy * dy).squareRoot(), abs(l1 - l2) + 0.5), l1 + l2 - 0.5)
        let base = atan2(dy, dx)
        let cosA = min(max((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1), 1)
        let ang = base + s * acos(cosA)
        let j = CGPoint(x: a.x + cos(ang) * l1, y: a.y + sin(ang) * l1)
        let e = t - j
        let el = max(e.length, 0.0001)
        return (j, j + e * (l2 / el))
    }
}

// MARK: - Pose

struct BodyPose {
    var hip: CGPoint
    var torso: Double
    var head: Double = 0
    var footN: CGPoint
    var footF: CGPoint
    var footAngN: Double = 0
    var footAngF: Double = 0
    var handN: CGPoint
    var handF: CGPoint
    var effort: Double = 0.3

    static func lerp(_ a: BodyPose, _ b: BodyPose, _ t: Double) -> BodyPose {
        let k = CGFloat(t)
        func l(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return BodyPose(
            hip: a.hip.lerp(b.hip, k), torso: l(a.torso, b.torso), head: l(a.head, b.head),
            footN: a.footN.lerp(b.footN, k), footF: a.footF.lerp(b.footF, k),
            footAngN: l(a.footAngN, b.footAngN), footAngF: l(a.footAngF, b.footAngF),
            handN: a.handN.lerp(b.handN, k), handF: a.handF.lerp(b.handF, k),
            effort: l(a.effort, b.effort)
        )
    }
}

struct Skeleton {
    let pose: BodyPose
    let hip, shoulder, neckTop, head: CGPoint
    let headAngle: Double
    let kneeN, ankleN, kneeF, ankleF, hipF: CGPoint
    let elbowN, wristN, elbowF, wristF, shoulderF: CGPoint

    init(_ p: BodyPose) {
        let sh = BodyGeo.shoulder(hip: p.hip, torso: p.torso)
        let ha = p.torso + p.head
        let nt = sh + BodyGeo.dir(ha) * BodyGeo.neck
        let hF = p.hip + BodyGeo.far
        let shF = sh + BodyGeo.far
        pose = p
        hip = p.hip
        shoulder = sh
        headAngle = ha
        neckTop = nt
        head = nt + BodyGeo.dir(ha) * (BodyGeo.head - 4)
        hipF = hF
        shoulderF = shF
        let legN = BodyGeo.ik(p.hip, p.footN, BodyGeo.thigh, BodyGeo.shin, -1)
        let legF = BodyGeo.ik(hF, p.footF, BodyGeo.thigh, BodyGeo.shin, -1)
        let armN = BodyGeo.ik(sh, p.handN, BodyGeo.upper, BodyGeo.fore, 1)
        let armF = BodyGeo.ik(shF, p.handF, BodyGeo.upper, BodyGeo.fore, 1)
        kneeN = legN.joint; ankleN = legN.end
        kneeF = legF.joint; ankleF = legF.end
        elbowN = armN.joint; wristN = armN.end
        elbowF = armF.joint; wristF = armF.end
    }
}

// MARK: - Animation

enum Muscle: String, CaseIterable {
    case quads, hamstrings, glutes, calves, chest, core, back, shoulders, triceps, biceps

    var label: String {
        switch self {
        case .quads: return "Quadriceps"
        case .hamstrings: return "Ischios"
        case .glutes: return "Fessiers"
        case .calves: return "Mollets"
        case .chest: return "Pectoraux"
        case .core: return "Abdos / gainage"
        case .back: return "Dos"
        case .shoulders: return "Épaules"
        case .triceps: return "Triceps"
        case .biceps: return "Biceps"
        }
    }
}

struct AnimPhase {
    var duration: Double
    var label: String
    var cue: String
    var pose: BodyPose
    var step: Int? = nil       // étape des consignes par défaut mise en avant
}

struct ExerciseAnimation: Identifiable {
    let id: String
    let name: String
    var muscles: [Muscle]
    var dumbbells = false
    var wide = false
    var scale: CGFloat = 1
    var raise: CGFloat = 0          // remonte les exercices au sol pour les centrer
    var level = "Débutant"
    var phases: [AnimPhase]
    var steps: [String]
    var mistakes: [String]

    var cycle: Double { phases.reduce(0) { $0 + $1.duration } }

    struct Sample {
        var pose: BodyPose
        var index: Int
        var phase: AnimPhase
        var progress: Double
    }

    func sample(at t: Double) -> Sample {
        let total = max(cycle, 0.01)
        var x = t.truncatingRemainder(dividingBy: total)
        if x < 0 { x += total }
        let progress = x / total
        var i = 0
        while i < phases.count - 1 && x > phases[i].duration {
            x -= phases[i].duration
            i += 1
        }
        let prev = phases[(i - 1 + phases.count) % phases.count].pose
        let cur = phases[i]
        let f = min(max(x / cur.duration, 0), 1)
        let eased = (1 - cos(Double.pi * f)) / 2
        return Sample(pose: BodyPose.lerp(prev, cur.pose, eased), index: i, phase: cur, progress: progress)
    }
}

// MARK: - Dessin

enum FigurePalette {
    static let skin = Color(hex: 0xE7A77C)
    static let skinDark = Color(hex: 0xC98A62)
    static let shirt = Color(hex: 0x2DD4BF)
    static let shirtDark = Color(hex: 0x1FA395)
    static let shorts = Color(hex: 0x243046)
    static let shortsDark = Color(hex: 0x1A2334)
    static let hair = Color(hex: 0x2A1D16)
    static let shoe = Color(hex: 0xF4F6F8)
    static let shoeDark = Color(hex: 0xC9D0D8)
    static let shoeShade = Color(hex: 0x9AA4B0)
    static let sole = Color(hex: 0xC6F432)
    static let sock = Color.white
    static let sockDark = Color(hex: 0xD9DEE5)
    static let warm = Color(hex: 0xFF7A45)
    static let plate = Color(hex: 0x3A4456)
    static let plateDark = Color(hex: 0x2A3242)
}

enum FigureRenderer {
    typealias Pal = FigurePalette

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, animation: ExerciseAnimation,
                     pose: BodyPose, muscles: Bool, shadow: Bool = true) {
        let s = min(size.width / 400, size.height / 440)
        ctx.translateBy(x: (size.width - 400 * s) / 2, y: (size.height - 440 * s) / 2)
        ctx.scaleBy(x: s, y: s)
        if animation.scale != 1 || animation.raise != 0 {
            ctx.translateBy(x: 0, y: -animation.raise)
            ctx.translateBy(x: 200, y: BodyGeo.ground)
            ctx.scaleBy(x: animation.scale, y: animation.scale)
            ctx.translateBy(x: -200, y: -BodyGeo.ground)
        }
        let k = Skeleton(pose)

        if shadow {
            let cx = (k.ankleN.x + k.hip.x + k.wristN.x) / 3
            let rx: CGFloat = animation.wide ? 150 : 85
            ctx.fill(Path(ellipseIn: CGRect(x: cx - rx, y: BodyGeo.ground - 7, width: rx * 2, height: 18)),
                     with: .color(.black.opacity(0.35)))
        }

        // Bras arrière
        capsule(&ctx, k.shoulderF, k.elbowF, 10, 8.5, Pal.skinDark)
        capsule(&ctx, k.elbowF, k.wristF, 8.5, 6.5, Pal.skinDark)
        circle(&ctx, k.wristF, 8, Pal.skinDark)
        if animation.dumbbells { dumbbell(&ctx, k.wristF, dark: true) }

        // Jambe arrière
        shoe(&ctx, k.ankleF, pose.footAngF, Pal.shoeDark, Pal.shoeShade)
        capsule(&ctx, k.kneeF, k.ankleF, 13.5, 9, Pal.skinDark)
        capsule(&ctx, k.ankleF, k.ankleF.lerp(k.kneeF, 0.18), 9.5, 10, Pal.sockDark)
        capsule(&ctx, k.hipF, k.kneeF, 19, 14, Pal.skinDark)
        capsule(&ctx, k.hipF, k.hipF.lerp(k.kneeF, 0.55), 22, 19, Pal.shortsDark)

        // Jambe avant
        capsule(&ctx, k.kneeN, k.ankleN, 14, 9.5, Pal.skin)
        capsule(&ctx, k.ankleN, k.ankleN.lerp(k.kneeN, 0.18), 10, 10.5, Pal.sock)
        shoe(&ctx, k.ankleN, pose.footAngN, Pal.shoe, Pal.shoeDark)
        capsule(&ctx, k.hip, k.kneeN, 20, 14.5, Pal.skin)

        // Torse + short
        capsule(&ctx, k.hip, k.shoulder, 25, 23, Pal.shirt)
        capsule(&ctx, k.hip, k.hip.lerp(k.shoulder, 0.12), 26, 25.5, Pal.shorts)
        capsule(&ctx, k.hip, k.hip.lerp(k.kneeN, 0.55), 24, 20.5, Pal.shorts)

        // Cou + tête
        capsule(&ctx, k.shoulder, k.neckTop, 9, 9, Pal.skinDark)
        head(&ctx, k.head, k.headAngle)

        // Bras avant
        capsule(&ctx, k.shoulder, k.elbowN, 11, 9, Pal.skin)
        capsule(&ctx, k.elbowN, k.wristN, 9, 7, Pal.skin)
        circle(&ctx, k.wristN, 8.5, Pal.skin)
        if animation.dumbbells { dumbbell(&ctx, k.wristN, dark: false) }
        capsule(&ctx, k.shoulder, k.shoulder.lerp(k.elbowN, 0.42), 15, 12.5, Pal.shirtDark)

        if muscles {
            drawMuscles(&ctx, k, animation.muscles, 0.2 + 0.75 * pose.effort)
        }
    }

    // MARK: Primitives

    private static func circle(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    /// Membre effilé : trapèze + deux disques (remplis séparément pour éviter les trous).
    private static func capsule(_ ctx: inout GraphicsContext, _ p1: CGPoint, _ p2: CGPoint,
                                _ r1: CGFloat, _ r2: CGFloat, _ color: Color) {
        let d = p2 - p1
        let l = max(d.length, 0.0001)
        let n = CGPoint(x: -d.y / l, y: d.x / l)
        var body = Path()
        body.move(to: p1 + n * r1)
        body.addLine(to: p2 + n * r2)
        body.addLine(to: p2 - n * r2)
        body.addLine(to: p1 - n * r1)
        body.closeSubpath()
        ctx.fill(body, with: .color(color))
        circle(&ctx, p1, r1, color)
        circle(&ctx, p2, r2, color)
    }

    private static func shoe(_ ctx: inout GraphicsContext, _ a: CGPoint, _ angle: Double, _ color: Color, _ dark: Color) {
        let t = CGAffineTransform(translationX: a.x, y: a.y).rotated(by: BodyGeo.rad(angle))
        var p = Path()
        p.move(to: CGPoint(x: -20, y: 16))
        p.addLine(to: CGPoint(x: 44, y: 16))
        p.addQuadCurve(to: CGPoint(x: 50, y: 8), control: CGPoint(x: 52, y: 16))
        p.addQuadCurve(to: CGPoint(x: 26, y: -3), control: CGPoint(x: 46, y: 1))
        p.addLine(to: CGPoint(x: 8, y: -10))
        p.addQuadCurve(to: CGPoint(x: -19, y: -4), control: CGPoint(x: -10, y: -13))
        p.addQuadCurve(to: CGPoint(x: -20, y: 16), control: CGPoint(x: -25, y: 6))
        p.closeSubpath()
        ctx.fill(p.applying(t), with: .color(color))

        var lace = Path()
        lace.move(to: CGPoint(x: 8, y: -10))
        lace.addLine(to: CGPoint(x: 26, y: -3))
        lace.addLine(to: CGPoint(x: 22, y: 2))
        lace.addLine(to: CGPoint(x: 5, y: -5))
        lace.closeSubpath()
        ctx.fill(lace.applying(t), with: .color(dark.opacity(0.7)))

        let sole = Path(roundedRect: CGRect(x: -22, y: 14, width: 74, height: 6), cornerRadius: 3)
        ctx.fill(sole.applying(t), with: .color(FigurePalette.sole))
    }

    private static func head(_ ctx: inout GraphicsContext, _ h: CGPoint, _ angle: Double) {
        circle(&ctx, h, BodyGeo.head, Pal.skin)
        let t = CGAffineTransform(translationX: h.x, y: h.y).rotated(by: BodyGeo.rad(angle))

        var hair = Path()
        // Calotte : arc du cercle de la tête, de l'arrière (≈171°) au front (≈323°) en passant par le haut
        let a0 = atan2(4.0, -25.0), a1 = atan2(-15.0, 20.0) + 2 * Double.pi
        hair.move(to: CGPoint(x: -25, y: 4))
        for i in 1...16 {
            let a = a0 + (a1 - a0) * Double(i) / 16
            hair.addLine(to: CGPoint(x: 25 * cos(a), y: 25 * sin(a)))
        }
        hair.addQuadCurve(to: CGPoint(x: -4, y: -4), control: CGPoint(x: 6, y: -9))
        hair.addQuadCurve(to: CGPoint(x: -18, y: 16), control: CGPoint(x: -10, y: 6))
        hair.addQuadCurve(to: CGPoint(x: -25, y: 4), control: CGPoint(x: -25, y: 12))
        hair.closeSubpath()
        ctx.fill(hair.applying(t), with: .color(Pal.hair))

        ctx.fill(Path(ellipseIn: CGRect(x: -9, y: -4, width: 10, height: 14)).applying(t), with: .color(Pal.skinDark))
        ctx.fill(Path(ellipseIn: CGRect(x: 11.4, y: -3.6, width: 5.2, height: 5.2)).applying(t),
                 with: .color(Color(hex: 0x1B130F)))
        var mouth = Path()
        mouth.move(to: CGPoint(x: 12, y: 11))
        mouth.addQuadCurve(to: CGPoint(x: 21, y: 10), control: CGPoint(x: 17, y: 13))
        ctx.stroke(mouth.applying(t), with: .color(Color(hex: 0x9C5D3D)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private static func dumbbell(_ ctx: inout GraphicsContext, _ w: CGPoint, dark: Bool) {
        let r: CGFloat = 15
        let rect = CGRect(x: w.x - r, y: w.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(dark ? Pal.plateDark : Pal.plate))
        ctx.stroke(Path(ellipseIn: rect), with: .color(Pal.sole.opacity(dark ? 0.4 : 0.9)), lineWidth: 2.5)
    }

    // MARK: Muscles

    private static func glow(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ a: Double) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect),
                 with: .radialGradient(Gradient(colors: [Pal.warm.opacity(0.95 * a), Pal.warm.opacity(0)]),
                                       center: c, startRadius: 0, endRadius: r))
    }

    /// Normale d'un segment, orientée vers `toward` (ou `fallback` si le membre est tendu).
    private static func sideNormal(_ p1: CGPoint, _ p2: CGPoint, toward: CGPoint, fallback: CGPoint) -> CGPoint {
        let d = p2 - p1
        let l = max(d.length, 0.0001)
        let n = CGPoint(x: -d.y / l, y: d.x / l)
        var s = n.x * toward.x + n.y * toward.y
        if abs(s) < 0.001 { s = n.x * fallback.x + n.y * fallback.y }
        return s >= 0 ? n : n * -1
    }

    private static func drawMuscles(_ ctx: inout GraphicsContext, _ k: Skeleton, _ list: [Muscle], _ a: Double) {
        let front = BodyGeo.dir(k.pose.torso + 90)
        let back = front * -1
        let thighBack = sideNormal(k.hip, k.kneeN, toward: k.ankleN - k.kneeN, fallback: back)
        let shinBack = sideNormal(k.kneeN, k.ankleN, toward: k.hip - k.kneeN, fallback: back)
        let armFront = sideNormal(k.shoulder, k.elbowN, toward: k.wristN - k.elbowN, fallback: front)
        for m in list {
            switch m {
            case .quads:
                glow(&ctx, k.hip.lerp(k.kneeN, 0.35) + thighBack * -9, 17, a)
                glow(&ctx, k.hip.lerp(k.kneeN, 0.72) + thighBack * -8, 15, a)
            case .hamstrings:
                glow(&ctx, k.hip.lerp(k.kneeN, 0.45) + thighBack * 9, 17, a)
                glow(&ctx, k.hip.lerp(k.kneeN, 0.75) + thighBack * 8, 14, a)
            case .glutes:
                glow(&ctx, k.hip + back * 15, 20, a)
            case .calves:
                glow(&ctx, k.kneeN.lerp(k.ankleN, 0.35) + shinBack * 7, 14, a)
            case .chest:
                glow(&ctx, k.hip.lerp(k.shoulder, 0.8) + front * 13, 19, a)
            case .core:
                glow(&ctx, k.hip.lerp(k.shoulder, 0.38) + front * 12, 20, a)
            case .back:
                glow(&ctx, k.hip.lerp(k.shoulder, 0.72) + back * 13, 21, a)
            case .shoulders:
                glow(&ctx, k.shoulder, 17, a)
            case .triceps:
                glow(&ctx, k.shoulder.lerp(k.elbowN, 0.5) + armFront * -7, 13, a)
            case .biceps:
                glow(&ctx, k.shoulder.lerp(k.elbowN, 0.5) + armFront * 7, 13, a)
            }
        }
    }
}

// MARK: - Vues

/// Dessine une pose précise (pour un temps donné).
struct ExerciseFigure: View {
    let animation: ExerciseAnimation
    let time: Double
    var muscles = false
    var shadow = true

    var body: some View {
        Canvas { ctx, size in
            let pose = animation.sample(at: time).pose
            FigureRenderer.draw(&ctx, size: size, animation: animation, pose: pose, muscles: muscles, shadow: shadow)
        }
    }
}

/// Animation en boucle autonome (vignettes, montre).
struct AnimatedExerciseFigure: View {
    let animation: ExerciseAnimation
    var muscles = false
    var playing = true
    var fps: Double = 30
    var shadow = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / fps, paused: !playing)) { context in
            ExerciseFigure(animation: animation,
                           time: context.date.timeIntervalSinceReferenceDate,
                           muscles: muscles, shadow: shadow)
        }
    }
}
