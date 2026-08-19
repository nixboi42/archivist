import AppKit
import ArchiveApplication
import ArchiveUI
import BackendRegistry
import ProductionComposition
import SwiftUI

@MainActor
final class ApplicationRuntime {
    static let shared = ApplicationRuntime()
    let registry: ArchiveBackendRegistry
    let model: ArchiveAppModel
    let presentation: ApplicationPresentationCoordinator
    lazy var finder = FinderRequestCoordinator(model: model, presentation: presentation)
    private var backendConfiguration: Task<Void, Never>?

    private init() {
        ArchivistPreferenceMigration.migrateIfNeeded()
        ArchiveDragExportUseCase.sweepOrphans()
        StartupAccessAudit.event("application-init", "creating in-memory registry and UI model")
        registry = ArchiveBackendRegistry()
        let maximum = UserDefaults.standard.integer(forKey: "maximumConcurrentJobs")
        model = ArchiveAppModel(registry: registry, maximumConcurrentJobs: maximum > 0 ? maximum : 2)
        presentation = ApplicationPresentationCoordinator(model: model)
    }

    func configureBackends() {
        guard backendConfiguration == nil else { return }
        backendConfiguration = Task {
            let path = UserDefaults.standard.string(forKey: "externalSevenZipPath")
            let external = path.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            StartupAccessAudit.path("backend-health", external ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/7zz"), reason: "exact configured 7zz probe")
            await ProductionEnvironment.configure(registry, externalSevenZip: external)
            StartupAccessAudit.event("backend-health", "libarchive initialized in process; XIP tools remain lazy")
        }
    }

    func handleFinderURL(_ url: URL) {
        configureBackends()
        guard let backendConfiguration else { return }
        Task {
            await backendConfiguration.value
            finder.handle(url)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private var runtime: ApplicationRuntime { .shared }
    func applicationDidFinishLaunching(_ notification: Notification) {
        StartupAccessAudit.event("app-delegate", "launch completed without filesystem traversal or forced activation")
        runtime.configureBackends()
    }
    func application(_ application: NSApplication, open urls: [URL]) { for url in urls { runtime.handleFinderURL(url) } }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool { runtime.presentation.presentMainWindow(); return true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && !runtime.presentation.isPresentingRequiredInteraction {
            runtime.presentation.presentMainWindow()
        }
        return true
    }
    func applicationShouldSaveApplicationState(_ sender: NSApplication) -> Bool { false }
    func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool { false }
}

@main
struct ArchivistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let runtime = ApplicationRuntime.shared

    var body: some Scene {
        Settings { ArchivePreferencesView(registry: runtime.registry) }
            .commands { ArchiveCommands(model: runtime.model, presentation: runtime.presentation) }
    }
}
