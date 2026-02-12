import Foundation

@MainActor
final class ActivityPipeline {
    private let inferenceClient: InferenceClient
    private let store: ActivityStore

    init(inferenceClient: InferenceClient, store: ActivityStore) {
        self.inferenceClient = inferenceClient
        self.store = store
    }

    func processPhotoCapture(photoData: Data, capturedAt: Date) async throws {
        let fileURL = try persistCaptureData(photoData, ext: "jpg")
        let capture = CaptureEnvelope(
            id: UUID(),
            captureType: .photo,
            capturedAt: capturedAt,
            deviceId: nil,
            localMediaURL: fileURL,
            metadata: ["source": "mwdat_photo"]
        )
        let inference = try await inferenceClient.infer(from: capture)
        try store.saveEvent(from: capture, inference: inference)
    }

    private func persistCaptureData(_ data: Data, ext: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PoLCaptures", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}
