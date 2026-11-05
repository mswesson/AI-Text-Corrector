import Foundation
import CryptoKit
import Observation

/// Installs only catalogued models using verified, atomic directory replacement.
@MainActor
@Observable
public final class SpeechModelManager {
    public enum InstallState: Equatable {
        case downloading(Int64, Int64)
        case verifying
        case installing
        case failed(String)
    }
    public private(set) var catalog: [SpeechModel] = []
    public private(set) var installed: Set<String> = []
    public private(set) var states: [String: InstallState] = [:]
    public var inUse: Set<String> = []
    public private(set) var errorMessage: String?
    private let directory: URL
    private let settings: SettingsStore
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Loads catalog metadata and discovers completed model installations.
    public init(directory: URL, settings: SettingsStore) {
        self.directory = directory
        self.settings = settings
        do {
            catalog = try SpeechModel.catalog()
            for model in catalog {
                try model.validate()
                if installationIsComplete(model) { installed.insert(model.id) }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Resolves the selected model without silently replacing an unavailable choice.
    public func activeModel() throws -> (SpeechModel, URL) {
        guard let model = catalog.first(where: { $0.id == settings.settings.activeSpeechModelID }),
              installed.contains(model.id) else {
            throw SpeechError.unavailable(tr("Скачайте и выберите модель в разделе Speech Models."))
        }
        return (model, location(for: model))
    }

    /// Returns the versioned model installation directory.
    public func location(for model: SpeechModel) -> URL {
        directory.appendingPathComponent(model.id + "-" + model.version, isDirectory: true)
    }

    /// Persists an installed model as the active speech engine.
    public func select(_ model: SpeechModel) throws {
        guard inUse.isEmpty, installed.contains(model.id) else {
            throw SpeechError.unavailable(tr("Модель не установлена или сейчас используется диктовка."))
        }
        settings.settings.activeSpeechModelID = model.id
        try settings.save()
    }

    /// Starts a cancellable download without changing the active model.
    public func download(_ model: SpeechModel) {
        guard tasks[model.id] == nil, !installed.contains(model.id) else { return }
        states[model.id] = .downloading(0, model.downloadBytes)
        tasks[model.id] = Task {
            defer { tasks[model.id] = nil }
            do {
                try await install(model)
                installed.insert(model.id)
                states[model.id] = nil
            } catch is CancellationError {
                states[model.id] = nil
            } catch {
                if Task.isCancelled { states[model.id] = nil }
                else { states[model.id] = .failed(error.localizedDescription) }
            }
        }
    }

    /// Cancels a pending installation and lets its staging directory be removed.
    public func cancel(_ model: SpeechModel) { tasks[model.id]?.cancel() }

    /// Removes an inactive, unused downloaded model.
    public func remove(_ model: SpeechModel) throws {
        guard model.id != settings.settings.activeSpeechModelID, !inUse.contains(model.id), tasks[model.id] == nil else {
            throw SpeechError.unavailable(tr("Сначала выберите другую модель и завершите диктовку."))
        }
        try FileManager.default.removeItem(at: location(for: model))
        installed.remove(model.id)
    }

    /// Downloads, checks and atomically publishes all assets of one model.
    private func install(_ model: SpeechModel) async throws {
        try model.validate()
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values.volumeAvailableCapacityForImportantUsage, capacity < model.downloadBytes + 100_000_000 {
            throw SpeechError.unavailable(tr("Недостаточно места для установки модели."))
        }
        let staging = directory.appendingPathComponent(".download-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var completed: Int64 = 0
        for asset in model.files {
            try Task.checkCancellation()
            let offset = completed
            states[model.id] = .downloading(completed, model.downloadBytes)
            let destination = staging.appendingPathComponent(asset.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let download = ModelDownload(destination: destination) { [weak self] bytes in
                Task { @MainActor in
                    guard let self, self.tasks[model.id]?.isCancelled == false,
                          case .downloading = self.states[model.id] else { return }
                    self.states[model.id] = .downloading(offset + bytes, model.downloadBytes)
                }
            }
            try await download.run(url: asset.url)
            states[model.id] = .verifying
            try await Task.detached { try Self.verify(destination, asset: asset) }.value
            completed += asset.size
        }
        try Task.checkCancellation()
        states[model.id] = .installing
        try JSONEncoder().encode(model).write(to: staging.appendingPathComponent("installation.json"), options: .atomic)
        let final = location(for: model)
        if fm.fileExists(atPath: final.path) { try fm.removeItem(at: final) }
        try fm.moveItem(at: staging, to: final)
    }

    /// Checks the installation marker and every declared file before offering a model.
    private func installationIsComplete(_ model: SpeechModel) -> Bool {
        let root = location(for: model)
        guard let data = try? Data(contentsOf: root.appendingPathComponent("installation.json")),
              let saved = try? JSONDecoder().decode(SpeechModel.self, from: data),
              saved.id == model.id, saved.version == model.version, saved.engine == model.engine,
              saved.files == model.files else { return false }
        return model.files.allSatisfy { asset in
            let size = try? root.appendingPathComponent(asset.path).resourceValues(forKeys: [.fileSizeKey]).fileSize
            return size.map { Int64($0) == asset.size } ?? false
        }
    }

    /// Verifies asset size and SHA-256 without loading the full file into memory.
    nonisolated public static func verify(_ url: URL, asset: SpeechModel.Asset) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            size += Int64(data.count)
            hasher.update(data: data)
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard size == asset.size, hash == asset.sha256 else {
            throw SpeechError.unavailable(tr("Файл модели повреждён: размер или SHA-256 не совпадает."))
        }
    }
}
