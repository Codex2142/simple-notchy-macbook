import Combine
import Foundation
import IslandBridge
import SwiftUI

public struct ModuleInfo: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let icon: String

    public init(id: String, title: String, subtitle: String, icon: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }
}

/// View model managing module activation and retention policy settings backed by Rust SQLite storage.
@MainActor
public final class SettingsStore: ObservableObject {
    public static let defaultModuleIDs = [
        "media",
        "clipboard",
        "timer",
        "system",
        "notes",
        "shelf"
    ]

    public static let moduleCatalog: [ModuleInfo] = [
        ModuleInfo(id: "media", title: "Spotify & Music", subtitle: "Now playing track, playback controls & live lyrics", icon: "sparkles"),
        ModuleInfo(id: "clipboard", title: "Clipboard", subtitle: "Clipboard history, pinning, search & delete all", icon: "doc.on.clipboard"),
        ModuleInfo(id: "timer", title: "Timer", subtitle: "Custom countdown, Pomodoro & keep awake", icon: "timer"),
        ModuleInfo(id: "system", title: "System Monitoring", subtitle: "Real-time CPU usage, memory stats & battery", icon: "cpu"),
        ModuleInfo(id: "notes", title: "Notes", subtitle: "Quick scratchpad for fast thoughts & pinned notes", icon: "note.text"),
        ModuleInfo(id: "shelf", title: "Shelf", subtitle: "Drag & drop temporary file buffer", icon: "tray.and.arrow.down")
    ]

    @Published public private(set) var moduleStates: [String: Bool] = [:]
    @Published public var retentionPolicy: FfiRetentionPolicy
    @Published public var menuBarDetached: Bool = false

    private let core: IslandCore

    public init(core: IslandCore) throws {
        self.core = core
        self.retentionPolicy = try core.getRetentionPolicy()
        try bootstrapAndLoadModules()
    }

    public func isModuleEnabled(_ moduleID: String) -> Bool {
        moduleStates[moduleID] ?? true
    }

    public func setModuleEnabled(_ moduleID: String, enabled: Bool) throws {
        try core.setModuleEnabled(moduleId: moduleID, enabled: enabled, configJson: "{}")
        moduleStates[moduleID] = enabled
    }

    public func updateRetentionPolicy(_ policy: FfiRetentionPolicy) throws {
        try core.setRetentionPolicy(policy: policy)
        self.retentionPolicy = try core.getRetentionPolicy()
    }

    private func bootstrapAndLoadModules() throws {
        let existing = try core.listModules()
        var map: [String: Bool] = [:]
        for item in existing {
            map[item.moduleId] = item.enabled
        }
        for moduleID in Self.defaultModuleIDs where map[moduleID] == nil {
            try core.setModuleEnabled(moduleId: moduleID, enabled: true, configJson: "{}")
            map[moduleID] = true
        }
        self.moduleStates = map
    }
}

public struct SettingsView: View {
    @ObservedObject public var store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Project Island Settings")
                            .font(.system(size: 16, weight: .bold))
                        Text("Configure menu visibility and local data retention")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 2)

                // Menu Visibility Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Dynamic Island Menu Visibility")
                            .font(.system(size: 13, weight: .semibold))

                        Text("Choose which feature menus appear when the island is expanded. Disabling a menu preserves its data and history.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Divider()

                        ForEach(SettingsStore.moduleCatalog) { module in
                            HStack(spacing: 12) {
                                Image(systemName: module.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 22)
                                    .foregroundColor(.accentColor)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(module.title)
                                        .font(.system(size: 12.5, weight: .medium))
                                    Text(module.subtitle)
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { store.isModuleEnabled(module.id) },
                                    set: { newValue in
                                        try? store.setModuleEnabled(module.id, enabled: newValue)
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(10)
                }

                // Data Retention Policies Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Data Retention Policies")
                            .font(.system(size: 13, weight: .semibold))

                        Text("Automatic cleanup threshold for local SQLite databases.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            policyRow(label: "Clipboard History", value: "\(store.retentionPolicy.clipboardDays) days (Pinned kept forever)")
                            policyRow(label: "Timer & Focus Sessions", value: "\(store.retentionPolicy.timerHistoryDays) days")
                            policyRow(label: "Activity & Peek Events", value: "\(store.retentionPolicy.activityEventsDays) days")
                            policyRow(label: "Diagnostic Logs", value: "\(store.retentionPolicy.logsDays) days")
                        }
                    }
                    .padding(10)
                }
            }
            .padding(20)
        }
        .frame(width: 480, height: 500)
    }

    private func policyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}
