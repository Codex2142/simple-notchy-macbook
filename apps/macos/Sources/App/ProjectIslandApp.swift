import AppKit
import SwiftUI
import IslandBridge
import IslandWindow

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let dbPath = Self.defaultDatabasePath()
        guard let core = try? IslandCore(databasePath: dbPath),
              let controller = try? IslandWindowController(core: core)
        else {
            fputs("Failed to initialize IslandCore\n", stderr)
            return
        }

        let rootView = IslandRootView(controller: controller)
        controller.attachRootView(rootView)
        self.windowController = controller
    }

    static func defaultDatabasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("ProjectIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("project_island.db").path
    }
}

@main
struct ProjectIslandApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
