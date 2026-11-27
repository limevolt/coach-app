// ExerciseLibrary.swift — les exercices animés, leurs consignes et erreurs fréquentes
// ⚠️ Ce fichier doit appartenir AUX DEUX cibles.
//
// Pour associer une animation à un exercice du plan : champ "animation" (ex. "squat"),
// sinon l'app la devine d'après le nom (« Squat sauté », « Pompes », « Fentes »…).

import SwiftUI

enum ExerciseLibrary {

    // MARK: Recherche

    static func animation(id: String) -> ExerciseAnimation? {
        all.first { $0.id == id }
    }

    static func animation(for exercise: Exercise) -> ExerciseAnimation? {
        if exercise.homeVariant == true {
            // Variante sans matériel : uniquement l'animation prévue pour elle, jamais devinée d'après le nom
            // (« Soulevé de terre roumain sur une jambe » trouvait l'animation aux haltères). Aucune plutôt qu'une fausse.
            guard let id = exercise.animation, let a = animation(id: id), !a.dumbbells else { return nil }
            return a
        }
        if let id = exercise.animation, let a = animation(id: id) { return a }
        return animation(forName: exercise.name)
    }

    static func animation(forName name: String) -> ExerciseAnimation? {
        let n = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
        let rules: [(keys: [String], id: String)] = [
            (["squat saut", "jump squat", "squat jump"], "squatJump"),
            (["squat"], "squat"),
            (["pompe", "push"], "pushup"),
            (["gainage lat", "planche lat", "side plank", "lateral"], "sidePlank"),
            (["gainage", "planche", "plank"], "plank"),
            (["fente", "lunge"], "lunge"),
            (["jumping", "jack"], "jumpingJack"),
            (["mountain", "grimpeur"], "mountainClimber"),
            (["roumain", "deadlift", "rdl", "souleve de terre"], "rdl"),
            (["rowing", "row", "tirage"], "row"),
            (["mollet", "calf"], "calfRaise"),
            (["pont", "bridge", "hip thrust"], "gluteBridge")
        ]
        for rule in rules where rule.keys.contains(where: { n.contains($0) }) {
            guard let a = animation(id: rule.id) else { return nil }
            // Une autre version que celle dessinée : aucune animation plutôt qu'une fausse
            // (« Soulevé de terre roumain sur une jambe » n'est pas la version aux haltères sur deux jambes).
            if n.contains("une jambe") && !a.singleLeg { return nil }
            if a.dumbbells && bodyweightMarkers.contains(where: { n.contains($0) }) { return nil }
            return a
        }
        return nil
    }

    /// Mots qui désignent une version sans charge d'un exercice dessiné aux haltères.
    private static let bodyweightMarkers = ["unilateral", "inverse", "sac a dos", "poids du corps", "sans charge",
                                            "sans materiel", "table"]

    // MARK: Constructeurs de poses

    private typealias G = BodyGeo

    private enum Hands { case hang, forward, hips, overhead }

    private static func stand(hip: CGPoint, torso: Double, head: Double = 0, hands: Hands = .hang,
                              effort: Double = 0.2, ankleX: CGFloat = 192, lift: CGFloat = 0,
                              footAng: Double = 0, handsAt: ((CGPoint, CGPoint) -> CGPoint)? = nil) -> BodyPose {
        let sh = G.shoulder(hip: hip, torso: torso)
        let hN: CGPoint
        if let handsAt {
            hN = handsAt(sh, hip)
        } else {
            switch hands {
            case .hang: hN = CGPoint(x: sh.x + 6, y: sh.y + 110)
            case .forward: hN = CGPoint(x: sh.x + 108, y: sh.y + 4)
            case .hips: hN = CGPoint(x: hip.x + 14, y: hip.y - 14)
            case .overhead: hN = CGPoint(x: sh.x + 14, y: sh.y - 110)
            }
        }
        let fN = CGPoint(x: ankleX, y: G.flat - lift)
        return BodyPose(hip: hip, torso: torso, head: head,
                        footN: fN, footF: fN + G.far, footAngN: footAng, footAngF: footAng,
                        handN: hN, handF: hN + G.far, effort: effort)
    }

    private static func plank(toeX: CGFloat, footAng: Double = 62, shoulderY: CGFloat, forearms: Bool,
                              effort: Double = 0.8, head: Double = -4, hipDrop: CGFloat = 0,
                              freeArm: ((CGPoint) -> CGPoint)? = nil) -> BodyPose {
        let ankle = G.ankleForToe(toeX, footAng)
        let legs = G.thigh + G.shin - 1
        let bodyLen = legs + G.torso
        let dy = shoulderY - ankle.y
        let dx = max(1, bodyLen * bodyLen - dy * dy).squareRoot()
        let sh0 = CGPoint(x: ankle.x + dx, y: shoulderY)
        let dir = (sh0 - ankle) * (1 / bodyLen)
        let hip = ankle + dir * legs + CGPoint(x: 0, y: hipDrop)
        let torso = G.angle(of: sh0 - hip)
        let sh = G.shoulder(hip: hip, torso: torso)
        var hN = forearms ? CGPoint(x: sh.x + 54, y: G.ground - 9) : CGPoint(x: sh.x + 2, y: G.ground - 9)
        let hF = hN + G.far
        if let freeArm { hN = freeArm(sh) }
        return BodyPose(hip: hip, torso: torso, head: head,
                        footN: ankle, footF: ankle + G.far, footAngN: footAng, footAngF: footAng,
                        handN: hN, handF: hF, effort: effort)
    }

    // MARK: Bibliothèque

    static let all: [ExerciseAnimation] = [
        squat, squatJump, pushup, plankAnim, sidePlank, lunge,
        jumpingJack, mountainClimber, rdl, row, calfRaise, gluteBridge
    ]

    /// Petit coureur de l'écran d'attente « Le coach prépare ton plan » : pas un exercice du plan (hors `all`).
    static let jog: ExerciseAnimation = {
        func runPose(hipY: CGFloat, footN: CGPoint, footF: CGPoint, handN: CGPoint, handF: CGPoint) -> BodyPose {
            let hip = CGPoint(x: 192, y: hipY)
            let sh = G.shoulder(hip: hip, torso: 8)
            return BodyPose(hip: hip, torso: 8, head: -4, footN: footN, footF: footF,
                            footAngN: 0, footAngF: 0, handN: sh + handN, handF: sh + handF, effort: 0.5)
        }
        // Pied avant posé / pied arrière levé, puis passage (genou haut), et l'inverse : bras opposés aux jambes.
        let contactN = runPose(hipY: 198, footN: CGPoint(x: 246, y: 378), footF: CGPoint(x: 134, y: 300),
                              handN: CGPoint(x: -36, y: 62), handF: CGPoint(x: 40, y: 46))
        let passN = runPose(hipY: 190, footN: CGPoint(x: 198, y: 382), footF: CGPoint(x: 214, y: 296),
                           handN: CGPoint(x: 6, y: 72), handF: CGPoint(x: 2, y: 72))
        let contactF = runPose(hipY: 198, footN: CGPoint(x: 128, y: 300), footF: CGPoint(x: 238, y: 378),
                              handN: CGPoint(x: 40, y: 46), handF: CGPoint(x: -36, y: 62))
        let passF = runPose(hipY: 190, footN: CGPoint(x: 222, y: 296), footF: CGPoint(x: 190, y: 382),
                           handN: CGPoint(x: 2, y: 72), handF: CGPoint(x: 6, y: 72))
        return ExerciseAnimation(
            id: "jog", name: "Course", muscles: [],
            phases: [
                AnimPhase(duration: 0.17, label: "", cue: "", pose: contactN),
                AnimPhase(duration: 0.17, label: "", cue: "", pose: passN),
                AnimPhase(duration: 0.17, label: "", cue: "", pose: contactF),
                AnimPhase(duration: 0.17, label: "", cue: "", pose: passF)
            ],
            steps: [], mistakes: [])
    }()

    static let squat: ExerciseAnimation = {
        let top = stand(hip: CGPoint(x: 192, y: 194), torso: 3, effort: 0.1)
        let bottom = stand(hip: CGPoint(x: 142, y: 312), torso: 40, head: -25, hands: .forward, effort: 1)
        return ExerciseAnimation(
            id: "squat", name: "Squat", muscles: [.quads, .glutes],
            phases: [
                AnimPhase(duration: 1.5, label: "Descente", cue: "Inspire, fesses en arrière, bras devant", pose: bottom, step: 1),
                AnimPhase(duration: 0.5, label: "En bas", cue: "Cuisses parallèles, dos droit, talons au sol", pose: bottom, step: 2),
                AnimPhase(duration: 1.1, label: "Remontée", cue: "Expire, pousse fort dans les talons", pose: top, step: 3),
                AnimPhase(duration: 0.9, label: "En haut", cue: "Debout, serre les fessiers", pose: top, step: 0)
            ],
            steps: ["Pieds largeur d'épaules, pointes légèrement ouvertes.",
                    "Inspire et descends en poussant les fesses en arrière, bras devant.",
                    "Cuisses parallèles au sol, dos droit, talons au sol.",
                    "Expire et remonte en poussant dans les talons."],
            mistakes: ["Talons qui décollent : garde tout le pied au sol.",
                       "Genoux vers l'intérieur : dans l'axe des pointes de pieds.",
                       "Dos arrondi : poitrine ouverte, regard devant."])
    }()

    static let squatJump: ExerciseAnimation = {
        let top = stand(hip: CGPoint(x: 192, y: 194), torso: 3, effort: 0.2)
        let bottom = stand(hip: CGPoint(x: 146, y: 300), torso: 38, head: -24, hands: .forward, effort: 0.9)
        let air = stand(hip: CGPoint(x: 194, y: 170), torso: 2, hands: .overhead, effort: 1, lift: 26, footAng: 22)
        let land = stand(hip: CGPoint(x: 176, y: 236), torso: 20, head: -12, hands: .forward, effort: 0.7)
        return ExerciseAnimation(
            id: "squatJump", name: "Squat sauté", muscles: [.quads, .glutes, .calves], scale: 0.84,
            level: "Intermédiaire",
            phases: [
                AnimPhase(duration: 0.9, label: "Descente", cue: "Descends en squat, bras devant", pose: bottom, step: 0),
                AnimPhase(duration: 0.35, label: "Saut", cue: "Explose vers le haut, bras au ciel", pose: air, step: 1),
                AnimPhase(duration: 0.35, label: "Réception", cue: "Atterris souple sur l'avant du pied", pose: land, step: 2),
                AnimPhase(duration: 0.6, label: "Amorti", cue: "Genoux fléchis, enchaîne", pose: top, step: 3)
            ],
            steps: ["Descends en squat, bras tendus devant.",
                    "Pousse fort dans le sol et saute, bras vers le ciel.",
                    "Atterris en douceur sur l'avant du pied, genoux fléchis.",
                    "Enchaîne directement la descente suivante."],
            mistakes: ["Réception jambes tendues : amortis toujours.",
                       "Genoux qui rentrent à l'atterrissage.",
                       "Sauter sans contrôle : qualité avant vitesse."])
    }()

    static let pushup: ExerciseAnimation = {
        let top = plank(toeX: 30, shoulderY: 281, forearms: false, effort: 0.3, head: -6)
        var bottom = plank(toeX: 30, shoulderY: 338, forearms: false, effort: 1, head: -10)
        bottom.handN = top.handN
        bottom.handF = top.handF
        return ExerciseAnimation(
            id: "pushup", name: "Pompes", muscles: [.chest, .triceps, .core], wide: true, scale: 0.86, raise: 100,
            phases: [
                AnimPhase(duration: 1.3, label: "Descente", cue: "Inspire, coudes à 45°, corps gainé", pose: bottom, step: 1),
                AnimPhase(duration: 0.3, label: "En bas", cue: "Poitrine près du sol", pose: bottom, step: 2),
                AnimPhase(duration: 1.0, label: "Poussée", cue: "Expire, pousse le sol loin de toi", pose: top, step: 3),
                AnimPhase(duration: 0.7, label: "En haut", cue: "Bras tendus, dos plat", pose: top, step: 0)
            ],
            steps: ["Mains un peu plus larges que les épaules, corps aligné.",
                    "Inspire et descends, coudes à 45° du corps.",
                    "Poitrine près du sol, ventre et fessiers serrés.",
                    "Expire et pousse jusqu'aux bras tendus."],
            mistakes: ["Bassin qui s'affaisse : serre les abdos.",
                       "Fesses trop hautes : corps en planche.",
                       "Coudes à 90° du corps : rapproche-les à 45°."])
    }()

    static let plankAnim: ExerciseAnimation = {
        let a = plank(toeX: 40, shoulderY: 333, forearms: true, effort: 0.8)
        var b = plank(toeX: 40, shoulderY: 331, forearms: true, effort: 0.9, hipDrop: -2)
        b.handN = a.handN
        b.handF = a.handF
        return ExerciseAnimation(
            id: "plank", name: "Gainage planche", muscles: [.core, .shoulders], wide: true, scale: 0.86, raise: 110,
            phases: [
                AnimPhase(duration: 2.0, label: "Tiens", cue: "Coudes sous les épaules, ventre serré", pose: b, step: 1),
                AnimPhase(duration: 2.0, label: "Respire", cue: "Bassin aligné, respire calmement", pose: a, step: 2)
            ],
            steps: ["Avant-bras au sol, coudes sous les épaules.",
                    "Corps aligné de la tête aux talons, ventre et fessiers serrés.",
                    "Respire calmement sans bouger le bassin."],
            mistakes: ["Bassin trop bas : le dos se creuse.",
                       "Fesses trop hautes : ça devient trop facile.",
                       "Bloquer la respiration."])
    }()

    static let sidePlank: ExerciseAnimation = {
        let low = plank(toeX: 40, footAng: 30, shoulderY: 333, forearms: true, effort: 0.7, hipDrop: 14,
                        freeArm: { CGPoint(x: $0.x + 8, y: $0.y - 70) })
        var high = plank(toeX: 40, footAng: 30, shoulderY: 333, forearms: true, effort: 1, hipDrop: -6,
                         freeArm: { CGPoint(x: $0.x + 8, y: $0.y - 112) })
        high.handF = low.handF
        return ExerciseAnimation(
            id: "sidePlank", name: "Gainage latéral", muscles: [.core, .shoulders], wide: true, scale: 0.86, raise: 80,
            phases: [
                AnimPhase(duration: 1.4, label: "Monte", cue: "Monte le bassin, bras vers le ciel", pose: high, step: 1),
                AnimPhase(duration: 1.2, label: "Tiens", cue: "Corps en ligne droite", pose: high, step: 2),
                AnimPhase(duration: 1.2, label: "Contrôle", cue: "Redescends légèrement sans toucher", pose: low, step: 3)
            ],
            steps: ["Sur le côté, coude sous l'épaule, pieds empilés.",
                    "Monte le bassin, bras du dessus vers le ciel.",
                    "Corps aligné de la tête aux pieds.",
                    "Tiens, puis change de côté."],
            mistakes: ["Bassin qui tombe vers le sol.",
                       "Épaule qui s'écrase : pousse dans l'avant-bras.",
                       "Buste qui bascule en avant."])
    }()

    static let lunge: ExerciseAnimation = {
        let standing = stand(hip: CGPoint(x: 192, y: 194), torso: 2, hands: .hips, effort: 0.1)
        func lungePose(_ nearForward: Bool) -> BodyPose {
            let hip = CGPoint(x: 190, y: 288)
            let front = CGPoint(x: 258, y: G.flat), back = G.ankleForToe(116, 48)
            return BodyPose(hip: hip, torso: 3, head: 0,
                            footN: nearForward ? front : back,
                            footF: nearForward ? back + G.far : front + G.far,
                            footAngN: nearForward ? 0 : 48, footAngF: nearForward ? 48 : 0,
                            handN: CGPoint(x: hip.x + 14, y: hip.y - 14), handF: CGPoint(x: hip.x + 6, y: hip.y - 14),
                            effort: 1)
        }
        func stepPose(_ nearForward: Bool) -> BodyPose {
            var p = BodyPose.lerp(standing, lungePose(nearForward), 0.5)
            if nearForward { p.footN = p.footN + CGPoint(x: 0, y: -26) } else { p.footF = p.footF + CGPoint(x: 0, y: -26) }
            return p
        }
        return ExerciseAnimation(
            id: "lunge", name: "Fentes alternées", muscles: [.quads, .glutes],
            phases: [
                AnimPhase(duration: 0.45, label: "Pas en avant", cue: "Grand pas en avant", pose: stepPose(true), step: 0),
                AnimPhase(duration: 0.7, label: "Descente", cue: "Descends, genoux à 90°", pose: lungePose(true), step: 1),
                AnimPhase(duration: 0.3, label: "En bas", cue: "Genou avant au-dessus de la cheville", pose: lungePose(true), step: 2),
                AnimPhase(duration: 0.8, label: "Retour", cue: "Repousse avec la jambe avant", pose: standing, step: 3),
                AnimPhase(duration: 0.45, label: "Pas en avant", cue: "Change de jambe", pose: stepPose(false), step: 0),
                AnimPhase(duration: 0.7, label: "Descente", cue: "Buste droit, regard devant", pose: lungePose(false), step: 1),
                AnimPhase(duration: 0.3, label: "En bas", cue: "Genou arrière près du sol", pose: lungePose(false), step: 2),
                AnimPhase(duration: 0.8, label: "Retour", cue: "Reviens pieds joints", pose: standing, step: 3)
            ],
            steps: ["Debout, mains sur les hanches, fais un grand pas en avant.",
                    "Descends jusqu'à ce que les deux genoux soient à 90°.",
                    "Genou avant au-dessus de la cheville, buste droit.",
                    "Repousse avec la jambe avant et change de côté."],
            mistakes: ["Pas trop court : le genou dépasse loin devant le pied.",
                       "Buste penché en avant.",
                       "Genou avant qui rentre vers l'intérieur."])
    }()

    static let jumpingJack: ExerciseAnimation = {
        let standing = stand(hip: CGPoint(x: 192, y: 196), torso: 2, effort: 0.3)
        let air = stand(hip: CGPoint(x: 192, y: 176), torso: 1, hands: .overhead, effort: 0.9, lift: 18, footAng: 18)
        let land = stand(hip: CGPoint(x: 186, y: 206), torso: 6, hands: .overhead, effort: 0.7)
        let air2 = stand(hip: CGPoint(x: 192, y: 178), torso: 1, hands: .forward, effort: 0.8, lift: 16, footAng: 16)
        return ExerciseAnimation(
            id: "jumpingJack", name: "Jumping jacks", muscles: [.calves, .shoulders], scale: 0.84,
            phases: [
                AnimPhase(duration: 0.28, label: "Saut", cue: "Saute en écartant, bras qui montent", pose: air, step: 0),
                AnimPhase(duration: 0.25, label: "Bras en haut", cue: "Bras au-dessus de la tête", pose: land, step: 1),
                AnimPhase(duration: 0.28, label: "Saut", cue: "Saute en resserrant, bras qui descendent", pose: air2, step: 2),
                AnimPhase(duration: 0.25, label: "Retour", cue: "Pieds joints, léger sur les pointes", pose: standing, step: 2)
            ],
            steps: ["Saute en écartant les pieds et en levant les bras sur les côtés.",
                    "Mains qui se rejoignent au-dessus de la tête.",
                    "Saute pour revenir pieds joints, bras le long du corps."],
            mistakes: ["Atterrir sur les talons : reste sur l'avant du pied.",
                       "Bras à moitié levés.",
                       "Genoux verrouillés."])
    }()

    static let mountainClimber: ExerciseAnimation = {
        let base = plank(toeX: 30, shoulderY: 281, forearms: false, effort: 0.7, head: -6)
        func drive(_ near: Bool) -> BodyPose {
            var p = base
            p.hip = base.hip + CGPoint(x: 0, y: -10)
            p.effort = 1
            let knee = CGPoint(x: base.hip.x + 70, y: G.ground - 52)
            if near { p.footN = knee; p.footAngN = 35 } else { p.footF = knee + G.far; p.footAngF = 35 }
            return p
        }
        return ExerciseAnimation(
            id: "mountainClimber", name: "Mountain climbers", muscles: [.core, .shoulders, .quads],
            wide: true, scale: 0.86, raise: 95, level: "Intermédiaire",
            phases: [
                AnimPhase(duration: 0.32, label: "Genou droit", cue: "Ramène le genou vers la poitrine", pose: drive(true), step: 1),
                AnimPhase(duration: 0.28, label: "Retour", cue: "Bassin bas, épaules au-dessus des mains", pose: base, step: 0),
                AnimPhase(duration: 0.32, label: "Genou gauche", cue: "Alterne vite, garde le gainage", pose: drive(false), step: 1),
                AnimPhase(duration: 0.28, label: "Retour", cue: "Respire en rythme", pose: base, step: 2)
            ],
            steps: ["En position de pompe, mains sous les épaules.",
                    "Ramène un genou vers la poitrine, puis l'autre, en alternance rapide.",
                    "Garde le bassin bas et le ventre serré."],
            mistakes: ["Fesses trop hautes.",
                       "Épaules qui reculent derrière les mains.",
                       "Rebondir sans gainage."])
    }()

    static let rdl: ExerciseAnimation = {
        let top = stand(hip: CGPoint(x: 192, y: 197), torso: 2, effort: 0.2,
                        handsAt: { sh, _ in CGPoint(x: sh.x + 4, y: sh.y + 112) })
        let bottom = stand(hip: CGPoint(x: 146, y: 214), torso: 78, head: -40, effort: 1,
                           handsAt: { sh, _ in CGPoint(x: sh.x + 2, y: sh.y + 112) })
        return ExerciseAnimation(
            id: "rdl", name: "Soulevé de terre roumain", muscles: [.hamstrings, .glutes, .back], dumbbells: true,
            level: "Intermédiaire",
            phases: [
                AnimPhase(duration: 1.6, label: "Descente", cue: "Fesses loin derrière, dos plat", pose: bottom, step: 1),
                AnimPhase(duration: 0.4, label: "Étirement", cue: "Charges près des jambes, sens l'arrière des cuisses", pose: bottom, step: 2),
                AnimPhase(duration: 1.1, label: "Remontée", cue: "Pousse les hanches vers l'avant", pose: top, step: 3),
                AnimPhase(duration: 0.7, label: "En haut", cue: "Serre les fessiers, épaules basses", pose: top, step: 0)
            ],
            steps: ["Debout, haltères devant les cuisses, genoux légèrement fléchis.",
                    "Pousse les fesses loin en arrière, dos plat, buste qui s'incline.",
                    "Charges près des jambes jusqu'à sentir l'étirement derrière les cuisses.",
                    "Remonte en poussant les hanches vers l'avant."],
            mistakes: ["Dos arrondi : garde la poitrine ouverte.",
                       "Plier les genoux comme un squat.",
                       "Haltères qui s'éloignent des jambes."])
    }()

    static let row: ExerciseAnimation = {
        let hip = CGPoint(x: 150, y: 226)
        let down = stand(hip: hip, torso: 68, head: -34, effort: 0.3,
                         handsAt: { sh, _ in CGPoint(x: sh.x + 4, y: sh.y + 112) })
        let up = stand(hip: hip, torso: 68, head: -34, effort: 1,
                       handsAt: { sh, h in h.lerp(sh, 0.45) + CGPoint(x: -4, y: 26) })
        return ExerciseAnimation(
            id: "row", name: "Rowing haltères", muscles: [.back, .biceps], dumbbells: true,
            phases: [
                AnimPhase(duration: 0.8, label: "Tirage", cue: "Tire les coudes vers le haut et l'arrière", pose: up, step: 1),
                AnimPhase(duration: 0.4, label: "Serre", cue: "Serre les omoplates", pose: up, step: 2),
                AnimPhase(duration: 1.1, label: "Descente", cue: "Descends lentement, dos plat", pose: down, step: 3),
                AnimPhase(duration: 0.5, label: "Bras tendus", cue: "Buste penché, genoux souples", pose: down, step: 0)
            ],
            steps: ["Buste penché à 45° environ, dos plat, haltères bras tendus.",
                    "Tire les coudes vers le haut et l'arrière, le long du corps.",
                    "Serre les omoplates en haut du mouvement.",
                    "Redescends lentement."],
            mistakes: ["Dos rond : poitrine ouverte.",
                       "Tirer avec l'élan du buste.",
                       "Hausser les épaules."])
    }()

    static let calfRaise: ExerciseAnimation = {
        let flatPose = stand(hip: CGPoint(x: 192, y: 194), torso: 2, hands: .hips, effort: 0.2)
        let a = G.ankleForToe(242, 26)
        let dy = G.flat - a.y
        var raised = stand(hip: CGPoint(x: a.x, y: 194 - dy), torso: 2, hands: .hips, effort: 1, footAng: 26)
        raised.footN = a
        raised.footF = a + G.far
        return ExerciseAnimation(
            id: "calfRaise", name: "Mollets debout", muscles: [.calves],
            phases: [
                AnimPhase(duration: 0.8, label: "Montée", cue: "Monte sur la pointe des pieds", pose: raised, step: 1),
                AnimPhase(duration: 0.5, label: "En haut", cue: "Tiens une seconde, serre les mollets", pose: raised, step: 1),
                AnimPhase(duration: 1.0, label: "Descente", cue: "Redescends lentement", pose: flatPose, step: 2),
                AnimPhase(duration: 0.4, label: "En bas", cue: "Talons au sol", pose: flatPose, step: 0)
            ],
            steps: ["Debout, pieds largeur de hanches, mains sur les hanches.",
                    "Monte le plus haut possible sur la pointe des pieds.",
                    "Redescends lentement jusqu'aux talons."],
            mistakes: ["Rebondir sans contrôle.",
                       "Chevilles qui partent vers l'extérieur.",
                       "Amplitude trop courte."])
    }()

    static let gluteBridge: ExerciseAnimation = {
        let shoulders = CGPoint(x: 112, y: 374)
        func bridge(_ elevation: Double, _ effort: Double) -> BodyPose {
            let r = G.rad(elevation)
            let hip = CGPoint(x: shoulders.x + G.torso * cos(r), y: shoulders.y - G.torso * sin(r))
            let torso = G.angle(of: shoulders - hip)
            let ankle = CGPoint(x: 300, y: G.flat)
            return BodyPose(hip: hip, torso: torso, head: -90 - torso,
                            footN: ankle, footF: ankle + G.far,
                            handN: CGPoint(x: 222, y: G.ground - 9), handF: CGPoint(x: 214, y: G.ground - 9),
                            effort: effort)
        }
        let down = bridge(3, 0.2), up = bridge(34, 1)
        return ExerciseAnimation(
            id: "gluteBridge", name: "Pont fessier", muscles: [.glutes, .hamstrings], wide: true, scale: 0.9, raise: 95,
            phases: [
                AnimPhase(duration: 0.9, label: "Montée", cue: "Pousse dans les talons, monte le bassin", pose: up, step: 1),
                AnimPhase(duration: 0.6, label: "En haut", cue: "Serre les fessiers, corps aligné", pose: up, step: 2),
                AnimPhase(duration: 1.1, label: "Descente", cue: "Redescends vertèbre par vertèbre", pose: down, step: 3),
                AnimPhase(duration: 0.5, label: "En bas", cue: "Bassin effleure le sol", pose: down, step: 0)
            ],
            steps: ["Allongé sur le dos, genoux pliés, pieds à plat près des fesses.",
                    "Pousse dans les talons et monte le bassin.",
                    "En haut, serre les fessiers : épaules, hanches et genoux alignés.",
                    "Redescends lentement."],
            mistakes: ["Cambrer le bas du dos en haut.",
                       "Pousser sur la pointe des pieds.",
                       "Genoux qui s'écartent."])
    }()
}
