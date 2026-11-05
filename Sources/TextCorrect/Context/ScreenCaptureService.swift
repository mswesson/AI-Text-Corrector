import TextCorrectCore
import AppKit
import ScreenCaptureKit
import Observation

/// Captures display pixels as PNG data without writing files.
@MainActor
@Observable
final class ScreenCaptureService {
    private(set) var isCapturing = false
    private(set) var errorMessage: String?
    private let selector = RegionSelector()

    /// Captures the display under the pointer or an interactively selected region.
    func capture(region: Bool) async -> Data? {
        guard !isCapturing else { return nil }
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }
        let activeScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            errorMessage = tr("Разрешите запись экрана в системных настройках macOS.")
            return nil
        }
        do {
            let screen: NSScreen
            let rect: CGRect
            if region {
                guard let selected = await selector.select() else { return nil }
                screen = selected.screen
                rect = selected.rect
            } else {
                guard let activeScreen else { throw CaptureError.displayUnavailable }
                screen = activeScreen
                rect = CGRect(origin: .zero, size: screen.frame.size)
            }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayUnavailable
            }
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = rect
            config.width = max(1, Int((rect.width * CGFloat(filter.pointPixelScale)).rounded(.up)))
            config.height = max(1, Int((rect.height * CGFloat(filter.pointPixelScale)).rounded(.up)))
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw CaptureError.encodingFailed
            }
            return data
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

private enum CaptureError: LocalizedError {
    case displayUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: return tr("Экран недоступен. Повторите захват.")
        case .encodingFailed: return tr("Не удалось подготовить изображение.")
        }
    }
}
