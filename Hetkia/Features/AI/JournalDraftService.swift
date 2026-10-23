import Foundation
import FoundationModels
import CoreGraphics

struct JournalDraftResult {
    let body: String
    let usedImageUnderstanding: Bool
}

enum JournalDraftError: LocalizedError {
    case unavailable(String)
    case imageInputUnavailable
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .imageInputUnavailable: "This system can generate text from metadata, but can’t analyze photos visually."
        case .emptyResponse: "The on-device model returned an empty journal draft."
        }
    }
}

enum JournalDraftService {
    static var availabilityDescription: String {
        guard #available(iOS 26, macOS 26, *) else {
            return NSLocalizedString("photos.ai.os-unsupported", comment: "")
        }
        return switch SystemLanguageModel.default.availability {
        case .available: NSLocalizedString("photos.ai.available", comment: "")
        case .unavailable(.deviceNotEligible): NSLocalizedString("photos.ai.device-unsupported", comment: "")
        case .unavailable(.appleIntelligenceNotEnabled): NSLocalizedString("photos.ai.disabled", comment: "")
        case .unavailable(.modelNotReady): NSLocalizedString("photos.ai.model-preparing", comment: "")
        case .unavailable: NSLocalizedString("photos.ai.unavailable", comment: "")
        }
    }

    @available(iOS 26, macOS 26, *)
    static func generate(date: Date, photoCount: Int, imageSamples: [CGImage], locationContext: [String] = []) async throws -> JournalDraftResult {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw JournalDraftError.unavailable(availabilityDescription)
        }

        let dateText = date.formatted(date: .complete, time: .omitted)
        let outputLanguage = HetkiaSystemLanguage.displayName
        let session = LanguageModelSession(instructions: """
        You write private journal entries. Write naturally and concisely in \(outputLanguage), as a personal memory rather than a photo caption.
        Describe what is visible. Use supplied location metadata and visible clues to help recall where the user went, what they may have bought or eaten, and who may have been around, but include these details only when the evidence supports them. Refer to people generically; never guess names or relationships.
        Do not invent events, objects, meals, places, or emotions. Do not mention the time of day or any clock time. Do not repeat the date in the entry.
        Return only the journal body, without a title, explanation, or list.
        """)

        if #available(iOS 27, macOS 27, *), !imageSamples.isEmpty {
            let prompt = Prompt {
                "Write a short private journal entry for \(dateText), based on these photos and reliable information. The user selected \(photoCount) photos for this day."
                if !locationContext.isEmpty {
                    "Photo location metadata: \(locationContext.joined(separator: "; ")). Use it only when relevant and supported."
                }
                "Do not include a time in the journal text."
                for (index, image) in imageSamples.enumerated() {
                    "照片 \(index + 1)："
                    Attachment(image).label("photo-\(index + 1)")
                }
            }
            let response = try await session.respond(to: prompt)
            let body = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { throw JournalDraftError.emptyResponse }
            return JournalDraftResult(body: body, usedImageUnderstanding: true)
        }

        let textOnlyPrompt = """
        Write a short private journal entry for \(dateText). Reliable information: the user selected \(photoCount) photos for this day.
        Photo location metadata: \(locationContext.isEmpty ? "none" : locationContext.joined(separator: "; ")).
        You have not seen the photos. Do not describe their content or infer purchases, meals, people, relationships, or emotions. You may refer to the supplied location only when present. Do not include the time of day or any clock time, and do not repeat the date. Keep the entry brief.
        """
        let response = try await session.respond(to: textOnlyPrompt)
        let body = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw JournalDraftError.emptyResponse }
        return JournalDraftResult(body: body, usedImageUnderstanding: false)
    }
}
