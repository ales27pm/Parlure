import SwiftUI
import SwiftData

struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DialogueTurn.timestamp, order: .reverse) private var turns: [DialogueTurn]
    @Query(sort: \GlossaryEntry.timestamp, order: .reverse) private var glossary: [GlossaryEntry]

    @AppStorage("allowTrainingExport") private var allowTrainingExport = false
    @AppStorage("containsPersonalData") private var containsPersonalData = true
    @AppStorage("requireReviewBeforeExport") private var requireReviewBeforeExport = true
    @AppStorage("exportRedactedText") private var exportRedactedText = true

    @State private var shareItems: [URL] = []
    @State private var showShare = false
    @State private var exportError: String?
    @State private var showClearAlert = false
    @State private var showExportConfirm = false

    private var exportSummary: (accepted: Int, pending: Int, rejected: Int, redacted: Int, pii: Int, consented: Int, qfrExpected: Int) {
        let allStatuses = turns.map(\.reviewStatus) + glossary.map(\.reviewStatus)
        let accepted = allStatuses.filter { $0 == .accepted }.count
        let pending = allStatuses.filter { $0 == .pendingReview }.count
        let rejected = allStatuses.filter { $0 == .rejected }.count
        let redacted = allStatuses.filter { $0 == .redacted }.count
        let pii = turns.filter(\.containsPersonalData).count + glossary.filter(\.containsPersonalData).count
        let consented = allowTrainingExport
            ? turns.filter { $0.consentForTraining && $0.reviewStatus == .accepted }.count
                + glossary.filter { $0.consentForTraining && $0.reviewStatus == .accepted }.count
            : 0
        let qfrExpected = turns.filter { $0.reviewStatus != .rejected }.count + glossary.filter { $0.reviewStatus != .rejected }.count
        return (accepted, pending, rejected, redacted, pii, consented, qfrExpected)
    }

    var body: some View {
        ZStack {
            Theme.paperBackground()
            ScrollView {
                VStack(spacing: 16) {
                    Text("Archive").font(.serif(34, weight: .bold)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                    summaryCard
                    ForEach(turns) { turn in DialogueReviewRow(turn: turn, onSave: saveContext) }
                    ForEach(glossary) { entry in GlossaryReviewRow(entry: entry, onSave: saveContext) }
                    actions
                }.padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .confirmationDialog("Confirmer l'export local", isPresented: $showExportConfirm) {
            Button("Exporter maintenant") { exportNow() }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Données possiblement personnelles. Révision/rédaction recommandée avant entraînement.") }
        .alert("Erreur", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) { Button("OK") { exportError = nil } } message: { Text(exportError ?? "") }
        .alert("Effacer l'archive ?", isPresented: $showClearAlert) {
            Button("Effacer", role: .destructive) { clearAll() }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Cela supprimera tous les dialogues et le glossaire.") }
    }

    private var summaryCard: some View {
        let s = exportSummary
        return VStack(alignment: .leading, spacing: 6) {
            Text("Résumé export").font(.serif(16, weight: .bold))
            Text("Dialogues: \(turns.count) • Glossaire: \(glossary.count)")
            Text("Acceptés: \(s.accepted) • En attente: \(s.pending) • Rejetés: \(s.rejected) • Caviardés: \(s.redacted)")
            Text("PII détecté: \(s.pii) • Consentis: \(s.consented) • QFR attendu: \(s.qfrExpected)")
        }
        .font(.serif(13)).foregroundStyle(Theme.inkSoft)
        .padding(14).background(Theme.cream).clipShape(.rect(cornerRadius: 12)).padding(.horizontal, 20)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button("Exporter pour entraînement") { showExportConfirm = true }
                .font(.serif(16, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14).background(Theme.mapleRed).clipShape(.rect(cornerRadius: 12))
            Button("Tout effacer", role: .destructive) { showClearAlert = true }
                .font(.serif(14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
        }.padding(.horizontal, 20)
    }

    private func saveContext() {
        do { try modelContext.save() } catch { exportError = error.localizedDescription }
    }

    private func exportNow() {
        do {
            let result = try ExportService.shared.export(turns: turns, glossary: glossary, options: .init(allowTrainingExport: allowTrainingExport, markContainsPersonalData: containsPersonalData, requireReviewBeforeExport: requireReviewBeforeExport, exportRedactedText: exportRedactedText))
            shareItems = result.files
            showShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func clearAll() {
        turns.forEach(modelContext.delete)
        glossary.forEach(modelContext.delete)
        saveContext()
    }
}

private struct DialogueReviewRow: View {
    @Bindable var turn: DialogueTurn
    let onSave: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.input).font(.serif(14)).lineLimit(2)
            Text(turn.output).font(.serif(13)).italic().foregroundStyle(Theme.inkSoft).lineLimit(2)
            Picker("Statut", selection: $turn.reviewStatusRaw) {
                ForEach(ReviewStatus.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
            }.pickerStyle(.menu)
            Toggle("Consentement entraînement", isOn: $turn.consentForTraining).onChange(of: turn.consentForTraining) { _, _ in onSave() }
            Text(turn.containsPersonalData ? "PII: oui" : "PII: non").font(.serif(12)).foregroundStyle(.secondary)
        }.padding(12).background(Theme.cream).clipShape(.rect(cornerRadius: 10)).padding(.horizontal, 20)
        .onChange(of: turn.reviewStatusRaw) { _, _ in onSave() }
    }
}

private struct GlossaryReviewRow: View {
    @Bindable var entry: GlossaryEntry
    let onSave: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("« \(entry.utterance) »").font(.serif(14, weight: .semibold)).lineLimit(2)
            Text(entry.explanation).font(.serif(13)).italic().foregroundStyle(Theme.inkSoft).lineLimit(2)
            Picker("Statut", selection: $entry.reviewStatusRaw) {
                ForEach(ReviewStatus.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
            }.pickerStyle(.menu)
            Toggle("Consentement entraînement", isOn: $entry.consentForTraining).onChange(of: entry.consentForTraining) { _, _ in onSave() }
            Text(entry.containsPersonalData ? "PII: oui" : "PII: non").font(.serif(12)).foregroundStyle(.secondary)
        }.padding(12).background(Theme.cream).clipShape(.rect(cornerRadius: 10)).padding(.horizontal, 20)
        .onChange(of: entry.reviewStatusRaw) { _, _ in onSave() }
    }
}

@MainActor
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
