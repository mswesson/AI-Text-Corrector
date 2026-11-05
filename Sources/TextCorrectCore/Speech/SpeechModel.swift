import Foundation

/// A pinned, reviewed set of speech model assets.
public struct SpeechModel: Codable, Identifiable, Equatable {
    public enum Engine: String, Codable { case whisper, parakeet }
    public struct Asset: Codable, Equatable {
        public var path: String
        public var url: URL
        public var sha256: String
        public var size: Int64
    }
    public struct Benchmark: Codable, Equatable {
        public var language: String
        public var wer: Double?
        public var rtfx: Double?
        public var dataset: String?
        public var datasetVersion: String?
        public var normalization: String?
        public var hardware: String?
        public var chip: String?
        public var memoryGB: Int?
        public var engine: String?
        public var backend: String?
        public var audioSeconds: Double?
        public var source: URL
        public var date: String
        public var modelVersion: String
    }
    public var id: String
    public var name: String
    public var description: String
    public var engine: Engine
    public var version: String
    public var languages: [String]
    public var license: String
    public var source: URL
    public var files: [Asset]
    public var benchmarks: [Benchmark]
    public var downloadBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    /// Loads the bundled offline catalog without contacting a model repository.
    public static func catalog() throws -> [SpeechModel] {
        let url = Bundle.module.url(forResource: "SpeechModels", withExtension: "json")!
        return try JSONDecoder().decode([SpeechModel].self, from: Data(contentsOf: url))
    }

    /// Rejects unsafe paths, unpinned URLs and missing checksums before installation.
    public func validate() throws {
        guard !files.isEmpty, version.count == 40,
              version.allSatisfy({ $0.isHexDigit }),
              !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw SpeechError.unavailable(tr("Некорректный манифест модели."))
        }
        for file in files {
            let components = file.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  !file.path.contains("\\"), file.url.scheme == "https", file.url.host == "huggingface.co",
                  file.url.path.contains("/resolve/\(version)/"), file.sha256.count == 64,
                  file.sha256.allSatisfy({ $0.isHexDigit }), file.size > 0 else {
                throw SpeechError.unavailable(tr("Модель содержит непроверенный файл."))
            }
        }
    }
}

public enum SpeechError: LocalizedError, Equatable {
    case unavailable(String)
    case noSpeech

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .noSpeech: return tr("Речь не распознана. Повторите запись.")
        }
    }
}
