//
//  SettingsView.swift
//  Parlure
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("autoTTS") private var autoTTS = true
    @AppStorage("confirmClarification") private var confirmClarification = true
    @AppStorage("silenceMs") private var silenceMs = 1200
    @AppStorage("maxSeconds") private var maxSeconds = 30

    var body: some View {
        ZStack {
            Theme.paperBackground()
            ScrollView {
                VStack(spacing: 22) {
                    header

                    section(title: "Général") {
                        ToggleRow(
                            icon: "checkmark.seal.fill",
                            title: "Confirmer avant glossaire",
                            subtitle: "Demande avant d'ajouter une expression",
                            isOn: $confirmClarification
                        )
                        Divider().background(Theme.divider.opacity(0.5))
                        ToggleRow(
                            icon: "speaker.wave.2.fill",
                            title: "Lecture automatique",
                            subtitle: "Lit les réponses à voix haute",
                            isOn: $autoTTS
                        )
                    }

                    section(title: "Enregistrement") {
                        ChoiceRow(
                            icon: "timer",
                            title: "Seuil de silence",
                            subtitle: "Arrête après \(silenceMs) ms de silence",
                            options: [800, 1200, 1600, 2000],
                            selection: $silenceMs,
                            label: { "\($0) ms" }
                        )
                        Divider().background(Theme.divider.opacity(0.5))
                        ChoiceRow(
                            icon: "hourglass",
                            title: "Durée max",
                            subtitle: "Limite chaque enregistrement à \(maxSeconds) s",
                            options: [15, 30, 60, 120],
                            selection: $maxSeconds,
                            label: { "\($0) s" }
                        )
                    }

                    aboutCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Réglages")
                        .font(.serif(34, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("ajuste l'expérience")
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

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.serif(11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.mapleRed)
                .padding(.horizontal, 20)
            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .background(Theme.cream)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.divider.opacity(0.5), lineWidth: 1))
            .clipShape(.rect(cornerRadius: 16))
            .padding(.horizontal, 20)
        }
    }

    private var aboutCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "fleuron")
                .font(.system(size: 22))
                .foregroundStyle(Theme.mapleRed.opacity(0.7))
            Text("Parlure")
                .font(.serif(18, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Reconnaissance vocale sur appareil.\nTes mots restent à toi.")
                .font(.serif(13))
                .italic()
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Theme.mapleRed)
                .frame(width: 26)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.serif(16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.serif(13)).italic().foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.mapleRed)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ChoiceRow<T: Hashable>: View {
    let icon: String
    let title: String
    let subtitle: String
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.mapleRed)
                    .frame(width: 26)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.serif(16, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.serif(13)).italic().foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { opt in
                    Button {
                        selection = opt
                    } label: {
                        Text(label(opt))
                            .font(.serif(13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selection == opt ? .white : Theme.ink)
                            .background(selection == opt ? Theme.mapleRed : Theme.parchment)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.divider.opacity(0.5), lineWidth: 1))
                            .clipShape(.rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
