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
    static func generate(date: Date, photoCount: Int, imageSamples: [CGImage]) async throws -> JournalDraftResult {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw JournalDraftError.unavailable(availabilityDescription)
        }

        let dateText = date.formatted(date: .complete, time: .omitted)
        let outputLanguage = HetkiaSystemLanguage.displayName
        let session = LanguageModelSession(instructions: """
        You write private journal drafts. Write naturally and concisely in \(outputLanguage).
        State only what the photos or supplied metadata support. Never guess identities, relationships, exact locations, context, or the user's emotions.
        Do not mention a place or mood unless reliable information was provided. Do not invent details.
        Return only the journal body, without a title, explanation, or list.
        """)

        if #available(iOS 27, macOS 27, *), !imageSamples.isEmpty {
            let prompt = Prompt {
                "Write a short private journal entry for \(dateText) based on these photos and reliable information. The user selected \(photoCount) photos for this day."
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
        You have not seen the photos. Do not describe their content, locations, people, or emotions. Keep the entry brief and do not infer details.
        """
        let response = try await session.respond(to: textOnlyPrompt)
        let body = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw JournalDraftError.emptyResponse }
        return JournalDraftResult(body: body, usedImageUnderstanding: false)
    }
}
