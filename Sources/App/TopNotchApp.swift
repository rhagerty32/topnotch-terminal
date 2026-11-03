import SwiftUI

@main
struct TopNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .onOpenURL { _ in
                    appDelegate.summonNow()
                }
        }
    }
}
