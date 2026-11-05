import Foundation

/// Immutable snapshot of the selection captured before the panel steals focus.
public struct TargetContext: Equatable {
    public enum Source: String, Codable {
        case accessibility
        case clipboard
    }

    public var pid: pid_t
    public var bundleID: String?
    public var appName: String?
    public var role: String?
    public var originalText: String
    public var range: NSRange?
    public var fieldValue: String?
    public var source: Source
    public var capturedAt: Date

    public init(
        pid: pid_t,
        bundleID: String? = nil,
        appName: String? = nil,
        role: String? = nil,
        originalText: String,
        range: NSRange? = nil,
        fieldValue: String? = nil,
        source: Source = .accessibility,
        capturedAt: Date = Date()
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.role = role
        self.originalText = originalText
        self.range = range
        self.fieldValue = fieldValue
        self.source = source
        self.capturedAt = capturedAt
    }
}

public enum TargetCheck: Equatable {
    case safe
    case appUnavailable
    case elementUnavailable
    case roleChanged
    case selectionChanged

    public var message: String {
        switch self {
        case .safe: return ""
        case .appUnavailable: return tr("Исходное приложение недоступно.")
        case .elementUnavailable: return tr("Исходное поле больше не доступно.")
        case .roleChanged: return tr("Изменилось целевое поле.")
        case .selectionChanged: return tr("Исходный текст изменился или выделение снято.")
        }
    }
}

/// Pure validation of a saved snapshot against the current state of the target field.
public enum ReplacementValidator {
    /// Rejects a replacement when its element, range or text no longer matches.
    public static func check(
        saved: TargetContext,
        isAppRunning: Bool,
        currentRole: String?,
        currentSelectedText: String?,
        currentFieldValue: String?,
        currentRange: NSRange?,
        isSameElement: Bool
    ) -> TargetCheck {
        guard isAppRunning else { return .appUnavailable }
        guard isSameElement else { return .elementUnavailable }
        guard let currentRole else { return .elementUnavailable }
        if let savedRole = saved.role, savedRole != currentRole { return .roleChanged }

        guard let range = saved.range, currentRange == range else { return .selectionChanged }
        if let fieldValue = saved.fieldValue, currentFieldValue != fieldValue { return .selectionChanged }
        switch saved.source {
        case .accessibility:
            let selectedText = currentSelectedText ?? (currentRange?.length == 0 ? "" : nil)
            guard let selectedText, selectedText == saved.originalText else {
                return .selectionChanged
            }
        case .clipboard:
            return .selectionChanged
        }
        return .safe
    }
}
