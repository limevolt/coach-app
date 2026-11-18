// TimersView.swift — minuteurs libres : tu définis toi-même travail / repos

import SwiftUI

struct TimersView: View {
    @Environment(PlanStore.self) private var store
    @State private var editing: IntervalTemplate?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.templates) { template in
                        HStack(spacing: 8) {
                            Button {
                                editing = template
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                                    Text("\(IntervalTemplate.activityLabel(template.activity)) · \(template.summary)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.borderless)
                            // Démarrer sur la montre (#5) : le minuteur s'ouvre prêt sur la montre.
                            StartOnWatchIconButton(name: template.name) { await store.startOnWatch(template) }
                        }
                    }
                    .onDelete { store.deleteTemplates(at: $0) }
                    .onMove { store.moveTemplates(from: $0, to: $1) }
                } footer: {
                    Text("▶︎ lance le minuteur sur ta montre. Tes favoris sont aussi dans Coach › Libre sur la montre.")
                }
            }
            .themedForm()
            .navigationTitle("Libre")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = IntervalTemplate(name: "", activity: "hiit", repeats: 5, segments: [
                            TimerSegment(kind: "work", seconds: 60),
                            TimerSegment(kind: "rest", seconds: 30)
                        ])
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { template in
                TimerEditorView(template: template)
            }
        }
    }
}

struct TimerEditorView: View {
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var template: IntervalTemplate

    // Motif rapide
    @State private var quickWork = 300
    @State private var quickRest = 120
    @State private var quickRepeats = 5

    init(template: IntervalTemplate) {
        _template = State(initialValue: template)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom (ex. Pyramide 2-3-4)", text: $template.name)
                    Picker("Activité", selection: $template.activity) {
                        ForEach(IntervalTemplate.activities, id: \.id) { a in
                            Text(a.label).tag(a.id)
                        }
                    }
                } footer: {
                    Text("L'activité détermine comment la séance est enregistrée dans Santé (calories, anneau Bouger).")
                }

                Section {
                    DurationPicker(title: "Travail", seconds: $quickWork)
                    DurationPicker(title: "Repos", seconds: $quickRest)
                    Stepper("Répéter \(quickRepeats) fois", value: $quickRepeats, in: 1...50)
                    Button("Appliquer ce motif") {
                        template.segments = [
                            TimerSegment(kind: "work", seconds: quickWork),
                            TimerSegment(kind: "rest", seconds: quickRest)
                        ]
                        template.repeats = quickRepeats
                        if template.name.isEmpty {
                            template.name = "\(quickRepeats) × \(Durations.label(quickWork)) / \(Durations.label(quickRest))"
                        }
                    }
                } header: {
                    Text("Motif rapide")
                } footer: {
                    Text("Ex. 5 × (5 min de travail / 2 min de repos). Remplace la séquence ci-dessous.")
                }

                Section {
                    ForEach($template.segments) { $segment in
                        SegmentEditor(segment: $segment)
                    }
                    .onDelete { template.segments.remove(atOffsets: $0) }
                    .onMove { template.segments.move(fromOffsets: $0, toOffset: $1) }

                    HStack {
                        Button("+ Travail") {
                            template.segments.append(TimerSegment(kind: "work", seconds: 60))
                        }
                        Spacer()
                        Button("+ Repos") {
                            template.segments.append(TimerSegment(kind: "rest", seconds: 60))
                        }
                    }
                    .buttonStyle(.borderless)

                    Stepper("Répéter la séquence \(template.repeats) fois", value: $template.repeats, in: 1...50)
                } header: {
                    Text("Séquence personnalisée")
                } footer: {
                    Text("Ex. pyramide : 2 min / 2 min repos, 3 min / 3 min repos, 4 min / 4 min repos. Glisse pour réordonner ou supprimer.")
                }

                Section {
                    LabeledContent("Durée totale", value: Durations.label(template.totalSeconds))
                    LabeledContent("Efforts", value: "\(template.segments.filter { $0.kind == "work" }.count * template.repeats)")
                }
            }
            .themedForm()
            .navigationTitle(template.name.isEmpty ? "Nouveau minuteur" : template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if template.name.isEmpty { template.name = "Mon minuteur" }
                        store.saveTemplate(template)
                        dismiss()
                    }
                    .disabled(template.segments.isEmpty || template.totalSeconds == 0)
                }
            }
        }
    }
}

private struct SegmentEditor: View {
    @Binding var segment: TimerSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Type", selection: $segment.kind) {
                Text("Travail").tag("work")
                Text("Repos").tag("rest")
            }
            .pickerStyle(.segmented)
            TextField(segment.kind == "work" ? "Libellé (ex. Squat, Côte…)" : "Libellé (facultatif)",
                      text: Binding(get: { segment.label ?? "" },
                                    set: { segment.label = $0.isEmpty ? nil : $0 }))
                .font(.callout)
            DurationPicker(title: "Durée", seconds: $segment.seconds)
        }
        .padding(.vertical, 4)
        .listRowBackground(segment.kind == "work" ? Color.green.opacity(0.08) : Color.blue.opacity(0.08))
    }
}

/// Choix minutes + secondes (pas de 5 s).
struct DurationPicker: View {
    let title: String
    @Binding var seconds: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker("min", selection: Binding(get: { seconds / 60 },
                                             set: { seconds = $0 * 60 + seconds % 60 })) {
                ForEach(0...90, id: \.self) { Text("\($0) min").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Picker("s", selection: Binding(get: { (seconds % 60) / 5 * 5 },
                                           set: { seconds = (seconds / 60) * 60 + $0 })) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text("\($0) s").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}
