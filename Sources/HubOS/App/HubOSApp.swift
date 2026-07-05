import SwiftUI

@main
struct HubOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var hub = HubState.shared

    var body: some Scene {
        MenuBarExtra {
            HubPanel()
                .environment(hub)
        } label: {
            // The menu bar glyph. Uses a template image so it adapts to
            // light/dark menu bars automatically.
            Image(systemName: "square.stack.3d.up.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
