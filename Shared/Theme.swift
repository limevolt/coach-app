// Theme.swift — identité visuelle de Coach (iPhone + montre)
// ⚠️ Ce fichier doit appartenir AUX DEUX cibles.
// Nouvelle ambiance (#40) : plus calme, un seul héros par écran, cartes sans bordure.

import SwiftUI

enum Theme {
    /// Fond : presque noir.
    static let bg = Color(hex: 0x06080B)
    /// Carte pleine : l'action du moment (une seule par écran), boutons ronds.
    static let card = Color(hex: 0x11151B)
    /// Fond un cran plus clair (tuile dans une carte, bouton sélectionné).
    static let card2 = Color(hex: 0x1A2029)
    /// Contours discrets : bouton secondaire, pastille de repos.
    static let line = Color(hex: 0x2A313C)
    /// Séparateur entre deux lignes d'une liste.
    static let separator = Color(hex: 0x141920)
    /// Chevron de fin de ligne : au moins 3:1 sur `bg`, `card` et `card2` (#113).
    static let chevron = Color(hex: 0x64707F)
    /// Contour d'un interrupteur ou d'une case non cochés (au moins 3:1 sur le fond, #45).
    static let controlStroke = Color(hex: 0x707A8A)
    /// Activité en plus (autre app, #54) : pastille grise.
    static let extraFill = Color(hex: 0x3A4250)
    static let text = Color(hex: 0xEEF2F7)
    static let muted = Color(hex: 0x8B97A8)
    static let accent = Color(hex: 0xC6F432)      // citron vert
    static let accentDark = Color(hex: 0x1B260A)  // texte sur fond citron vert
    static let teal = Color(hex: 0x2DD4BF)
    static let warm = Color(hex: 0xFF7A45)        // muscles, intensité
    static let danger = Color(hex: 0xFF9D7A)
    static let dangerBg = Color(hex: 0x1F1514)
    static let successBg = Color(hex: 0x18210F)

    /// Héros : dégradé citron vert → turquoise, réservé à la progression (accueil).
    static let heroGradient = LinearGradient(colors: [accent, teal], startPoint: .leading, endPoint: .trailing)

    /// Texte posé sur une pastille pleine (couleur du type de séance).
    static let onTint = bg

    static func color(for type: SessionType) -> Color {
        switch type {
        case .run: return warm
        case .strength: return teal
        case .circuit: return accent
        }
    }

    /// Titre compact pour l'écran de la montre.
    static let watchTitle = Font.coach(.footnote, weight: .semibold)
    /// Montre, pendant la séance : nom de l'exercice (suit la taille du texte).
    static let watchExercise = Font.coach(.headline, weight: .heavy)
    /// Montre : petit libellé en capitales (REPOS, ENSUITE…).
    static let watchLabel = Font.coach(.caption2, weight: .bold)
    /// Montre : chrono d'effort et nombre de répétitions, lisibles en plein effort.
    static let watchCountdown = Font.coach(size: 60, weight: .heavy)
    /// Montre : compte à rebours de repos, le plus grand possible.
    static let watchRestCountdown = Font.coach(size: 72, weight: .heavy)
    /// Montre : compte à rebours de départ (« 3 »), encore plus grand.
    static let watchStartCountdown = Font.coach(size: 88, weight: .heavy)

    /// Montre : fond plein écran pendant l'effort (teinte du type de séance).
    static func effortBackground(for type: SessionType) -> Color { effortBackground(color(for: type)) }
    static func effortBackground(_ tint: Color) -> Color { tint.opacity(0.22) }
    /// Montre : fond plein écran pendant le repos et la mise en place.
    static let restBackground = card

    /// Montre : marge autour du contenu, pour qu'aucun texte ne touche le bord arrondi de l'écran (#23).
    static let watchMargin: CGFloat = 8
    /// Montre : activité de la prochaine séance sur l'accueil.
    static let watchHomeActivity = Font.coach(.title2, weight: .heavy)
    /// Montre : contour de la valeur réglée par la Digital Crown.
    static let watchValueRadius: CGFloat = 12
    /// Montre : grands boutons de la page de commandes (pause, passer, repos, terminer).
    static let watchControlHeight: CGFloat = 56
    static let watchControlRadius: CGFloat = 20

    // Boutons et cartes de l'iPhone
    static let buttonRadius: CGFloat = Radius.m
    static let smallButtonRadius: CGFloat = Radius.m  // ancien nom : même rayon que buttonRadius
    static let heroCardRadius: CGFloat = Radius.card  // ancien nom, garder Radius.card
    /// Hauteur du bouton principal d'un écran ; `minTap` = cible tactile minimale (44 pt).
    static let primaryButtonHeight: CGFloat = 52
    /// Bouton principal d'une séance (« Démarrer »).
    static let largeButtonHeight: CGFloat = 64
    static let minTap: CGFloat = 44
    /// Hauteur d'une ligne de liste simple (titre + valeur + chevron).
    static let rowHeight: CGFloat = 52
    /// Contour d'un choix (assistant de création, #45) : gris fin, ou citron vert un peu plus épais quand choisi.
    static let selectionStroke: CGFloat = 1.5
    static let quietStroke: CGFloat = 1
    /// Marge intérieure d'un champ de saisie ou d'une pastille de choix.
    static let fieldPadding: CGFloat = Space.l
    static let chipPadding: CGFloat = Space.m
    /// Barre de progression de l'assistant.
    static let progressHeight: CGFloat = 4
    /// Choix en onglets (SegmentedChoice) : rayon d'une option et espace autour.
    static let segmentRadius: CGFloat = Radius.s  // concentrique : smallButtonRadius − segmentSpacing
    static let segmentSpacing: CGFloat = Space.xs
    /// Case à cocher (choix multiple) et interrupteur Coach (#45).
    static let checkboxSize: CGFloat = 26
    static let checkboxRadius: CGFloat = Radius.xs
    static let switchWidth: CGFloat = 52
    static let switchHeight: CGFloat = 32
    static let switchThumb: CGFloat = 24
    static let controlMarkFont = Font.system(size: 14, weight: .heavy)
    /// Fondu au-dessus d'une barre d'action fixée en bas : le contenu qui défile dessous n'est pas tranché.
    static let bottomFadeHeight: CGFloat = 32
    /// Étiquette discrète à côté d'un choix (« Conseillé », #57).
    static let tagRadius: CGFloat = Radius.xs
    /// Gros bouton de ressenti (#54).
    static let effortButtonHeight: CGFloat = 60
    /// Feuille « Noter mon effort » (#54).
    static let effortSheetHeight: CGFloat = 240
    /// Barres d'intensité (1 à 4) d'un niveau du plan (#57) : largeur, espace, hauteur de la 1re et pas.
    static let intensityBarWidth: CGFloat = 5
    static let intensityBarSpacing: CGFloat = 3
    static let intensityBarBase: CGFloat = 6
    static let intensityBarStep: CGFloat = 4

    // Espacements iPhone (multiples de 4/8)
    /// Marge latérale de l'écran.
    static let screenMargin: CGFloat = 20
    /// Espace entre deux blocs d'un écran.
    static let blockSpacing: CGFloat = Space.xl  // 24 (choix du propriétaire, 24/11/2026, #76)
    /// Vignettes d'exercices du détail de séance (maquette validée) : hauteur de l'image,
    /// espace entre deux colonnes, symbole quand l'exercice n'a pas encore d'illustration.
    static let exerciseTileHeight: CGFloat = 160
    static let tileSpacing: CGFloat = Space.m
    static let tileSymbolFont = Font.system(size: 34, weight: .semibold)
    static let exerciseFallbackSymbol = "figure.strengthtraining.functional"
    /// Écran « Le coach prépare ton plan » : petit coureur (réduit en très grand texte) et barre d'avancement.
    static let creationFigure: CGFloat = 180
    static let creationFigureCompact: CGFloat = 120
    static let creationBarWidth: CGFloat = 220
    /// Pastille de la coche « Ton plan est prêt » et taille de la coche.
    static let creationDone: CGFloat = 96
    static let creationDoneIcon = Font.system(size: 44, weight: .bold)
    /// Pastille d'un jour de la semaine (accueil).
    static let dayDot: CGFloat = 40
    /// Petit badge sur une pastille (séance manquée, deux séances le même jour).
    static let dotBadge: CGFloat = 16
    /// Tuile d'un jour libre dans « Adapter » (#73) et point « jour d'entraînement » dessous.
    static let dayTileWidth: CGFloat = 54
    static let dayTileHeight: CGFloat = 68
    static let dayTileSpacing: CGFloat = Space.s
    static let trainingDayDot: CGFloat = 6
    /// Petit titre gris au-dessus d'un choix qui dépend d'un autre (« Genre de course », « Matériel »).
    static let subChoiceTitleSpacing: CGFloat = Space.s

    // Barres de l'iPhone (#64) : barre d'onglets maison et boutons du haut sans bulle
    /// Hauteur de la barre d'onglets (hors zone du bas de l'écran).
    static let tabBarHeight: CGFloat = 56
    /// Trait citron vert au-dessus de l'onglet choisi.
    static let tabIndicatorWidth: CGFloat = 28
    static let tabIndicatorHeight: CGFloat = 3
    /// Pastille d'un onglet appuyé.
    static let tabPressRadius: CGFloat = Radius.s
    static let tabPressInset: CGFloat = 4
    /// Espace entre l'icône et le libellé d'un onglet ; hauteur réservée à l'icône.
    static let tabItemSpacing: CGFloat = 3
    /// Air entre le trait du haut de la barre et les icônes (retour du propriétaire, #64).
    static let tabItemTopPadding: CGFloat = Space.s
    static let tabIconHeight: CGFloat = 26
    /// Marge sous les libellés sur un iPhone à bouton d'accueil.
    static let tabBarBottomPadding: CGFloat = 6
    /// Icône d'un onglet (taille fixe, comme la barre d'Apple).
    static let tabIconFont = Font.system(size: 22, weight: .medium)
    /// Libellé d'un onglet : 12, taille fixe (appui long = visionneuse de grand contenu).
    static let tabLabelFont = Font.custom(Outfit.name(for: .medium), fixedSize: 12)
    static let tabLabelSelectedFont = Font.custom(Outfit.name(for: .semibold), fixedSize: 12)
    /// Icône d'un bouton du haut (•••, +), posée sur le fond, sans bulle.
    static let barIconFont = Font.system(size: 20, weight: .semibold)
    /// Bouton du haut appuyé : atténué.
    static let pressedOpacity: Double = 0.45
    /// Choix impossible (niveau grisé, #46) : titre et barres atténués, la raison reste lisible.
    static let unavailableOpacity: Double = 0.5

    // Icônes SF Symbols (taille fixe, graisse commune)
    /// Icône d'un bouton rond ou d'un état (•••, ✓ d'une ligne).
    static let iconFont = Font.system(size: 17, weight: .semibold)
    /// Icône du type dans une pastille ou en début de ligne.
    static let smallIconFont = Font.system(size: 15, weight: .semibold)
    /// Icône sur une pastille pleine (plus grasse pour rester lisible).
    static let tintedIconFont = Font.system(size: 15, weight: .bold)
    /// Chevron de fin de ligne, coche d'une étiquette.
    static let chevronFont = Font.system(size: 12, weight: .bold)
    /// Badge sur une pastille : icône « ! » et chiffre (taille fixe, le badge ne grandit pas).
    static let badgeFont = Font.system(size: 9, weight: .heavy)
    static let badgeTextFont = Font.custom(Outfit.name(for: .bold), fixedSize: 10)

    static func icon(for type: SessionType) -> String {
        switch type {
        case .run: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .circuit: return "flame.fill"
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    /// Ancien style de titre (très gras). Les écrans passés à la nouvelle ambiance utilisent
    /// l'échelle ci-dessous ; à retirer quand tous les écrans auront migré (#40).
    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .coach(size: size, weight: weight)
    }

    // MARK: Échelle de la nouvelle ambiance (#40) : 5 tailles, plus le texte secondaire.
    /// Héros : le seul gros chiffre de l'écran (taille fixe, en dégradé pour la progression).
    static let hero = Font.coach(size: 76, weight: .semibold)
    /// Titre d'écran : 30, semi-gras.
    static let screenTitle = Font.coach(size: 30, weight: .semibold)
    /// Chiffre ou titre de carte : 22, semi-gras.
    static let number = Font.coach(size: 22, weight: .semibold)
    /// Texte courant : 17, moyen.
    static let text = Font.coach(.body, weight: .medium)
    /// Étiquette : 12, semi-gras, en capitales grises (`Eyebrow`).
    static let label = Font.coach(size: 12, weight: .semibold)
    /// Lettre du jour d'aujourd'hui dans la semaine (#54) : plus grasse, en citron vert.
    static let labelStrong = Font.coach(size: 12, weight: .heavy)
    /// Texte secondaire gris sous un titre (15).
    static let detail = Font.coach(.subheadline)
    /// Unité à côté d'un chiffre (« min », « /10 »).
    static let unit = Font.coach(size: 14, weight: .medium)
}

extension View {
    /// Bouton principal plein (citron vert), pleine largeur. Indisponible : fond gris, texte gris lisible (#45).
    func primaryActionStyle(compact: Bool = false, large: Bool = false, enabled: Bool = true) -> some View {
        self.font(.coach(large ? .title3 : .body, weight: .bold))
            .foregroundStyle(enabled ? Theme.accentDark : Theme.muted)
            .frame(maxWidth: .infinity,
                   minHeight: compact ? Theme.minTap : (large ? Theme.largeButtonHeight : Theme.primaryButtonHeight))
            .background(enabled ? Theme.accent : Theme.card2,
                        in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                .stroke(enabled ? Color.clear : Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
    }

    /// Bouton discret (contour gris, texte blanc par défaut), pleine largeur : « Voir le détail », « Séance libre ».
    func quietActionStyle(color: Color = Theme.text) -> some View {
        self.font(.coach(.callout, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: Theme.minTap)
            .overlay(RoundedRectangle(cornerRadius: Theme.smallButtonRadius, style: .continuous)
                .stroke(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
    }

    /// Bouton secondaire (contour citron vert), pleine largeur.
    func secondaryActionStyle(compact: Bool = true) -> some View {
        self.font(.coach(compact ? .body : .title3, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: compact ? Theme.minTap : Theme.primaryButtonHeight)
            .overlay(RoundedRectangle(cornerRadius: compact ? Theme.smallButtonRadius : Theme.buttonRadius, style: .continuous)
                .stroke(Theme.accent.opacity(0.6), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

extension View {
    /// Choix sélectionnable (#45) : fond gris et contour citron vert quand choisi, contour gris sinon.
    /// Le citron vert plein reste réservé à l'action principale.
    func selectableStyle(isOn: Bool) -> some View {
        self.background(isOn ? Theme.card2 : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.smallButtonRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.smallButtonRadius, style: .continuous)
                .stroke(isOn ? Theme.accent : Theme.line, lineWidth: isOn ? Theme.selectionStroke : Theme.quietStroke))
            .contentShape(Rectangle())
    }

    /// Champ de saisie sur fond gris arrondi (#45).
    func fieldStyle() -> some View {
        self.font(.text)
            .padding(.horizontal, Theme.fieldPadding)
            .frame(minHeight: Theme.primaryButtonHeight)
            .background(Theme.card2, in: RoundedRectangle(cornerRadius: Theme.smallButtonRadius, style: .continuous))
    }
}

/// Carte pleine, sans bordure par défaut (#40). Une bordure colorée reste possible pour un
/// avertissement (`stroke: Theme.warm.opacity(0.5)`).
struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.cardPadding
    var radius: CGFloat = Radius.card
    var fill: Color = Theme.card
    var stroke: Color = .clear

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(stroke, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = Theme.cardPadding, radius: CGFloat = Radius.card, fill: Color = Theme.card, stroke: Color = .clear) -> some View {
        modifier(CardModifier(padding: padding, radius: radius, fill: fill, stroke: stroke))
    }
}

/// Petit titre en capitales, gris par défaut (#40). Une couleur seulement quand elle dit
/// le type de séance ou l'état (« FAIT »).
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text.uppercased())
            .font(.label)
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

/// Chiffre + unité grise (« 42 min », « 6 /10 ») avec son libellé dessous.
struct StatValue: View {
    let value: String
    var unit: String? = nil
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(value).font(.number).foregroundStyle(Theme.text)
                if let unit { Text(unit).font(.unit).foregroundStyle(Theme.muted) }
            }
            Text(label).font(.coach(.footnote)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Barre fixée en bas de l'écran (bouton principal, phrase d'explication), avec un fondu au-dessus
/// pour le contenu qui défile dessous. `fill` : fond de l'écran ou de la feuille.
struct BottomBar<Content: View>: View {
    var fill: Color = Theme.bg
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) { content() }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .background(fill)
            .background(alignment: .top) {
                LinearGradient(colors: [fill.opacity(0), fill], startPoint: .top, endPoint: .bottom)
                    .frame(height: Theme.bottomFadeHeight)
                    .offset(y: -Theme.bottomFadeHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// Étiquette arrondie (muscles, niveau…).
struct Chip: View {
    let text: String
    var hot = false

    var body: some View {
        Text(text)
            .font(.coach(size: 12, weight: hot ? .semibold : .medium))
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.xs)
            .foregroundStyle(hot ? Color(hex: 0x1A1205) : Theme.muted)
            .background(hot ? Theme.warm : Theme.card2, in: Capsule())
            .overlay(Capsule().stroke(hot ? Theme.warm : Theme.line, lineWidth: 1))
    }
}
