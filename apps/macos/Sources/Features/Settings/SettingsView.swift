import Combine
import Foundation
import IslandBridge
import SwiftUI

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
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Island Settings")
                .font(.system(size: 16, weight: .bold))

            GroupBox(label: Text("Active Feature Modules").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(SettingsStore.defaultModuleIDs, id: \.self) { moduleID in
                        HStack {
                            Text(moduleID.capitalized)
                            Spacer()
                            Button(store.isModuleEnabled(moduleID) ? "Enabled" : "Disabled") {
                                let next = !store.isModuleEnabled(moduleID)
                                try? store.setModuleEnabled(moduleID, enabled: next)
                            }
                        }
                    }
                }
                .padding(8)
            }

            GroupBox(label: Text("Retention Policies (Days)").font(.headline)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clipboard History: \(store.retentionPolicy.clipboardDays) days (Pinned kept until deleted)")
                    Text("Timer & Focus Sessions: \(store.retentionPolicy.timerHistoryDays) days")
                    Text("Activity Events: \(store.retentionPolicy.activityEventsDays) days")
                    Text("Diagnostic Logs: \(store.retentionPolicy.logsDays) days")
                }
                .font(.system(size: 12))
                .padding(8)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
