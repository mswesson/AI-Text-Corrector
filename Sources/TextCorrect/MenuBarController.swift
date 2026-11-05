import TextCorrectCore
import AppKit

final class MenuBarController: NSObject {
    enum Action { case openMain, openPalette, captureScreen, captureRegion, quit }

    private let statusItem: NSStatusItem
    private let onAction: (Action) -> Void

    init(onAction: @escaping (Action) -> Void) {
        self.onAction = onAction
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "TextCorrect")
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        addItem(tr("Open AI Palette"), #selector(openPalette), "", to: menu)
        addItem(tr("Open TextCorrect"), #selector(openMain), "", to: menu)
        addItem(tr("Capture Screen"), #selector(captureScreen), "", to: menu)
        addItem(tr("Capture Region…"), #selector(captureRegion), "", to: menu)
        menu.addItem(.separator())
        addItem(tr("Settings…"), #selector(openMain), ",", to: menu)
        menu.addItem(.separator())
        addItem(tr("Quit TextCorrect"), #selector(quit), "q", to: menu)
        return menu
    }

    private func addItem(_ title: String, _ action: Selector, _ key: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func openMain() { onAction(.openMain) }
    @objc private func openPalette() { onAction(.openPalette) }
    @objc private func captureScreen() { onAction(.captureScreen) }
    /// Starts interactive region capture from the menu bar.
    @objc private func captureRegion() { onAction(.captureRegion) }
    @objc private func quit() { onAction(.quit) }
}
