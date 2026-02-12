import Foundation
import SwiftData

@Model
final class ActivityEventRecord {
    var id: UUID
    var labelRawValue: String
    var timestamp: Date
    var sourceCaptureId: UUID
    var confidence: Double
    var needsReview: Bool
    var isUserCorrected: Bool
    var isDeleted: Bool
    var rationaleShort: String
    var modelVersion: String

    init(
        id: UUID = UUID(),
        label: ActivityLabel,
        timestamp: Date,
        sourceCaptureId: UUID,
        confidence: Double,
        needsReview: Bool,
        isUserCorrected: Bool = false,
        isDeleted: Bool = false,
        rationaleShort: String,
        modelVersion: String
    ) {
        self.id = id
        self.labelRawValue = label.rawValue
        self.timestamp = timestamp
        self.sourceCaptureId = sourceCaptureId
        self.confidence = confidence
        self.needsReview = needsReview
        self.isUserCorrected = isUserCorrected
        self.isDeleted = isDeleted
        self.rationaleShort = rationaleShort
        self.modelVersion = modelVersion
    }

    var label: ActivityLabel {
        get { ActivityLabel(rawValue: labelRawValue) ?? .other }
        set { labelRawValue = newValue.rawValue }
    }
}
