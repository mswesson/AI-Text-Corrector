import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

final class PermissionManager {
    enum Permission: String, CaseIterable {
        case accessibility
        case microphone
        case screenRecording

        var title: String {
            switch self {
            case .accessibility: return "Accessibility"
            case .microphone: return "Microphone"
            case .screenRecording: return "Screen Recording"
            }
        }
    }

    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: return AXIsProcessTrusted()
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        }
    }

    func request(_ permission: Permission) async -> Bool {
        switch permission {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        case .microphone:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .screenRecording:
            return CGRequestScreenCaptureAccess()
        }
    }

    func openSystemSettings(_ permission: Permission) {
        let pane: String
        switch permission {
        case .accessibility: pane = "com.apple.preference.security?Privacy_Accessibility"
        case .microphone: pane = "com.apple.preference.security?Privacy_Microphone"
        case .screenRecording: pane = "com.apple.preference.security?Privacy_ScreenCapture"
        }
        if let url = URL(string: "x-apple.systempreferences:\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
