import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var launchAtLogin: Bool = AppSettings.shared.launchAtLogin

    var body: some View {
        Form {
            TextField("Shell", text: $settings.shellPath)
                .help("Leave blank to use $SHELL")
            Stepper(value: $settings.fontSize, in: 9...18, step: 1) {
                Text("Font size: \(Int(settings.fontSize))")
            }
            Stepper(value: $settings.hoverEnterMs, in: 0...400, step: 10) {
                Text("Hover open: \(Int(settings.hoverEnterMs)) ms")
            }
            Stepper(value: $settings.hoverLeaveMs, in: 50...800, step: 10) {
                Text("Hover close: \(Int(settings.hoverLeaveMs)) ms")
            }
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in
                    settings.setLaunchAtLogin(value)
                }
        }
        .padding(20)
        .frame(width: 360)
    }
}
