// ReportBuilder.swift — construit le texte du suivi à envoyer à Claude

import Foundation
import HealthKit

@MainActor
struct ReportBuilder {
    let plan: TrainingPlan?
    let logs: [SessionLog]
    let profile: String

    func build(days: Int, comment: String, includePlan: Bool, footer: Bool = true) async -> String {
        let health = HealthReader()
        try? await health.requestAuthorization()

        let cal = Calendar.current
        let end = Date.now
        let todayStart = cal.startOfDay(for: end)
        let start = cal.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        let prevStart = cal.date(byAdding: .day, value: -days, to: start) ?? start

        let workouts = (try? await health.workouts(from: start, to: end)) ?? []
        let bpm = HealthReader.bpm
        let ms = HKUnit.secondUnit(with: .milli)
        let rhr = await health.average(.restingHeartRate, unit: bpm, from: start, to: end)
        let rhrPrev = await health.average(.restingHeartRate, unit: bpm, from: prevStart, to: start)
        let hrv = await health.average(.heartRateVariabilitySDNN, unit: ms, from: start, to: end)
        let hrvPrev = await health.average(.heartRateVariabilitySDNN, unit: ms, from: prevStart, to: start)
        let weight = await health.average(.bodyMass, unit: .gramUnit(with: .kilo), from: start, to: end)
        let vo2 = await health.average(.vo2Max, unit: HKUnit(from: "ml/kg*min"), from: prevStart, to: end)

        let dayFmt = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        var out: [String] = []

        out.append("# Suivi entraînement — du \(start.formatted(dayFmt)) au \(end.formatted(dayFmt))")
        if let plan { out.append("Plan : \(plan.title) — \(plan.planId) v\(plan.version)") }
        if !profile.isEmpty { out.append("Profil : \(profile)") }
        if let days = TrainingDays.exportLine { out.append(days) }
        out.append("")

        // 0. Objectifs
        if let goals = plan?.goals, !goals.isEmpty {
            out.append("## Objectifs")
            for g in goals {
                var line = "- \(g.title) — échéance \(g.date)"
                if let days = g.daysLeft { line += " (J-\(days))" }
                if let b = g.baseline { line += " · départ : \(b)" }
                if let c = g.current { line += " · actuel : \(c)" }
                if let t = g.target { line += " · cible : \(t)" }
                if let p = g.progress { line += " · progression \(Int((p * 100).rounded())) %" }
                out.append(line)
            }
            out.append("")
        }

        // 1. Séances prévues
        out.append("## Séances prévues")
        let planned = (plan?.sessions ?? [])
            .filter { s in
                guard let d = s.dayStart else { return false }
                return d >= start && d <= todayStart
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        if planned.isEmpty { out.append("Aucune séance prévue sur la période.") }
        for s in planned {
            let log = logs.last { $0.sessionId == s.id }
            let matched = workouts.contains { w in
                guard let d = s.startDate, cal.isDate(w.start, inSameDayAs: d) else { return false }
                return s.type == .run ? w.activity == .running : w.activity != .running
            }
            var status: String
            if log != nil || matched { status = "✅ faite" }
            else if s.dayStart == todayStart { status = "⏳ prévue aujourd'hui" }
            else { status = "❌ non faite" }
            if let rpe = log?.rpe { status += " · effort \(rpe)/10" }
            var adapted: [String] = []
            if s.withoutEquipment { adapted.append("faite sans matériel") }
            if let change = s.changeLabel { adapted.append(change.lowercased()) }
            let extra = adapted.isEmpty ? "" : " (\(adapted.joined(separator: ", ")))"
            out.append("- \(s.date) · \(s.typeLabel) « \(s.title) » [\(s.id)]\(extra) : \(status)")
            if let note = log?.note, !note.isEmpty { out.append("  Note : \(note)") }
        }
        out.append("")

        // 2. Entraînements Apple Santé
        out.append("## Entraînements enregistrés (Apple Santé)")
        if workouts.isEmpty {
            out.append("Aucun entraînement trouvé (vérifie l'accès à Santé).")
        } else {
            out.append("| Date | Type | Durée | Distance | Allure | FC moy | FC max | kcal |")
            out.append("|---|---|---|---|---|---|---|---|")
            for w in workouts {
                let date = w.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                let hasDistance = (w.distanceKm ?? 0) > 0.2
                let distance = hasDistance ? String(format: "%.2f km", w.distanceKm ?? 0) : "—"
                let pace = hasDistance ? Pace.label(secondsPerKm: w.duration / (w.distanceKm ?? 1)) : "—"
                out.append("| \(date) | \(w.activity.frenchName) | \(Self.duration(w.duration)) | \(distance) | \(pace) | \(Self.int(w.avgHR)) | \(Self.int(w.maxHR)) | \(Self.int(w.kcal)) |")
            }
        }
        out.append("")

        // 3. Détail renfo et circuits (app montre)
        let strengthLogs = logs
            .filter { $0.completedAt >= start && $0.kind != "libre" && ($0.sets?.isEmpty == false) }
            .sorted { $0.completedAt < $1.completedAt }
        if !strengthLogs.isEmpty {
            out.append("## Détail renfo / circuits (réalisé)")
            for log in strengthLogs {
                let title = plan?.sessions.first { $0.id == log.sessionId }?.title ?? log.title ?? log.sessionId
                let rpe = log.rpe.map { " · effort \($0)/10" } ?? ""
                out.append("### \(title) — \(log.completedAt.formatted(dayFmt))\(rpe)")
                var order: [String] = []
                var byExercise: [String: [SetLog]] = [:]
                for set in log.sets ?? [] {
                    if byExercise[set.exercise] == nil { order.append(set.exercise) }
                    byExercise[set.exercise, default: []].append(set)
                }
                for name in order {
                    let sets = (byExercise[name] ?? []).map(Self.setLabel).joined(separator: ", ")
                    out.append("- \(name) : \(sets)")
                }
            }
            out.append("")
        }

        // 3 bis. Séances libres (minuteurs)
        let freeLogs = logs
            .filter { $0.completedAt >= start && $0.kind == "libre" }
            .sorted { $0.completedAt < $1.completedAt }
        if !freeLogs.isEmpty {
            out.append("## Séances libres (minuteurs)")
            for log in freeLogs {
                let work = (log.sets ?? []).reduce(0) { $0 + ($1.durationSec ?? 0) }
                let rpe = log.rpe.map { " · effort \($0)/10" } ?? ""
                out.append("- \(log.completedAt.formatted(dayFmt)) · « \(log.title ?? "Minuteur") » : \(log.sets?.count ?? 0) efforts, \(Durations.label(work)) de travail\(rpe)")
            }
            out.append("")
        }

        // 4. Récupération
        out.append("## Récupération (moyennes)")
        out.append("- FC au repos : \(Self.num(rhr, "bpm")) (période précédente : \(Self.num(rhrPrev, "bpm")))")
        out.append("- VFC (SDNN) : \(Self.num(hrv, "ms")) (période précédente : \(Self.num(hrvPrev, "ms")))")
        out.append("- Poids : \(Self.num(weight, "kg", digits: 1))")
        out.append("- VO2max estimée : \(Self.num(vo2, "ml/kg/min", digits: 1))")
        out.append("")

        // 5. Ressenti
        out.append("## Ressenti général")
        out.append(comment.isEmpty ? "—" : comment)
        out.append("")

        // 6. Plan actuel (pour que Claude puisse le mettre à jour, même dans une nouvelle conversation)
        if includePlan, let plan, let data = try? Coding.compactEncoder.encode(plan),
           let json = String(data: data, encoding: .utf8) {
            out.append("## Plan actuel (JSON)")
            out.append("```json")
            out.append(json)
            out.append("```")
            out.append("")
        }

        if footer {
            out.append("_Généré localement par l'app Coach. Colle ce suivi dans ta conversation avec Claude pour obtenir le plan mis à jour._")
        }
        return out.joined(separator: "\n")
    }

    // MARK: Formatage

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func int(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))"
    }

    static func num(_ v: Double?, _ unit: String, digits: Int = 0) -> String {
        guard let v else { return "—" }
        return String(format: "%.\(digits)f %@", v, unit)
    }

    static func setLabel(_ s: SetLog) -> String {
        if let d = s.durationSec { return "\(d) s" }
        var label = "\(s.reps ?? 0)"
        if let w = s.weightKg, w > 0 { label += "×\(w.clean) kg" }
        return label
    }
}
