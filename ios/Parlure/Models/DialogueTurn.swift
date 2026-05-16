//
//  DialogueTurn.swift
//  Parlure
//

import Foundation
import SwiftData

@Model
final class DialogueTurn {
    var timestamp: Date
    var input: String
    var output: String
    var audioFilename: String?

    init(timestamp: Date = Date(), input: String, output: String, audioFilename: String? = nil) {
        self.timestamp = timestamp
        self.input = input
        self.output = output
        self.audioFilename = audioFilename
    }
}
