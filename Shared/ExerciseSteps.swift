// ExerciseSteps.swift — consignes écrites des exercices qui n'ont pas (encore) d'animation.
// La fiche « Comment faire ? » ne doit jamais être vide : sans animation ni consignes du plan,
// elle affiche ces étapes (retour du propriétaire : sans illustration, il n'y avait aucune description).

import Foundation

enum ExerciseSteps {

    /// Consignes trouvées d'après le nom de l'exercice (sans accents ni majuscules), ou nil.
    static func steps(forName name: String) -> [String]? {
        let n = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
        // Clé en début de mot : « traction » ne doit pas trouver « rétractions ».
        return catalogue.first { entry in
            entry.keys.contains { n.range(of: "\\b" + NSRegularExpression.escapedPattern(for: $0), options: .regularExpression) != nil }
        }?.steps
    }

    /// Ordre important : la première entrée qui correspond l'emporte (le plus précis d'abord).
    private static let catalogue: [(keys: [String], steps: [String])] = [
        (["jab-cross-crochet"], [
            "En garde, poings au menton, pieds décalés.",
            "Jab : bras avant tendu vite, puis retour en garde.",
            "Cross : bras arrière, en tournant la hanche et le pied arrière.",
            "Crochet du bras avant, coude à hauteur du poing, puis retour en garde."]),
        (["jab-cross", "direct"], [
            "En garde, poings au menton, pieds décalés.",
            "Jab : bras avant tendu vite, puis retour en garde.",
            "Cross : bras arrière, en tournant la hanche et le pied arrière.",
            "Enchaîne les deux sans t'arrêter, souffle à chaque coup."]),
        (["crochet"], [
            "En garde, poings au menton.",
            "Bras plié à 90°, coude à hauteur du poing.",
            "Pivote sur le pied du même côté : le coup part de la hanche.",
            "Alterne gauche et droite, retour en garde à chaque fois."]),
        (["uppercut"], [
            "En garde, fléchis un peu les genoux.",
            "Pousse sur les jambes et monte le poing de bas en haut, paume vers toi.",
            "Le coude reste près du corps.",
            "Alterne gauche et droite."]),
        (["coups de pied", "low kick", "pied bas"], [
            "En garde, poids sur la jambe avant.",
            "Pivote sur le pied d'appui et fouette avec le tibia de la jambe arrière, à hauteur de cuisse.",
            "Le bras du même côté descend pour équilibrer.",
            "Reviens en garde, puis change de jambe."]),
        (["montees de genoux", "montee de genoux"], [
            "Cours sur place en montant les genoux à hauteur de hanches.",
            "Reste sur l'avant du pied, buste droit.",
            "Les bras accompagnent, comme pour un sprint."]),
        (["coups de genou", "genoux au sac", "genoux en shadow", "genoux"], [
            "Mains devant toi, comme si tu tenais la nuque d'un adversaire.",
            "Tire vers le bas et monte le genou fort vers l'avant.",
            "Buste droit, gainé.",
            "Alterne les jambes."]),
        (["enchainement libre", "shadow"], [
            "En garde, sur l'avant des pieds, toujours en mouvement.",
            "Enchaîne 2 à 4 coups (jab, cross, crochets, genoux), puis bouge.",
            "Varie les rythmes : rafales rapides, puis enchaînements plus lourds.",
            "Retour en garde après chaque série de coups."]),
        (["burpee"], [
            "Debout, descends en squat et pose les mains au sol.",
            "Saute les pieds en arrière : position de pompe.",
            "Ramène les pieds près des mains.",
            "Saute bras en l'air, puis enchaîne."]),
        (["kettlebell swing", "swing"], [
            "Pieds un peu plus larges que les hanches, kettlebell tenue à deux mains.",
            "Bascule le buste en arrière des hanches, dos plat, kettlebell entre les jambes.",
            "Pousse les hanches vers l'avant d'un coup sec : la kettlebell monte à hauteur de poitrine.",
            "Les bras guident, ce sont les fessiers qui travaillent."]),
        (["crunch"], [
            "Allongé sur le dos, genoux fléchis, pieds au sol, mains aux tempes.",
            "Enroule le haut du dos en soufflant, regard vers le plafond.",
            "Ne tire pas sur la nuque.",
            "Redescends lentement."]),
        (["releves de jambes", "leg raise"], [
            "Allongé sur le dos, mains sous les fesses, jambes tendues.",
            "Bas du dos collé au sol.",
            "Monte les jambes jusqu'à la verticale.",
            "Redescends lentement, sans toucher le sol."]),
        (["russian twist"], [
            "Assis, genoux fléchis, buste incliné en arrière, dos droit.",
            "Pieds au sol (plus dur : pieds décollés).",
            "Tourne les épaules d'un côté puis de l'autre, mains jointes.",
            "Le regard suit les mains."]),
        (["hollow"], [
            "Allongé sur le dos, bras tendus derrière la tête.",
            "Bas du dos collé au sol.",
            "Décolle épaules et jambes tendues de quelques centimètres : forme de banane.",
            "Tiens la position en respirant."]),
        (["nordic"], [
            "À genoux, pieds calés sous un meuble lourd ou tenus.",
            "Corps droit des genoux à la tête.",
            "Descends vers l'avant le plus lentement possible.",
            "Rattrape-toi avec les mains, puis remonte en t'aidant des bras."]),
        (["traction", "pull-up", "pull up"], [
            "Suspendu à la barre, mains un peu plus larges que les épaules.",
            "Serre les omoplates et tire jusqu'au menton au-dessus de la barre.",
            "Redescends bras tendus, sans élan.",
            "Trop dur ? Pieds sur une chaise pour t'aider."]),
        (["pompes piquees", "pike"], [
            "Position de pompe, puis monte les fesses : corps en V inversé.",
            "Plie les bras : la tête descend entre les mains.",
            "Repousse le sol pour remonter.",
            "Plus dur : pieds sur une chaise."]),
        (["developpe au-dessus", "developpe militaire", "overhead press"], [
            "Debout, haltères à hauteur des épaules, gainé.",
            "Pousse les bras au-dessus de la tête, sans cambrer le dos.",
            "Redescends lentement aux épaules."]),
        (["course sur place"], [
            "Alterne sprint sur place, montées de genoux et petits pas rapides.",
            "Reste sur l'avant du pied, bras actifs.",
            "Garde un rythme que tu tiens jusqu'au bout de l'atelier."]),
        (["rameur"], [
            "Pieds sanglés, bras tendus, dos droit.",
            "Pousse d'abord avec les jambes, puis bascule le buste, puis tire la poignée au nombril.",
            "Reviens dans l'ordre inverse : bras, buste, jambes.",
            "Rythme régulier, environ 2 fois plus long au retour qu'à la poussée."]),
        (["dead bug"], [
            "Allongé sur le dos, bras tendus vers le plafond, genoux à 90°.",
            "Bas du dos collé au sol.",
            "Tends le bras droit et la jambe gauche vers le sol, sans toucher.",
            "Reviens et alterne."]),
        (["jumping jack"], [
            "Debout, pieds joints, bras le long du corps.",
            "Saute en écartant les pieds et en montant les bras au-dessus de la tête.",
            "Saute à nouveau pour revenir pieds joints.",
            "Reste sur l'avant du pied, rythme régulier."])
    ]
}
