//
//  ArchiveView.swift
//  Parlure
//
//  Stats, glossary review, and export.
//

import SwiftUI
import SwiftData

struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DialogueTurn.timestamp, order: .reverse) private var turns: [DialogueTurn]
    @Query(sort: \GlossaryEntry.timestamp, order: .reverse) private var glossary: [GlossaryEntry]

    @State private var shareItems: [URL] = []
    @State private var showShare = false
    @State private var exportError: String?
    @State private var showClearAlert = false

    var body: some View {
        ZStack {
            Theme.paperBackground()
            ScrollView {
                VStack(spacing: 22) {
                    header

                    HStack(spacing: 12) {
                        StatCard(label: "Tours", value: turns.count, icon: "bubble.left.and.bubble.right.fill", accent: Theme.mapleRed)
                        StatCard(label: "Glossaire", value: glossary.count, icon: "book.fill", accent: Theme.moss)
                    }
                    .padding(.horizontal, 20)

                    if !glossary.isEmpty {
                        glossarySection
                    }

                    if !turns.isEmpty {
                        recentDialoguesSection
                    }

                    actions
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .alert("Effacer l'archive ?", isPresented: $showClearAlert) {
            Button("Effacer", role: .destructive) { clearAll() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cela supprimera tous les dialogues et le glossaire de l'appareil.")
        }
        .alert("Erreur d'export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Archive")
                        .font(.serif(34, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("ce que tu as construit")
                        .font(.serif(13))
                        .italic()
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            Rectangle().fill(Theme.divider.opacity(0.6)).frame(height: 1).padding(.top, 12)
        }
    }

    private var glossarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Glossaire", subtitle: "expressions apprises")
            VStack(spacing: 10) {
                ForEach(glossary.prefix(8)) { entry in
                    GlossaryRow(entry: entry)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var recentDialoguesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Dialogues", subtitle: "tours récents")
            VStack(spacing: 10) {
                ForEach(turns.prefix(6)) { turn in
                    DialogueRow(turn: turn)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: exportNow) {
                HStack {
                    Image(systemName: "square.and.arrow.up.fill")
                    Text("Exporter pour entraînement")
                }
                .font(.serif(16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.mapleRed)
                .clipShape(.rect(cornerRadius: 14))
            }
            .disabled(turns.isEmpty && glossary.isEmpty)
            .opacity(turns.isEmpty && glossary.isEmpty ? 0.4 : 1)

            Button {
                showClearAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Tout effacer")
                }
                .font(.serif(15, weight: .medium))
                .foregroundStyle(Theme.mapleRedDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.mapleRed.opacity(0.08))
                .clipShape(.rect(cornerRadius: 12))
            }
            .disabled(turns.isEmpty && glossary.isEmpty)
            .opacity(turns.isEmpty && glossary.isEmpty ? 0.4 : 1)
        }
    }

    private func exportNow() {
        do {
            let result = try ExportService.shared.export(turns: turns, glossary: glossary)
            shareItems = result.files
            showShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func clearAll() {
        for t in turns { modelContext.delete(t) }
        for g in glossary { modelContext.delete(g) }
        try? modelContext.save()
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.serif(12, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.mapleRed)
            Text(subtitle)
                .font(.serif(13))
                .italic()
                .foregroundStyle(Theme.inkSoft)
        }
    }
}

private struct StatCard: View {
    let label: String
    let value: Int
    let icon: String
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(accent)
                Spacer()
            }
            Text("\(value)")
                .font(.serif(40, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(label.uppercased())
                .font(.serif(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.cream)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.divider.opacity(0.5), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 16))
    }
}

private struct GlossaryRow: View {
    let entry: GlossaryEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("« \(entry.utterance) »")
                .font(.serif(16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(entry.explanation)
                .font(.serif(14))
                .italic()
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cream)
        .overlay(
            HStack {
                Rectangle().fill(Theme.mapleRed).frame(width: 3)
                Spacer()
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider.opacity(0.5), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct DialogueRow: View {
    let turn: DialogueTurn
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.input)
                .font(.serif(15))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(turn.output)
                .font(.serif(13))
                .italic()
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cream.opacity(0.7))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.divider.opacity(0.4), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 10))
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    nonisolated func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    nonisolated func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
