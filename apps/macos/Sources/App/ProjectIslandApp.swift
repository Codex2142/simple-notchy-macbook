import AppKit
import SwiftUI
import IslandBridge
import IslandWindow
import IslandIntegrations
import IslandFeatures

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: IslandWindowController?
    private var pasteboardMonitor: PasteboardMonitor?
    private var keepAwakeAdapter: KeepAwakeAdapter?
    private var mediaAdapter: MediaAdapter?
    private var systemMetricsAdapter: SystemMetricsAdapter?
    private var notesShelfStore: NotesShelfStore?
    private var settingsStore: SettingsStore?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let dbPath = Self.defaultDatabasePath()
        guard let core = try? IslandCore(databasePath: dbPath),
              let controller = try? IslandWindowController(core: core),
              let pasteboard = try? PasteboardMonitor(core: core),
              let keepAwake = try? KeepAwakeAdapter(core: core),
              let media = try? MediaAdapter(core: core, enableLivePolling: true),
              let systemMetrics = try? SystemMetricsAdapter(core: core, autoStartRefresh: true),
              let notesShelf = try? NotesShelfStore(core: core),
              let settings = try? SettingsStore(core: core)
        else {
            fputs("Failed to initialize IslandCore\n", stderr)
            return
        }

        pasteboard.startMonitoring()
        let rootView = IslandRootView(
            controller: controller,
            pasteboardMonitor: pasteboard,
            keepAwakeAdapter: keepAwake,
            mediaAdapter: media,
            systemMetricsAdapter: systemMetrics,
            notesShelfStore: notesShelf
        )
        controller.attachRootView(rootView)
        self.windowController = controller
        self.pasteboardMonitor = pasteboard
        self.keepAwakeAdapter = keepAwake
        self.mediaAdapter = media
        self.systemMetricsAdapter = systemMetrics
        self.notesShelfStore = notesShelf
        self.settingsStore = settings
        setupMenuBarExtra()
    }

    private func setupMenuBarExtra() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Project Island")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Island Expansion", action: #selector(toggleIsland), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Detach Menu Bar Icon", action: #selector(detachMenuBar), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Project Island", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item
    }

    @objc private func toggleIsland() {
        windowController?.toggleExpandedOrPinned()
    }

    @objc private func openSettings() {
        guard let settingsStore else { return }
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 420, height: 340),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Project Island Settings"
            win.center()
            win.contentView = NSHostingView(rootView: SettingsView(store: settingsStore))
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func detachMenuBar() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
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
