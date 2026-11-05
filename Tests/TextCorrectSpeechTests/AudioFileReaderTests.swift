import XCTest
import AVFoundation
import TextCorrectCore
@testable import TextCorrectSpeech

final class AudioFileReaderTests: XCTestCase {
    /// Creates a short PCM fixture without microphone access or network dependencies.
    private func recording(rate: Double, channels: AVAudioChannelCount, seconds: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate)))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<Int(channels) {
            for index in 0..<Int(buffer.frameLength) {
                buffer.floatChannelData![channel][index] = sin(Float(index) * 0.1) * 0.2
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        for _ in 0..<seconds { try file.write(from: buffer) }
        return url
    }

    /// Reaches EOF without AVAudioFile attempting to read beyond the final frame.
    func testResamplingAndRepeatedEOF() throws {
        let url = try recording(rate: 22_050, channels: 1, seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try AudioFileReader(url: url)
        let samples = try XCTUnwrap(reader.nextSamples())
        XCTAssertTrue((15_900...16_100).contains(samples.count))
        XCTAssertNil(try reader.nextSamples())
        XCTAssertNil(try reader.nextSamples())
    }

    /// Downmixes stereo microphone-like input into a single 16 kHz signal.
    func testStereoInput() throws {
        let url = try recording(rate: 48_000, channels: 2, seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let samples = try XCTUnwrap(AudioFileReader(url: url).nextSamples())
        XCTAssertTrue((15_900...16_100).contains(samples.count))
        XCTAssertTrue(samples.contains { abs($0) > 0.01 })
    }

    /// Splits a long recording into bounded chunks while preserving all audio frames.
    func testLongFileUsesBoundedChunks() throws {
        let url = try recording(rate: 16_000, channels: 1, seconds: 31)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try AudioFileReader(url: url)
        let first = try XCTUnwrap(reader.nextSamples())
        let second = try XCTUnwrap(reader.nextSamples())
        XCTAssertLessThanOrEqual(first.count, 480_000)
        XCTAssertLessThanOrEqual(second.count, 480_000)
        XCTAssertEqual(first.count + second.count, 31 * 16_000)
        XCTAssertNil(try reader.nextSamples())
    }

    /// Cancels before opening a model or audio file, so no weights or downloads are required.
    func testCancelledInferenceNeverLoadsWeights() async throws {
        let cancellation = SpeechCancellation()
        cancellation.cancel()
        let model = try XCTUnwrap(SpeechModel.catalog().first)
        let absent = URL(fileURLWithPath: "/nonexistent-textcorrect-fixture")
        do {
            _ = try await SpeechRecognitionService().transcribe(file: absent, model: model, directory: absent, cancellation: cancellation)
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
