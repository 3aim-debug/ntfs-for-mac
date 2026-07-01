import SwiftUI
import NTFSAccessCore

@main
struct NTFSAccessApp: App {
    @StateObject private var driveManager = DriveManager()

    var body: some Scene {
        WindowGroup(AppInfo.displayName) {
            ContentView()
                .environmentObject(driveManager)
                .task {
                    driveManager.start()
                    driveManager.refresh()
                    await driveManager.refreshDriverStatus()
                }
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Drives") {
                    driveManager.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
