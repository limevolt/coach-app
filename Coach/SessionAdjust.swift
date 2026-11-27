// SessionAdjust.swift — adapter une séance : autre activité, sans matériel, séances par défaut

import Foundation

// MARK: - Activité choisie

enum ActivityChoice: String, CaseIterable, Identifiable {
    /// Course classique (tout sauf les escaliers).
    case run
    case strength
    case martial
    /// Escaliers : présentés sous l'onglet « Course » (#73).
    case stairs

    var id: String { rawValue }

    /// Choix « Avec / Sans matériel » possible dans « Adapter » (renfo, et martial cross si la séance
    /// a des exercices au sac : voir `PlannedSession.hasHomeVariant`).
    var hasEquipmentChoice: Bool { self == .strength || self == .martial }

    var label: String {
        switch self {
        case .run: return "Course"
        case .strength: return "Renfo"
        case .martial: return "Martial cross"
        case .stairs: return "Escaliers"
        }
    }

    /// Onglets d'« Adapter » : les escaliers sont un genre de course, choisi sous « Course » (#73).
    static let tabs: [ActivityChoice] = [.run, .strength, .martial]
    var tab: ActivityChoice { self == .stairs ? .run : self }
    /// Genres de course proposés sous l'onglet « Course », toujours tous les deux (retour du propriétaire, #73).
    static let runKinds: [(value: ActivityChoice, label: String)] = [(.stairs, "Escaliers"), (.run, "Course classique")]

    /// Ordre de préférence quand l'app cherche une séance de ce type dans le plan.
    func rank(_ s: PlannedSession) -> Int? {
        switch self {
        // « Côtes ou escaliers » : escaliers en 2e choix (des côtes chez qui n'a pas d'escalier), jamais
        // « course classique », pour qu'on puisse la remplacer par un footing (revue #73).
        case .run: return s.type == .run && !s.isStairs && !s.isHillsOrStairs ? 0 : nil
        case .stairs: return s.isStairs ? 0 : (s.isHillsOrStairs ? 1 : nil)
        case .martial: return s.isMartial ? 0 : nil
        case .strength:
            if s.type == .strength { return 0 }
            if s.type == .circuit && !s.isMartial { return 1 }
            return nil
        }
    }
}

extension PlannedSession {
    /// Martial cross = circuit dont le titre parle de martial, boxe ou sac de frappe.
    var isMartial: Bool {
        guard type == .circuit else { return false }
        let t = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        return ["martial", "boxe", "sac de frappe", "frappe"].contains { t.contains($0) }
    }

    /// « Sans matériel » a un sens : renfo, ou martial cross avec des exercices au sac ou sur tapis
    /// (pas un cours collectif, dont le contenu est celui du cours).
    var hasHomeVariant: Bool {
        if type == .strength { return true }
        guard isMartial, let circuit else { return false }
        return circuit.exercises.contains { Bodyweight.isBagExercise($0) || $0.name.localizedCaseInsensitiveContains("ou tapis") }
    }

    var activity: ActivityChoice {
        if isMartial { return .martial }
        if isStairs || isHillsOrStairs { return .stairs }
        return type == .run ? .run : .strength
    }

    /// La séance réellement à faire : variante sans matériel appliquée si besoin.
    var effective: PlannedSession {
        guard withoutEquipment else { return self }
        var s = self
        s.title = Bodyweight.homeTitle(title)
        let header = isMartial
            ? "- **Version maison, sans matériel** : les exercices au sac passent en shadow boxing."
            : "- **Version maison, sans matériel** : les exercices avec charge sont remplacés."
        let home = notes.map(Bodyweight.homeText).map { isMartial ? Bodyweight.shadowText($0) : $0 }
        s.notes = [header, home].compactMap { $0 }.joined(separator: "\n")
        if var strength = s.strength {
            strength.exercises = strength.exercises.map(Bodyweight.convert)
            s.strength = strength
        }
        if var circuit = s.circuit {
            // Martial cross seulement : « au sac » = sac de frappe (pas un sac à dos ou un sac lesté de renfo).
            circuit.exercises = circuit.exercises.map { e in
                (isMartial ? Bodyweight.shadowBoxing(e) : nil) ?? Bodyweight.convert(e)
            }
            s.circuit = circuit
        }
        return s
    }
}

// MARK: - Variantes sans matériel

enum Bodyweight {
    private struct Rule {
        let keys: [String]
        let name: String
        let animation: String?
        let instructions: [String]
        /// true = remplacé à la maison même sans charge indiquée (mouvement qui a besoin de matériel
        /// ou qu'on rend plus dur en le faisant sur une jambe).
        var always = false
        /// Machine de cardio : se fait en durée, pas en répétitions (ex. « 500 m de rameur »).
        var cardio = false
    }

    private static let machinePattern = "(rameur|elliptique|ski ?erg|v[ée]lo d'appartement|v[ée]lo stationnaire|assault ?bike|air ?bike|stepper)"

    /// Machines de cardio de la salle → équivalent maison, dans les notes de la séance.
    private static let machineText: [(String, String)] = [
        ("(?i)\\b(au |à l')\(machinePattern)\\b", "en jumping jacks"),
        ("(?i)\\b\(machinePattern)\\b", "jumping jacks"),
        ("(?i)\\b(sur le |au )tapis de course\\b", "en course sur place"),
        ("(?i)\\btapis de course\\b", "course sur place"),
        ("(?i)\\bà la salle\\b", "à la maison")
    ]

    /// Remplace les machines citées dans un texte par leur équivalent maison.
    static func homeText(_ text: String) -> String {
        machineText.reduce(text) { t, r in
            t.replacingOccurrences(of: r.0, with: r.1, options: .regularExpression)
        }
    }

    /// « Renfo salle » → « Renfo maison », « Renfo B — haltères » → « Renfo B — poids du corps (maison) ».
    static func homeTitle(_ title: String) -> String {
        var t = title
        for (pattern, replacement) in [("(?i)\\bsalle\\b", "maison"), ("(?i)halt[eè]res?", "poids du corps")] {
            t = t.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        t = homeText(t)
        return t.localizedCaseInsensitiveContains("maison") ? t : t + " (maison)"
    }

    /// Ordre important : la première règle qui correspond l'emporte.
    private static let rules: [Rule] = [
        // Avant la règle des machines : « Course sur place ou tapis » ne doit plus parler de tapis.
        Rule(keys: ["ou tapis"],
             name: "Course sur place", animation: nil,
             instructions: ["Alterne sprint sur place, montées de genoux et petits pas rapides.",
                            "Reste sur l'avant du pied, bras actifs.",
                            "Garde un rythme que tu tiens jusqu'au bout de l'atelier."],
             always: true, cardio: true),
        Rule(keys: ["rameur", "tapis de course", "elliptique", "ski erg", "skierg", "assault", "airbike", "air bike",
                    "stepper", "velo d'appart", "velo stationnaire", "spinning"],
             name: "Cardio maison : jumping jacks et montées de genoux", animation: "jumpingJack",
             instructions: ["Alterne 30 s de jumping jacks et 30 s de montées de genoux.",
                            "Garde un rythme où tu peux encore parler.",
                            "Pas de place ? Course sur place."],
             always: true, cardio: true),
        Rule(keys: ["roumain", "rdl", "deadlift", "souleve de terre"],
             name: "Soulevé de terre roumain sur une jambe", animation: nil,   // "rdl" = version aux haltères, sur deux jambes
             instructions: ExerciseSteps.steps(forName: "Soulevé de terre roumain sur une jambe") ?? [],
             always: true),
        Rule(keys: ["squat"],
             name: "Squat sauté", animation: "squatJump",
             instructions: ["Pieds largeur de hanches, descends jusqu'aux cuisses parallèles au sol.",
                            "Pousse fort dans le sol et saute.",
                            "Réceptionne-toi en souplesse, genoux fléchis, et enchaîne."]),
        Rule(keys: ["fente", "lunge"],
             name: "Fentes alternées", animation: "lunge",
             instructions: ["Grand pas en avant, descends jusqu'à ce que le genou arrière frôle le sol.",
                            "Genou avant au-dessus de la cheville.",
                            "Remonte en poussant dans le talon avant, puis change de jambe."]),
        Rule(keys: ["rowing", "row", "tirage"],
             name: "Rowing sac à dos", animation: nil,   // "row" = version aux haltères
             instructions: ExerciseSteps.steps(forName: "Rowing sac à dos") ?? [],
             always: true),
        Rule(keys: ["mollet", "calf"],
             name: "Mollets sur une marche, une jambe", animation: nil,   // "calfRaise" = deux pieds, au sol
             instructions: ExerciseSteps.steps(forName: "Mollets sur une marche, une jambe") ?? [],
             always: true),
        Rule(keys: ["pont", "hip thrust", "bridge", "fessier"],
             name: "Pont fessier une jambe", animation: nil,   // "gluteBridge" = deux pieds au sol
             instructions: ExerciseSteps.steps(forName: "Pont fessier une jambe") ?? [],
             always: true),
        Rule(keys: ["developpe", "press", "pompe", "bench"],
             name: "Pompes", animation: "pushup",
             instructions: ["Mains un peu plus larges que les épaules.",
                            "Corps gainé, de la tête aux talons.",
                            "Descends la poitrine près du sol, remonte en poussant.",
                            "Trop dur ? Genoux au sol."])
    ]

    private static func normalized(_ s: String) -> String { EquipmentText.normalized(s) }

    /// Exercice avec charge ou matériel ? (poids chiffré, ou matériel cité dans le nom, la note ou les consignes)
    static func needsEquipment(_ e: Exercise) -> Bool {
        if e.weightKg != nil { return true }
        return ([e.name, e.notes ?? ""] + (e.instructions ?? [])).contains(where: EquipmentText.mentions)
    }

    /// Noms d'exercices déjà sans matériel : jamais remplacés par une variante intégrée.
    private static let bodyweightNames = ["inverse", "sous une table", "poids du corps", "sans charge", "sans materiel"]

    /// Variante intégrée qui porte exactement ce nom (« Soulevé de terre roumain sur une jambe »…).
    private static func rule(named name: String) -> Rule? {
        let n = normalized(name)
        return rules.first { normalized($0.name) == n }
    }

    /// Consignes ou erreurs qui ne parlent pas de matériel, sinon nil (jamais celles de la version avec matériel).
    private static func withoutEquipmentText(_ lines: [String]?) -> [String]? {
        guard let lines, !lines.isEmpty, !lines.contains(where: EquipmentText.mentions) else { return nil }
        return lines
    }

    static func convert(_ e: Exercise) -> Exercise {
        // 1. Variante prévue par le coach
        if let alt = e.noEquipment {
            // Consignes et animation de la variante elle-même : celles du plan, sinon celles de la variante
            // intégrée du même nom. Jamais celles de l'exercice avec matériel.
            let known = rule(named: alt.name)
            return Exercise(name: alt.name,
                            sets: alt.sets ?? e.sets,
                            reps: alt.reps ?? (alt.durationSec == nil ? e.reps : nil),
                            durationSec: alt.durationSec ?? (alt.reps == nil ? e.durationSec : nil),
                            weightKg: nil,
                            restSec: alt.restSec ?? e.restSec,
                            notes: alt.notes ?? "Sans matériel (au lieu de « \(e.name) »)",
                            instructions: alt.instructions ?? known?.instructions,
                            mistakes: nil,
                            animation: alt.animation ?? known?.animation,
                            videoURL: nil,
                            homeVariant: true)
        }
        let n = normalized(e.name)
        let rule = rules.first { r in r.keys.contains { n.contains($0) } }
        let loaded = needsEquipment(e)

        // 2. Déjà au poids du corps (pompes, gainage, dead bug, rowing inversé sous une table…) : rien à changer
        guard loaded || (rule?.always == true && !bodyweightNames.contains { n.contains($0) }) else { return e }
        if let rule, normalized(rule.name) == n {
            var same = e
            same.weightKg = nil
            same.videoURL = nil
            same.noEquipment = nil
            same.homeVariant = true
            same.instructions = withoutEquipmentText(e.instructions) ?? rule.instructions
            same.mistakes = withoutEquipmentText(e.mistakes)
            same.animation = rule.animation
            return same
        }

        // 3. Variante intégrée
        var out = e
        out.weightKg = nil
        out.videoURL = nil
        out.noEquipment = nil
        out.homeVariant = true
        if let rule {
            out.name = rule.name
            out.animation = rule.animation
            out.instructions = rule.instructions
            out.mistakes = nil
            if rule.cardio && out.durationSec == nil {
                out.reps = nil
                out.durationSec = 300
            }
        } else {
            // Pas de variante connue : même mouvement sans charge. Les consignes et erreurs qui parlent
            // de matériel sont retirées (avertissement à la place) ; l'animation aux haltères n'est plus affichée.
            out.name = e.name + " (sans charge)"
            out.instructions = withoutEquipmentText(e.instructions)
            out.mistakes = withoutEquipmentText(e.mistakes)
        }
        out.notes = "Sans matériel (au lieu de « \(e.name) »)"
        return out
    }
}

extension Bodyweight {
    /// « Jab-cross au sac » → « Jab-cross en shadow boxing » : mêmes séries, même durée, consignes adaptées.
    private static let bagPattern = "(?i)\\s+(au|dans le) sac( de frappe)?\\b(?!\\s*(à|a) dos|\\s*lest)"

    static func isBagExercise(_ e: Exercise) -> Bool {
        e.name.range(of: bagPattern, options: .regularExpression) != nil
    }

    /// Notes d'une séance de martial cross en version maison : plus de sac de frappe.
    static func shadowText(_ text: String) -> String {
        [("(?i)il faut un (\\*\\*)?sac de frappe(\\*\\*)?\\.?", "Sans sac : **shadow boxing**."),
         (bagPattern, " en shadow boxing")].reduce(text) { t, r in
            t.replacingOccurrences(of: r.0, with: r.1, options: .regularExpression)
        }
    }

    static func shadowBoxing(_ e: Exercise) -> Exercise? {
        guard e.noEquipment == nil else { return nil }   // la variante prévue par le coach l'emporte
        let pattern = bagPattern
        guard isBagExercise(e) else { return nil }
        var out = e
        out.name = e.name.replacingOccurrences(of: pattern, with: " en shadow boxing", options: .regularExpression)
        out.weightKg = nil
        out.videoURL = nil
        out.instructions = ["Même enchaînement qu'au sac, dans le vide, face à un adversaire imaginaire.",
                            "Garde haute, menton rentré, bouge sur l'avant des pieds.",
                            "Frappe vite mais sans verrouiller le coude ni le genou.",
                            "Reviens en garde après chaque coup."]
        out.mistakes = nil
        out.homeVariant = true
        out.notes = "Sans matériel (au lieu de « \(e.name) »)"
        return out
    }
}

// MARK: - Séances par défaut (quand le plan n'a rien du type choisi)

enum DefaultSessions {
    static func make(_ choice: ActivityChoice, id: String, date: String, time: String?) -> PlannedSession {
        switch choice {
        case .run:
            let step = RunStep(purpose: "work",
                               goal: StepGoal(type: "time", value: 30, unit: "min"),
                               alert: StepAlert(type: "hrZone", zone: 2))
            return PlannedSession(id: id, date: date, time: time, type: .run,
                                  title: "Footing facile 30 min",
                                  notes: "- Footing en **zone 2** : tu dois pouvoir parler.\n- Séance proposée par l'app.",
                                  run: RunWorkout(location: "outdoor", blocks: [RunBlock(iterations: 1, steps: [step])]))
        case .stairs:
            return PlannedSession(id: id, date: date, time: time, type: .run,
                                  title: "Escaliers 30 min",
                                  notes: "- Il faut un **escalier**.\n- Montées à ton rythme, descentes en marchant.\n- Séance proposée par l'app.",
                                  run: RunWorkout(location: "outdoor",
                                                  warmup: RunStep(purpose: nil,
                                                                  goal: StepGoal(type: "time", value: 10, unit: "min"),
                                                                  alert: StepAlert(type: "hrZone", zone: 2)),
                                                  blocks: [RunBlock(iterations: 1, steps: [
                                                      RunStep(purpose: "work",
                                                              goal: StepGoal(type: "time", value: 15, unit: "min"),
                                                              alert: StepAlert(type: "hrZone", zone: 3))])],
                                                  cooldown: RunStep(purpose: nil,
                                                                    goal: StepGoal(type: "time", value: 5, unit: "min"),
                                                                    alert: nil)))
        case .strength:
            return PlannedSession(id: id, date: date, time: time, type: .strength,
                                  title: "Renfo maison",
                                  notes: "- Renfo complet **au poids du corps**.\n- 60 s de repos entre les séries.\n- Séance proposée par l'app.",
                                  strength: StrengthWorkout(exercises: [
                                      ex("Squat", sets: 3, reps: 15, animation: "squat"),
                                      ex("Pompes", sets: 3, reps: 10, animation: "pushup"),
                                      ex("Pont fessier", sets: 3, reps: 15, animation: "gluteBridge"),
                                      ex("Mollets sur une marche", sets: 3, reps: 15, animation: "calfRaise"),
                                      ex("Rowing sac à dos", sets: 3, reps: 12, animation: "row"),
                                      ex("Dead bug", sets: 3, reps: 10, instructions: [
                                          "Allongé sur le dos, bras tendus vers le plafond, genoux à 90°.",
                                          "Bas du dos collé au sol.",
                                          "Tends le bras droit et la jambe gauche vers le sol, sans toucher.",
                                          "Reviens et alterne."]),
                                      ex("Gainage latéral", sets: 3, durationSec: 30, animation: "sidePlank")
                                  ]))
        case .martial:
            return PlannedSession(id: id, date: date, time: time, type: .circuit,
                                  title: "Martial cross",
                                  notes: "- 4 tours : **40 s d'effort, 20 s de repos**.\n- Il faut un **sac de frappe**.\n- Séance proposée par l'app.",
                                  circuit: CircuitWorkout(rounds: 4, workSec: 40, restSec: 20, roundRestSec: 60, prepareSec: 10, exercises: [
                                      ex("Directs au sac", instructions: ["Garde haute, menton rentré.", "Enchaîne gauche-droite, en tournant la hanche.", "Reviens en garde après chaque coup."]),
                                      ex("Crochets au sac", instructions: ["Coude à hauteur du poing.", "Pivote sur le pied avant.", "Frappe avec tout le corps, pas seulement le bras."]),
                                      ex("Coups de genou au sac", instructions: ["Mains sur le haut du sac.", "Monte le genou en tirant le sac vers toi.", "Alterne les jambes."]),
                                      ex("Burpees", instructions: ["Descends mains au sol, saute pieds en arrière.", "Ramène les pieds, saute bras en l'air."]),
                                      ex("Crunch", instructions: ["Allongé, genoux fléchis, mains aux tempes.", "Enroule le buste en soufflant, sans tirer sur la nuque."])
                                  ]))
        }
    }

    private static func ex(_ name: String, sets: Int? = nil, reps: Int? = nil, durationSec: Int? = nil,
                           animation: String? = nil, instructions: [String]? = nil) -> Exercise {
        Exercise(name: name, sets: sets, reps: reps, durationSec: durationSec, restSec: sets == nil ? nil : 60,
                 instructions: instructions, animation: animation)
    }
}

// MARK: - Version d'origine (pour annuler une adaptation)

/// Séance telle qu'elle était avant la première adaptation, et séances modifiées en même temps (échange).
struct SessionOriginal: Codable, Hashable {
    var session: PlannedSession
    var linked: [String]
}

/// Versions d'origine, valables pour une version précise du plan.
struct OriginalsFile: Codable {
    var planKey: String
    var items: [String: SessionOriginal]
}

extension TrainingPlan {
    var key: String { "\(planId)-v\(version)" }
}
