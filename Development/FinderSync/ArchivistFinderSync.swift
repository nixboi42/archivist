import AppKit
import Domain
import FinderIntegration
import FinderSync
import Foundation
import OSLog

@objc(ArchivistFinderSync)
final class ArchivistFinderSync: FIFinderSync {
    private static let logger = Logger(subsystem: "com.keremgurevin.Archivist.FinderSync", category: "Lifecycle")
    private var snapshot: FinderCapabilitySnapshot?
    private var transport: (any FinderRequestTransport)?
    private var transportMode: FinderRequestTransportMode?
    private var pendingMenuSelection: [URL] = []

    override init() {
        NSLog("[ArchivistFinderSync] init entered")
        super.init()
        Self.logger.notice("extension init")
        let bundle = Bundle(for: ArchivistFinderSync.self)
        guard let mode = try? FinderRequestTransportConfiguration.mode(bundle: bundle),
              let selectedTransport = try? FinderRequestTransportConfiguration.make(bundle: bundle) else {
            Self.logger.error("transport configuration is invalid")
            NSLog("[ArchivistFinderSync] transport configuration is invalid")
            return
        }
        transportMode = mode
        transport = selectedTransport
        switch mode {
        case .appGroup:
            guard let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: FinderRequestStore.appGroupIdentifier
            ) else {
                Self.logger.error("full-team App Group container is unavailable")
                return
            }
            snapshot = FinderCapabilityStore(containerURL: container).load()
            let configuration = MonitoredRootStore(containerURL: container).load()
            assignDirectoryURLs(configuration.enabled ? Set(configuration.roots.map(\.standardizedFileURL)) : [])
        case .personalTeamDevelopment:
            snapshot = PersonalTeamFinderCapabilityProjection.makeSnapshot()
            let roots = PersonalTeamMonitoredRoots.resolve()
            for root in roots {
                Self.logger.notice("resolved Personal Team root: \(root.absoluteString, privacy: .public)")
                NSLog("[ArchivistFinderSync] resolved root: %@", root.absoluteString)
            }
            assignDirectoryURLs(Set(roots))
        }
    }

    override func beginObservingDirectory(at url: URL) {
        Self.logger.notice("beginObservingDirectory: \(url.absoluteString, privacy: .public)")
        NSLog("[ArchivistFinderSync] beginObservingDirectory: %@", url.absoluteString)
    }

    override func endObservingDirectory(at url: URL) {
        Self.logger.notice("endObservingDirectory: \(url.absoluteString, privacy: .public)")
        NSLog("[ArchivistFinderSync] endObservingDirectory: %@", url.absoluteString)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        let targetedURL = FIFinderSyncController.default().targetedURL()
        let selected = urls.isEmpty ? [targetedURL].compactMap { $0 } : urls
        pendingMenuSelection = Array(selected.prefix(32))
        Self.logger.notice("menu(for: \(Self.semanticName(for: menuKind), privacy: .public), rawValue=\(menuKind.rawValue)); targetedURL=\(targetedURL?.absoluteString ?? "nil", privacy: .public); selectedItemURLs=\(selected.map(\.absoluteString).joined(separator: ","), privacy: .public)")

        guard menuKind == .contextualMenuForItems else {
            logReturnedMenu(nil, classification: "unsupported-menu-kind", actions: [])
            return nil
        }
        let detectedFormats = selected.map { ArchiveFormat.extensionFallback(for: $0.lastPathComponent) }
        let policyActions = FinderSelectionPolicy().actions(
            for: selected,
            snapshot: snapshot,
            developmentCreationShortcuts: false
        )
        Self.logger.notice("selectionClassification=\(detectedFormats.allSatisfy { $0 != .unknown } ? "recognized-archive" : "ordinary-or-mixed", privacy: .public); formats=\(detectedFormats.map(String.init(describing:)).joined(separator: ","), privacy: .public); capabilitySource=\(self.transportMode == .personalTeamDevelopment ? PersonalTeamFinderCapabilityProjection.sourceName : "app-group-snapshot", privacy: .public); resultingActions=\(policyActions.map(\.rawValue).joined(separator: ","), privacy: .public)")

        guard !policyActions.isEmpty else {
            logReturnedMenu(nil, classification: "capability-policy-no-actions", actions: [])
            return nil
        }
        let menu = NSMenu(title: "Archivist")
        let rootItem = NSMenuItem(title: "Archivist", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Archivist")
        for action in policyActions {
            submenu.addItem(menuItem(for: action, urls: selected))
        }
        rootItem.submenu = submenu
        menu.addItem(rootItem)
        logReturnedMenu(menu, classification: "capability-derived-nested-menu", actions: policyActions)
        return menu
    }

    private func assignDirectoryURLs(_ roots: Set<URL>) {
        FIFinderSyncController.default().directoryURLs = roots
        let rendered = roots.sorted { $0.path < $1.path }.map(\.absoluteString).joined(separator: ",")
        Self.logger.notice("directoryURLs assigned: \(rendered, privacy: .public)")
        NSLog("[ArchivistFinderSync] directoryURLs assigned: %@", rendered)
    }

    private func logReturnedMenu(_ menu: NSMenu?, classification: String, actions: [FinderArchiveAction]) {
        guard let menu else {
            Self.logger.notice("selectionClassification=\(classification, privacy: .public); capabilitySnapshot=\(self.snapshot == nil ? "unavailable" : "available", privacy: .public); actionCount=\(actions.count); returning=nil")
            return
        }
        Self.logger.notice("selectionClassification=\(classification, privacy: .public); capabilitySnapshot=\(self.snapshot == nil ? "unavailable" : "available", privacy: .public); actionCount=\(actions.count); returning=NSMenu; itemCount=\(menu.items.count)")
        for (index, item) in menu.items.enumerated() {
            Self.logger.notice("item[\(index)]: title=\(item.title, privacy: .public); action=\(item.action.map(NSStringFromSelector) ?? "nil", privacy: .public); target=\(item.target.map { String(describing: type(of: $0)) } ?? "nil", privacy: .public); enabled=\(item.isEnabled); hasSubmenu=\(item.submenu != nil); submenuItemCount=\(item.submenu?.items.count ?? 0)")
            for (childIndex, child) in (item.submenu?.items ?? []).enumerated() {
                Self.logger.notice("item[\(index)].submenu[\(childIndex)]: title=\(child.title, privacy: .public); action=\(child.action.map(NSStringFromSelector) ?? "nil", privacy: .public); target=\(child.target.map { String(describing: type(of: $0)) } ?? "nil", privacy: .public); enabled=\(child.isEnabled)")
            }
        }
    }

    private func menuItem(for action: FinderArchiveAction, urls: [URL]) -> NSMenuItem {
        let selector: Selector
        switch action {
        case .openArchive: selector = #selector(openArchiveAction(_:))
        case .extractHere: selector = #selector(extractHereAction(_:))
        case .extractTo: selector = #selector(extractToAction(_:))
        case .extractToNamed: selector = #selector(extractToNamedAction(_:))
        case .createSevenZip: selector = #selector(createSevenZipAction(_:))
        case .createZIP: selector = #selector(createZIPAction(_:))
        case .createArchive: selector = #selector(createArchiveAction(_:))
        }
        let item = NSMenuItem(title: title(for: action, urls: urls), action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private static func semanticName(for kind: FIMenuKind) -> String {
        switch kind {
        case .contextualMenuForItems: "contextualMenuForItems"
        case .contextualMenuForContainer: "contextualMenuForContainer"
        case .contextualMenuForSidebar: "contextualMenuForSidebar"
        case .toolbarItemMenu: "toolbarItemMenu"
        @unknown default: "unknown(\(kind.rawValue))"
        }
    }

    @objc private func openArchiveAction(_ sender: NSMenuItem) { invoke(.openArchive) }

    @objc private func extractHereAction(_ sender: NSMenuItem) {
        Self.logger.notice("extractHereAction selector entered")
        NSLog("[ArchivistFinderSync] extractHereAction selector entered")
        invoke(.extractHere)
    }

    @objc private func extractToAction(_ sender: NSMenuItem) { invoke(.extractTo) }
    @objc private func extractToNamedAction(_ sender: NSMenuItem) { invoke(.extractToNamed) }
    @objc private func createSevenZipAction(_ sender: NSMenuItem) { invoke(.createSevenZip) }
    @objc private func createZIPAction(_ sender: NSMenuItem) { invoke(.createZIP) }
    @objc private func createArchiveAction(_ sender: NSMenuItem) { invoke(.createArchive) }

    private func invoke(_ action: FinderArchiveAction) {
        guard let transport else {
            Self.logger.error("action invocation rejected: transport unavailable")
            return
        }
        let controllerSelection = FIFinderSyncController.default().selectedItemURLs() ?? []
        let prepared: PreparedFinderInvocation
        do {
            prepared = try FinderActionInvocation.prepare(
                action: action,
                controllerSelection: controllerSelection,
                menuSelection: pendingMenuSelection
            )
        } catch {
            Self.logger.error("request construction failed: \(String(describing: error), privacy: .public)")
            NSSound.beep()
            return
        }
        let request = prepared.request
        Self.logger.notice("selectionSource=\(prepared.selectionSource.rawValue, privacy: .public); action invoked: \(action.rawValue, privacy: .public); sourceURLCount=\(request.urls.count)")
        Self.logger.notice("request constructed id=\(request.id.uuidString, privacy: .public)")
        Task { @MainActor in
            do {
                Self.logger.notice("transport submit started: requestID=\(request.id.uuidString, privacy: .public)")
                let activationURL = try await transport.submit(request)
                Self.logger.notice("development transport submit succeeded: requestID=\(request.id.uuidString, privacy: .public)")
                Self.logger.notice("activation requested")
                let configuration = NSWorkspace.OpenConfiguration()
                let activates = Self.requiresForegroundActivation(action)
                configuration.activates = activates
                NSWorkspace.shared.open(activationURL, configuration: configuration) { _, error in
                    if let error { Self.logger.error("activation failed: \(String(describing: error), privacy: .public)") }
                    else { Self.logger.notice("activation succeeded; foreground=\(activates)") }
                }
            } catch {
                Self.logger.error("Finder action submission failed: \(String(describing: error), privacy: .public)")
                NSSound.beep()
            }
        }
    }

    private static func requiresForegroundActivation(_ action: FinderArchiveAction) -> Bool {
        switch action {
        case .openArchive, .extractTo, .createArchive: true
        case .extractHere, .extractToNamed, .createSevenZip, .createZIP: false
        }
    }

    private func title(for action: FinderArchiveAction, urls: [URL]) -> String {
        switch action {
        case .openArchive: "Open Archive"
        case .extractHere: urls.count == 1 ? "Extract Here" : "Extract Archives Here"
        case .extractTo: "Extract to…"
        case .extractToNamed:
            urls.count == 1 ? "Extract to “\(FinderDestinationPolicy.extractToNamedDirectory(for: urls[0]).lastPathComponent)”" : "Extract Each to Named Folder"
        case .createSevenZip: "Create 7z Archive"
        case .createZIP: "Create ZIP Archive"
        case .createArchive: "Create Archive…"
        }
    }
}
