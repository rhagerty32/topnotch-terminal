import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    private var router: SurfaceRouter?
    private var ipc = CommandServer()
    private var statusItem: NSStatusItem?
    private var pendingSummon = false
    private let summonHotkey = SummonHotkey()
    private var openedAtLogin = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        openedAtLogin = Self.launchedAsLoginItem()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        NSApp.setActivationPolicy(.accessory)
        installMenu()
        installStatusItem()
        let router = SurfaceRouter(store: store)
        self.router = router
        ipc.handler = { command in
            router.handleIPC(command)
        }
        ipc.start()
        summonHotkey.onPress = { [weak self] in
            self?.summonNow()
        }
        summonHotkey.apply(AppSettings.shared.summonHotkey)
        NotificationCenter.default.addObserver(
            forName: .topNotchSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.summonHotkey.apply(AppSettings.shared.summonHotkey)
            }
        }
        if pendingSummon {
            pendingSummon = false
            router.summon()
        } else if !openedAtLogin {
            presentRequestedOpen()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppSettings.shared.confirmQuitWhileBusy else { return .terminateNow }
        for session in store.sessions {
            session.refreshBusy()
        }
        guard store.isAnyBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A command is still running"
        alert.informativeText = "Quitting ends every session in the notch."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipc.stop()
        router?.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentRequestedOpen()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        summonNow()
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        summonNow()
    }

    @objc func summonNow() {
        if let router {
            router.summon()
        } else {
            pendingSummon = true
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "apple.terminal", accessibilityDescription: "TopNotch Terminal")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Terminal", action: #selector(summonNow), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "t").target = self
        menu.addItem(withTitle: "Close Tab", action: #selector(closeTab), keyEquivalent: "w").target = self
        menu.addItem(withTitle: "Pin / Unpin", action: #selector(pin), keyEquivalent: "p").target = self
        menu.addItem(withTitle: "Pop Out", action: #selector(kick), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(withTitle: "Move to Notch", action: #selector(kickBack), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit TopNotch Terminal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func installMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit TopNotch Terminal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "t").target = self
        file.addItem(withTitle: "Close Tab", action: #selector(closeTab), keyEquivalent: "w").target = self
        let fileItem = NSMenuItem()
        fileItem.submenu = file
        main.addItem(fileItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc private func newTab() {
        store.addTab()
    }

    @objc private func closeTab() {
        store.closeSelected()
    }

    @objc private func pin() { router?.togglePin() }
    @objc private func kick() { router?.kickOut() }
    @objc private func kickBack() { router?.kickBack() }

    @objc private func openSettings() {
        SettingsWindow.show()
    }

    /// Finder, Spotlight, and a second click open Settings unless the user picked
    /// another behavior. The first time, the window includes the hover hint.
    private func presentRequestedOpen() {
        let settings = AppSettings.shared
        if !settings.hasOpenedSettings {
            settings.showFirstLaunchHint = true
            settings.hasOpenedSettings = true
            SettingsWindow.show()
            return
        }
        switch settings.openAppBehavior {
        case .settings:
            SettingsWindow.show()
        case .terminal:
            summonNow()
        case .both:
            SettingsWindow.show()
            summonNow()
        }
    }

    /// SMAppService login items set this on the opening AppleEvent. A normal
    /// Finder launch does not, so the two cold starts can take different paths.
    private static func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        guard event.eventID == AEEventID(kAEOpenApplication) else { return false }
        guard let props = event.paramDescriptor(forKeyword: keyAEPropData) else { return false }
        return props.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem)?.booleanValue == true
    }
}
