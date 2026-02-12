import Foundation

enum ActivityLabel: String, CaseIterable, Codable, Identifiable {
    case diaperWet
    case diaperBowel
    case feeding
    case sleepStart
    case wakeUp
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .diaperWet: return "Diaper (Wet)"
        case .diaperBowel: return "Diaper (Bowel)"
        case .feeding: return "Feeding"
        case .sleepStart: return "Baby Asleep"
        case .wakeUp: return "Baby Wakes Up"
        case .other: return "Other"
        }
    }
}

enum CaptureType: String, Codable {
    case photo
    case shortVideo
    case audioSnippet
}

struct CaptureEnvelope: Sendable {
    let id: UUID
    let captureType: CaptureType
    let capturedAt: Date
    let deviceId: String?
    let localMediaURL: URL
    let metadata: [String: String]
}

struct InferenceResult: Sendable {
    let label: ActivityLabel
    let confidence: Double
    let rationaleShort: String
    let modelVersion: String
}
