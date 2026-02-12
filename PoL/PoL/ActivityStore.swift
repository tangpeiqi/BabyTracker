import Foundation
import SwiftData

protocol ActivityStore {
    func saveEvent(from capture: CaptureEnvelope, inference: InferenceResult) throws
}

@MainActor
final class SwiftDataActivityStore: ActivityStore {
    private let modelContext: ModelContext
    private let confidenceThreshold: Double

    init(modelContext: ModelContext, confidenceThreshold: Double = 0.75) {
        self.modelContext = modelContext
        self.confidenceThreshold = confidenceThreshold
    }

    func saveEvent(from capture: CaptureEnvelope, inference: InferenceResult) throws {
        let event = ActivityEventRecord(
            label: inference.label,
            timestamp: capture.capturedAt,
            sourceCaptureId: capture.id,
            confidence: inference.confidence,
            needsReview: inference.confidence < confidenceThreshold,
            rationaleShort: inference.rationaleShort,
            modelVersion: inference.modelVersion
        )
        modelContext.insert(event)
        try modelContext.save()
    }
}
