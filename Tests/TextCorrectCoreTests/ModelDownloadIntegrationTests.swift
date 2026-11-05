import XCTest
@testable import TextCorrectCore

private final class ReceivedBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Int64 = 0
    var count: Int64 { lock.withLock { bytes } }

    /// Records progress from URLSession's background delegate queue.
    func record(_ count: Int64) { lock.withLock { bytes = count } }
}

final class ModelDownloadIntegrationTests: XCTestCase {
    /// Downloads a small pinned public asset and verifies both progress and file integrity.
    func testPinnedDownloadHasRealProgress() async throws {
        guard ProcessInfo.processInfo.environment["TEXTCORRECT_TEST_DOWNLOAD"] == "1" else {
            throw XCTSkip("Enable TEXTCORRECT_TEST_DOWNLOAD=1 for the network integration check")
        }
        let asset = try XCTUnwrap(SpeechModel.catalog().first(where: { $0.engine == .parakeet })?.files.first(where: { $0.size < 1024 }))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        let bytes = ReceivedBytes()
        try await ModelDownload(destination: destination, onProgress: bytes.record).run(url: asset.url)
        try SpeechModelManager.verify(destination, asset: asset)
        XCTAssertEqual(bytes.count, asset.size)
    }
}
