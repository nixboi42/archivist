import BackendRegistry
import FinderIntegration
import AppKit
import SwiftUI

public struct ArchivePreferencesView: View {
    private let registry: ArchiveBackendRegistry
    @AppStorage("defaultConflict") private var defaultConflict = "ask"
    @AppStorage("preventPathTraversal") private var traversal = true
    @AppStorage("restrictSymlinks") private var symlinks = true
    @AppStorage("restrictHardlinks") private var hardlinks = true
    @AppStorage("rejectUnicodeCollisions") private var unicode = true
    @AppStorage("maximumConcurrentJobs") private var concurrency = 2
    @AppStorage("externalSevenZipPath") private var externalSevenZipPath = ""
    @State private var statuses: [BackendStatus] = []
    @State private var finderConfiguration = MonitoredRootConfiguration()

    public init(registry: ArchiveBackendRegistry) { self.registry = registry }
    public var body: some View {
        TabView {
            Form {
                Picker("Default conflict behavior", selection: $defaultConflict) {
                    Text("Ask").tag("ask"); Text("Replace").tag("replace"); Text("Skip").tag("skip"); Text("Keep Both").tag("keepBoth")
                }
                Section("Finder Integration") {
                    Toggle("Enable in monitored folders", isOn: $finderConfiguration.enabled).onChange(of: finderConfiguration.enabled) { saveFinderConfiguration() }
                    ForEach(finderConfiguration.roots, id: \.self) { root in
                        HStack { Image(systemName: "folder"); Text(root.path(percentEncoded: false)).lineLimit(1); Spacer(); Button("Remove") { finderConfiguration.roots.removeAll { $0 == root }; saveFinderConfiguration() } }
                    }
                    Button("Add Folder…", action: addMonitoredRoot)
                    Toggle("Allow selected external-volume roots", isOn: $finderConfiguration.allowExternalVolumes).onChange(of: finderConfiguration.allowExternalVolumes) { saveFinderConfiguration() }
                    Text("Finder Sync coverage is limited to these monitored locations. It is not global.").foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gear") }
            Form {
                Section { Text("Format availability is derived from verified capabilities and current backend health. Unsupported formats are not advertised to Finder.").foregroundStyle(.secondary) }
            }.formStyle(.grouped).tabItem { Label("Formats", systemImage: "doc.zipper") }
            Form {
                Section("Recommended Protections") {
                    Toggle("Prevent path traversal", isOn: $traversal)
                    Toggle("Restrict unsafe symbolic links", isOn: $symlinks)
                    Toggle("Restrict unsafe hard links", isOn: $hardlinks)
                    Toggle("Reject Unicode filename collisions", isOn: $unicode)
                }
                Section("Hard Safety") { Text("Non-disableable resource and containment floors remain active regardless of these preferences.").foregroundStyle(.secondary) }
            }.formStyle(.grouped).tabItem { Label("Security", systemImage: "lock.shield") }
            Form { Stepper("Concurrent jobs: \(concurrency)", value: $concurrency, in: 1...8); Text("Changes apply the next time the application starts.").foregroundStyle(.secondary) }
                .formStyle(.grouped).tabItem { Label("Performance", systemImage: "speedometer") }
            Form {
                Section("Backend Status") {
                    ForEach(statuses, id: \.identifier) { status in
                        LabeledContent(status.identifier.rawValue, value: availabilityName(status.availability))
                    }
                }
                Section("External 7-Zip") { TextField("Executable path", text: $externalSevenZipPath); Text("The path is validated on the next launch and can only narrow availability.").foregroundStyle(.secondary) }
                #if DEBUG
                if let mode = try? FinderRequestTransportConfiguration.mode(bundle: .main) {
                    Section("Developer Diagnostics") {
                        LabeledContent("Finder Integration Transport", value: mode.displayName)
                    }
                }
                #endif
            }.formStyle(.grouped).tabItem { Label("Backends", systemImage: "externaldrive.connected.to.line.below") }
        }.frame(width: 600, height: 480).task { statuses = await registry.statuses() }
    }

    private func loadFinderConfiguration() {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FinderRequestStore.appGroupIdentifier) else { return }
        finderConfiguration = MonitoredRootStore(containerURL: container).load()
    }
    private func saveFinderConfiguration() {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FinderRequestStore.appGroupIdentifier) else { return }
        try? MonitoredRootStore(containerURL: container).save(finderConfiguration)
    }
    private func addMonitoredRoot() {
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.allowsMultipleSelection=true
        if panel.runModal() == .OK {
            for url in panel.urls where !finderConfiguration.roots.contains(url) {
                let isExternal = (try? url.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) == false
                if !isExternal || finderConfiguration.allowExternalVolumes { finderConfiguration.roots.append(url) }
            }
            saveFinderConfiguration()
        }
    }
}

private func availabilityName(_ value: BackendAvailability) -> String {
    switch value { case .available: "Available"; case .degraded(let reason): "Degraded — \(reason)"; case .unavailable(let reason): "Unavailable — \(reason)" }
}
