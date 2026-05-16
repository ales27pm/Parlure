//
//  GeneratedDecision.swift
//  Parlure
//
//  @Generable type used by the Foundation Models LLMService.
//  Must be declared at file scope (not nested) for the macro to apply.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct GeneratedDecision {
    @Guide(description: "Set to 'askClarify' if the phrase contains an unfamiliar Québécois idiom that you cannot confidently explain. Otherwise 'answer'.")
    var action: String

    @Guide(description: "A short reply (1–2 sentences) in Québécois French. If asking for clarification, phrase it as a friendly question.")
    var response: String

    @Guide(description: "List of specific words or short phrases you find unclear. Empty if everything is clear.", .maximumCount(4))
    var unclearTerms: [String]
}
#endif
