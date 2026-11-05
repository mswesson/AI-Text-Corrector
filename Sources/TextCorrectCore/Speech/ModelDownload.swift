import Foundation

/// Downloads one asset with real byte progress and cancellation across delegate callbacks.
final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var cancelled = false

    /// Prepares a download into a caller-owned staging location.
    init(destination: URL, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    /// Starts one native download and waits until its file has been moved out of URLSession's temporary storage.
    func run(url: URL) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = lock.withLock {
                    self.continuation = continuation
                    let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
                    self.session = session
                    let task = session.downloadTask(with: url)
                    self.task = task
                    return task
                }
                task.resume()
                if lock.withLock({ cancelled }) { task.cancel() }
            }
        } onCancel: {
            let task = self.lock.withLock {
                self.cancelled = true
                return self.task
            }
            task?.cancel()
        }
    }

    /// Reports the byte count supplied by the native download delegate.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten)
    }

    /// Moves a successful response before URLSession discards its temporary file.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            finish(.failure(SpeechError.unavailable(tr("Не удалось скачать файл модели."))))
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch { finish(.failure(error)) }
    }

    /// Completes failed or cancelled transfers without resuming a finished continuation twice.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let cancelled = lock.withLock { self.cancelled }
            finish(.failure(cancelled ? CancellationError() : error))
        }
    }

    /// Resolves the awaiting caller once and breaks the session/delegate retain cycle.
    private func finish(_ result: Result<Void, Error>) {
        let (pending, session) = lock.withLock {
            let pending = continuation
            let session = self.session
            continuation = nil
            self.session = nil
            task = nil
            return (pending, session)
        }
        session?.finishTasksAndInvalidate()
        pending?.resume(with: result)
    }
}
