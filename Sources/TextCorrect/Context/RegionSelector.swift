import TextCorrectCore
import AppKit

/// Lets the user select a rectangle on any connected display.
@MainActor
final class RegionSelector {
    struct Selection {
        let screen: NSScreen
        let rect: CGRect
    }

    private var windows: [NSPanel] = []
    private var continuation: CheckedContinuation<Selection?, Never>?

    /// Shows display overlays until the user selects a region or presses Escape.
    func select() async -> Selection? {
        guard continuation == nil, !NSScreen.screens.isEmpty else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            for screen in NSScreen.screens {
                let window = SelectionPanel(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isOpaque = false
                window.backgroundColor = .clear
                window.level = .screenSaver
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.isReleasedWhenClosed = false
                window.sharingType = .none
                let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size)) { [weak self] rect in
                    self?.finish(rect.map { Selection(screen: screen, rect: $0) })
                }
                window.contentView = view
                windows.append(window)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
            }
            if let active = windows.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
                active.makeKey()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Removes all overlays and resolves the active selection exactly once.
    private func finish(_ selection: Selection?) {
        for window in windows { window.close() }
        windows = []
        let pending = continuation
        continuation = nil
        pending?.resume(returning: selection)
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    private let onFinish: (CGRect?) -> Void
    private var start: CGPoint?
    private var selection: CGRect = .zero

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Creates an overlay with a callback for the selected display-local rectangle.
    init(frame: CGRect, onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        super.init(frame: frame)
    }

    /// Disables decoding for this programmatically created overlay.
    required init?(coder: NSCoder) { nil }

    /// Draws a shaded screen with the selected rectangle left visible.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()
        if !selection.isEmpty {
            NSGraphicsContext.current?.cgContext.clear(selection)
            NSColor.white.setStroke()
            NSBezierPath(rect: selection).stroke()
        }
        let hint = tr("Выделите область · Esc — отмена") as NSString
        hint.draw(at: CGPoint(x: 24, y: 24), withAttributes: [
            .font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.white,
        ])
    }

    /// Starts a new selection at the mouse location.
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    /// Keeps the selection inside the display where dragging began.
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                           width: abs(start.x - point.x), height: abs(start.y - point.y)).intersection(bounds)
        needsDisplay = true
    }

    /// Completes a nonempty selection without creating an image for a click.
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        onFinish(selection.width >= 1 && selection.height >= 1 ? selection : nil)
    }

    /// Cancels region capture when Escape is pressed.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) }
        else { super.keyDown(with: event) }
    }

    /// Uses the system crosshair cursor over the selection overlay.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}
