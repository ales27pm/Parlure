//
//  ConversationView.swift
//  Parlure
//

import SwiftUI
import SwiftData
import Observation

enum AssistantMessageDeduper {
    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func shouldAppend(lastRole: ChatMessage.Role?, lastAssistantNormalized: String?, candidateText: String) -> Bool {
        let normalized = normalize(candidateText)
        guard !normalized.isEmpty else { return false }
        guard lastRole == .assistant else { return true }
        return normalized != lastAssistantNormalized
    }
}

struct ConversationView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DialogueTurn.timestamp, order: .reverse) private var allTurns: [DialogueTurn]
    @Query(sort: \GlossaryEntry.timestamp, order: .reverse) private var allGlossary: [GlossaryEntry]

    @AppStorage("autoTTS") private var autoTTS = true
    @AppStorage("confirmClarification") private var confirmClarification = true
    @AppStorage("silenceMs") private var silenceMs = 1200
    @AppStorage("maxSeconds") private var maxSeconds = 30

    @State private var speech = SpeechService()
    @State private var rag = GlossaryRAG()

    @State private var messages: [ChatMessage] = []
    @State private var mode: ConversationMode = .idle
    @State private var pending: PendingClarification?
    @State private var pendingExplanation: String = ""
    @State private var showConfirmSheet = false
    @State private var statusText: String = "Prêt à écouter"
    @State private var errorBanner: String?
    @State private var activeRecordingID: UUID?
    @State private var processedRecordingIDs: Set<UUID> = []
    @State private var lastAssistantResponseNormalized: String?
    @State private var isStartingRecording = false

    var body: some View {
        ZStack {
            Theme.paperBackground()

            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            if messages.isEmpty {
                                emptyState
                                    .padding(.top, 60)
                            }
                            ForEach(messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                            Color.clear.frame(height: 180).id("conversation-bottom-spacer")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            proxy.scrollTo("conversation-bottom-spacer", anchor: .bottom)
                        }
                    }
                }

                if let live = liveTranscriptText, !live.isEmpty {
                    LiveTranscriptStrip(text: live)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }

                controls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
        .onAppear { rag.reload(allGlossary) }
        .onChange(of: allGlossary) { _, new in rag.reload(new) }
        .sheet(isPresented: $showConfirmSheet) {
            ConfirmClarificationSheet(
                utterance: pending?.utterance ?? "",
                explanation: pendingExplanation,
                onConfirm: { saveClarification() },
                onCancel: { showConfirmSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Erreur", isPresented: Binding(get: { errorBanner != nil }, set: { if !$0 { errorBanner = nil } })) {
            Button("OK") { errorBanner = nil }
        } message: {
            Text(errorBanner ?? "")
        }
    }

    // MARK: - Header

    private var recognitionBadge: String { "\(speech.recognizerLocale) • \(speech.usesOnDeviceRecognition ? "sur appareil" : "assisté")" }

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parlure")
                        .font(.serif(34, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("journal vocal québécois")
                        .font(.serif(13))
                        .italic()
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(mode: mode, text: statusText)
                    Text(recognitionBadge).font(.serif(11)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            Rectangle()
                .fill(Theme.divider.opacity(0.6))
                .frame(height: 1)
                .padding(.top, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.mapleRed.opacity(0.08))
                    .frame(width: 120, height: 120)
                Image(systemName: "quote.opening")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(Theme.mapleRed)
            }
            VStack(spacing: 8) {
                Text("Raconte-moi quelque chose")
                    .font(.serif(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Appuie sur le micro et parle en français.\nJe note les expressions, et je demande quand je ne comprends pas.")
                    .font(.serif(15))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Controls

    private var liveTranscriptText: String? {
        guard mode == .recording || mode == .clarificationRecording else { return nil }
        return speech.transcript.isEmpty ? "…" : speech.transcript
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if mode == .clarifying {
                clarifyControls
            } else {
                mainMicControl
            }
        }
        .padding(.bottom, 4)
    }

    private var mainMicControl: some View {
        VStack(spacing: 10) {
            MicButton(
                isRecording: mode == .recording,
                isProcessing: mode == .processing,
                level: CGFloat(speech.audioLevel)
            ) {
                Task { await toggleRecording() }
            }
            Text(mode == .recording ? "Touche pour arrêter" : "Touche pour parler")
                .font(.serif(13))
                .italic()
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var clarifyControls: some View {
        VStack(spacing: 12) {
            Text("Explique-moi cette expression")
                .font(.serif(15))
                .italic()
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 12) {
                Button {
                    cancelClarification()
                } label: {
                    Label("Annuler", systemImage: "xmark")
                        .font(.serif(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(Theme.ink)
                        .background(Theme.cream)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
                        .clipShape(.rect(cornerRadius: 14))
                }
                Button {
                    Task { await toggleClarificationRecording() }
                } label: {
                    Label(mode == .clarificationRecording ? "Arrêter" : "Expliquer", systemImage: "mic.fill")
                        .font(.serif(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Theme.mapleRed)
                        .clipShape(.rect(cornerRadius: 14))
                }
                .disabled(isStartingRecording)
            }
        }
    }

    // MARK: - Recording flow

    private func toggleRecording() async {
        if mode == .recording {
            let text = speech.stopAndReturnTranscript()
            if let id = activeRecordingID { await processUserUtterance(text: text, recordingID: id) }
            return
        }
        guard mode == .idle else { return }
        do {
            TTSService.shared.stop()
            let recordingID = UUID()
            activeRecordingID = recordingID
            mode = .recording
            statusText = "À l'écoute…"
            try await speech.start(silenceThresholdMs: silenceMs, maxSeconds: maxSeconds) { text in
                Task { await processUserUtterance(text: text, recordingID: recordingID) }
            }
        } catch {
            mode = .idle
            statusText = "Prêt"
            errorBanner = error.localizedDescription
        }
    }

    private func processUserUtterance(text: String, recordingID: UUID) async {
        guard !processedRecordingIDs.contains(recordingID) else { return }
        processedRecordingIDs.insert(recordingID)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            mode = .idle
            statusText = "Rien capté — réessaie"
            return
        }
        mode = .processing
        statusText = "Je réfléchis…"

        let userMsg = ChatMessage(role: .user, content: text)
        withAnimation { messages.append(userMsg) }
        lastAssistantResponseNormalized = nil

        let match = rag.bestMatch(for: text)
        let glossaryContext = match.flatMap { m in
            rag.shouldUseGlossary(match: m, query: text)
            ? GlossaryContext(displayTerm: rag.displayTerm(for: m.entry), utterance: m.entry.utterance, explanation: m.entry.explanation, score: m.score)
            : nil
        }
        let decision = await LLMService.shared.decide(history: messages, userText: text, glossaryContext: glossaryContext)
        let responseText = decision.response

        if decision.action == .askClarify {
            pending = PendingClarification(utterance: text, terms: PendingClarification.resolvedTerms(utterance: text, detectedTerms: decision.unclearTerms), recordingID: recordingID)
            mode = .clarifying
            statusText = "Aide-moi à comprendre"
            appendAssistantMessageIfNeeded(responseText)
            if autoTTS { TTSService.shared.speak(responseText) }
        } else {
            appendAssistantMessageIfNeeded(responseText)
            if autoTTS { TTSService.shared.speak(responseText) }
            // Persist dialogue turn
            let turn = DialogueTurn(input: text, output: responseText, recognizerLocale: speech.recognizerLocale, outputSource: decision.source == .foundationModels ? .foundationModels : decision.source == .glossary ? .glossary : .heuristic, glossaryHintUsed: glossaryContext != nil, containsPersonalData: PIIRedactor.containsPII(text: text + " " + responseText))
            modelContext.insert(turn)
            do { try modelContext.save() } catch { errorBanner = error.localizedDescription }
            mode = .idle
            statusText = "Continue quand tu veux"
        }
    }

    // MARK: - Clarification recording

    private func toggleClarificationRecording() async {
        if mode == .clarificationRecording {
            let text = speech.stopAndReturnTranscript()
            if let id = activeRecordingID { await processClarification(text: text, recordingID: id) }
            return
        }
        guard mode == .clarifying else { return }
        do {
            TTSService.shared.stop()
            isStartingRecording = true
            try? await Task.sleep(nanoseconds: 200_000_000)
            let recordingID = UUID()
            activeRecordingID = recordingID
            mode = .clarificationRecording
            statusText = "À l'écoute…"
            try await speech.start(silenceThresholdMs: silenceMs, maxSeconds: maxSeconds) { text in
                Task { await processClarification(text: text, recordingID: recordingID) }
            }
            isStartingRecording = false
        } catch {
            isStartingRecording = false
            mode = .clarifying
            statusText = "Aide-moi à comprendre"
            errorBanner = "Le micro n’a pas pu démarrer. Réessaie dans une seconde."
        }
    }

    private func processClarification(text: String, recordingID: UUID) async {
        guard !processedRecordingIDs.contains(recordingID) else { return }
        processedRecordingIDs.insert(recordingID)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, pending != nil else {
            mode = .clarifying
            return
        }
        pendingExplanation = text
        if confirmClarification {
            showConfirmSheet = true
            mode = .clarifying
        } else {
            saveClarification()
        }
    }

    private func saveClarification() {
        guard let p = pending, !pendingExplanation.isEmpty else {
            showConfirmSheet = false
            return
        }
        let validation = ClarificationValidator.validate(utterance: p.utterance, explanation: pendingExplanation)
        let quality = GlossaryQualityValidator.validate(utterance: p.utterance, explanation: pendingExplanation, unclearTerms: p.terms, detectedTerms: p.terms)
        guard validation.isValid, quality.isValid else {
            let retry = "Je pense que j’ai mal associé l’expression. Peux-tu me redire juste l’expression, puis me l’expliquer clairement?"
            appendAssistantMessageIfNeeded(retry)
            if autoTTS { TTSService.shared.speak(retry) }
            showConfirmSheet = false
            pendingExplanation = ""
            mode = .clarifying
            statusText = "Aide-moi à comprendre"
            return
        }
        let entry = GlossaryEntry(
            utterance: quality.cleanedUtterance,
            unclearTerms: quality.cleanedTerms,
            explanation: quality.cleanedExplanation
        )
        modelContext.insert(entry)
        do { try modelContext.save() } catch { errorBanner = error.localizedDescription }

        let thanks = "Merci ! Là je comprends mieux ce que tu veux dire par « \(quality.cleanedUtterance) » : \(quality.cleanedExplanation)"
        appendAssistantMessageIfNeeded(thanks)
        if autoTTS { TTSService.shared.speak(thanks) }

        // Also persist as a dialogue turn for export
        let turn = DialogueTurn(input: quality.cleanedUtterance, output: quality.cleanedExplanation, recognizerLocale: speech.recognizerLocale, outputSource: .manual, reviewStatus: .pendingReview, containsPersonalData: PIIRedactor.containsPII(text: quality.cleanedUtterance + " " + quality.cleanedExplanation))
        modelContext.insert(turn)
        do { try modelContext.save() } catch { errorBanner = error.localizedDescription }

        resetPendingClarification()
        showConfirmSheet = false
        mode = .idle
        statusText = "Bien noté"
    }

    private func cancelClarification() {
        resetPendingClarification()
        mode = .idle
        statusText = "Prêt"
    }


    private func resetPendingClarification() {
        pending = nil
        pendingExplanation = ""
        activeRecordingID = nil
    }

    private func appendAssistantMessageIfNeeded(_ text: String) {
        let normalized = AssistantMessageDeduper.normalize(text)
        guard AssistantMessageDeduper.shouldAppend(lastRole: messages.last?.role, lastAssistantNormalized: lastAssistantResponseNormalized, candidateText: text) else { return }
        withAnimation { messages.append(ChatMessage(role: .assistant, content: text)) }
        lastAssistantResponseNormalized = normalized
    }
}

// MARK: - Subviews

private struct StatusPill: View {
    let mode: ConversationMode
    let text: String

    private var color: Color {
        switch mode {
        case .recording, .clarificationRecording: return Theme.mapleRed
        case .processing: return Theme.moss
        case .clarifying: return Theme.inkSoft
        case .idle: return Theme.divider
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .opacity(mode == .recording || mode == .clarificationRecording || mode == .processing ? 1 : 0.6)
                .scaleEffect(mode == .recording || mode == .clarificationRecording ? 1.12 : 1)
                .animation(mode == .recording || mode == .clarificationRecording ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: mode)
            Text(text)
                .font(.serif(12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 170, alignment: .leading)
        .background(Theme.cream.opacity(0.8))
        .overlay(Capsule().stroke(Theme.divider.opacity(0.5), lineWidth: 1))
        .clipShape(Capsule())
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 36) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.role == .user ? "Toi" : "Parlure")
                    .font(.serif(11, weight: .semibold))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(message.role == .user ? Theme.mapleRed : Theme.inkSoft)

                Text(message.content)
                    .font(.serif(16))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(Theme.mapleRed.opacity(0.08))
                            : AnyShapeStyle(Theme.cream)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                message.role == .user ? Theme.mapleRed.opacity(0.25) : Theme.divider.opacity(0.6),
                                lineWidth: 1
                            )
                    )
                    .clipShape(.rect(cornerRadius: 14))
            }

            if message.role == .assistant { Spacer(minLength: 36) }
        }
    }
}

private struct LiveTranscriptStrip: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 14))
                .foregroundStyle(Theme.mapleRed)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text(text)
                .font(.serif(15))
                .italic()
                .foregroundStyle(Theme.ink.opacity(0.85))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cream.opacity(0.85))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider.opacity(0.5), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct MicButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let level: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ripple rings while recording
                if isRecording {
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(Theme.mapleRed.opacity(0.35 - Double(i) * 0.1), lineWidth: 2)
                            .scaleEffect(1 + level * 1.2 + CGFloat(i) * 0.08)
                            .frame(width: 90, height: 90)
                            .animation(.easeOut(duration: 0.2), value: level)
                    }
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.mapleRed, Theme.mapleRedDeep],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 110
                        )
                    )
                    .frame(width: 92, height: 92)
                    .shadow(color: Theme.mapleRedDeep.opacity(0.35), radius: 14, y: 8)
                    .scaleEffect(isRecording ? 1.05 + level * 0.1 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)

                if isProcessing {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 130, height: 130)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
        .disabled(isProcessing)
    }
}

private struct ConfirmClarificationSheet: View {
    let utterance: String
    let explanation: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.mapleRed)
                    Text("Ajouter au glossaire ?")
                        .font(.serif(22, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 14) {
                    LabeledQuote(label: "Expression", text: utterance, accent: Theme.mapleRed)
                    LabeledQuote(label: "Ton explication", text: explanation, accent: Theme.moss)
                }
                .padding(.horizontal, 20)

                VStack(spacing: 10) {
                    Button(action: onConfirm) {
                        Text("Ajouter au glossaire")
                            .font(.serif(16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.mapleRed)
                            .clipShape(.rect(cornerRadius: 14))
                    }
                    Button(action: onCancel) {
                        Text("Annuler")
                            .font(.serif(15, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }
}

private struct LabeledQuote: View {
    let label: String
    let text: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.serif(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.inkSoft)
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
                Text(text)
                    .font(.serif(17))
                    .italic()
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
    }
}
