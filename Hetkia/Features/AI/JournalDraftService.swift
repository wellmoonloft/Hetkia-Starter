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
    static let promptDefaultsKey = "hetkia.ai.journalPrompt"
    static let defaultPrompt = """
    You are my personal diary writer. Based on all the photos I took today, write a natural, warm, and authentic diary entry in the first person, using "I" to describe what may have happened during my day.
    Consider all the photos together, along with their timestamps, locations, and other available metadata, to reconstruct the day's experiences as a whole rather than describing each photo individually. Focus on activities, places, and life moments that are supported by clear evidence.
    Strictly adhere to the evidence provided by the photos and metadata. Do not invent relationships, conversations, itineraries, events, or emotions. Make cautious inferences only when there are clear supporting clues. If something is uncertain, express it cautiously; if it cannot be reasonably inferred, leave it out. Ordinary moments are perfectly fine. Do not exaggerate, romanticize, or force a deeper meaning.
    Write 2–5 sentences in a natural, warm, and conversational style. Always write the diary entry in the current system language, regardless of the language used in the photos, text within the images, place names, or other available information. Output only the diary entry itself, without a title or any mention of AI or your reasoning process.
    Do not include specific dates in the diary entry. Relative time expressions such as "today" or "yesterday" are fine.
    """

    static var currentPrompt: String {
        guard let savedPrompt = UserDefaults.standard.string(forKey: promptDefaultsKey),
              !savedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultPrompt
        }
        return savedPrompt
    }

    static func photoMetadata(index: Int, capturedAt: Date?, placeName: String?, latitude: Double?, longitude: Double?) -> String {
        let date = capturedAt?.formatted(date: .numeric, time: .shortened) ?? "unknown date"
        let place = placeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = place.flatMap { $0.isEmpty ? nil : $0 }
            ?? (latitude.flatMap { lat in longitude.map { String(format: "%.5f, %.5f", lat, $0) } } ?? "unknown location")
        return "Photo \(index): captured \(date); location: \(location)."
    }

    static var isAvailable: Bool {
        guard #available(iOS 26, macOS 26, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

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
    static func generate(date: Date, photoCount: Int, imageSamples: [CGImage], locationContext: [String] = [], photoMetadata: [String] = []) async throws -> JournalDraftResult {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw JournalDraftError.unavailable(availabilityDescription)
        }

        let dateText = date.formatted(date: .complete, time: .omitted)
        let outputLanguage = HetkiaSystemLanguage.displayName
        let session = LanguageModelSession(instructions: currentPrompt)

        if #available(iOS 27, macOS 27, *), !imageSamples.isEmpty {
            let prompt = Prompt {
                "Diary date: \(dateText). The user selected \(photoCount) photos for this day."
                "Current system language: \(outputLanguage)."
                "Consider the attached photos together as one day's experience."
                if !locationContext.isEmpty {
                    "Available location names: \(locationContext.joined(separator: "; "))."
                }
                if !photoMetadata.isEmpty {
                    "Per-photo metadata: \(photoMetadata.joined(separator: " "))"
                }
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
        Diary date: \(dateText). The user selected \(photoCount) photos for this day.
        Current system language: \(outputLanguage).
        Visual photo input is unavailable in this system version. Do not claim to see or describe photo contents; rely only on the metadata below and omit unsupported details.
        Available location names: \(locationContext.isEmpty ? "none" : locationContext.joined(separator: "; ")).
        Per-photo metadata: \(photoMetadata.isEmpty ? "unavailable" : photoMetadata.joined(separator: " "))
        """
        let response = try await session.respond(to: textOnlyPrompt)
        let body = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw JournalDraftError.emptyResponse }
        return JournalDraftResult(body: body, usedImageUnderstanding: false)
    }
}
