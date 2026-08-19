import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
public final class ApplicationPresentationCoordinator: ApplicationPresenting {
    private static let logger = Logger(subsystem: "com.keremgurevin.Archivist", category: "window-presentation")
    public static let jobsWindowIdentifier = NSUserInterfaceItemIdentifier("com.archivist.jobs")
    public static let interactionWindowIdentifier = NSUserInterfaceItemIdentifier("com.archivist.required-interaction")
    private unowned let model: ArchiveAppModel
    private var mainController: NSWindowController?
    private var jobsController: NSWindowController?
    private var interactionController: NSWindowController?
    private var cancellables: Set<AnyCancellable> = []
    public private(set) var isPresentingRequiredInteraction = false

    public init(model: ArchiveAppModel) {
        self.model = model
        model.$conflictPrompt.dropFirst().sink { [weak self] prompt in
            guard let self, let prompt else { return }
            Self.logger.notice("conflict panel presentation requested; path=\(prompt.context.destinationURL.path, privacy: .private(mask: .hash))")
            self.presentInteraction(kind: .conflict, title: "Archive Conflict", view: AnyView(ConflictSheet(prompt: prompt) { resolution, remaining in
                self.model.answerConflict(resolution, remaining: remaining); self.closeInteraction()
            }))
        }.store(in: &cancellables)
        model.$passwordPromptVisible.dropFirst().filter { $0 }.sink { [weak self] _ in
            self?.presentPassword()
        }.store(in: &cancellables)
        model.$errorPresentation.dropFirst().compactMap { $0 }.sink { [weak self] error in
            self?.presentInteraction(kind: .error, title: error.title, view: AnyView(ErrorSheet(presentation: error) {
                self?.model.errorPresentation = nil; self?.closeInteraction()
            }))
        }.store(in: &cancellables)
    }

    public func presentMainWindow() {
        if mainController == nil {
            mainController = makeWindow(title: "Archivist", size: NSSize(width: 1040, height: 680),
                                        view: AnyView(ArchiveMainView(model: model, presentation: self)))
        }
        activate(mainController)
    }

    public func presentJobs() {
        Self.logger.notice("showJobs requested; observedModelJobCount=\(self.model.jobs.count)")
        NSLog("[Archivist Jobs] showJobs requested; observedModelJobCount=%d", model.jobs.count)
        let existing = NSApp.windows.first { $0.identifier == Self.jobsWindowIdentifier }
        Self.logger.notice("window lookup result=\(existing == nil ? "not-found" : "found")")
        if jobsController == nil {
            Self.logger.notice("NSWindow creation invoked")
            jobsController = makeWindow(title: "Archivist Jobs", size: NSSize(width: 380, height: 430),
                                        identifier: Self.jobsWindowIdentifier,
                                        view: AnyView(JobsView(model: model)))
        }
        guard let window = jobsController?.window else {
            Self.logger.error("Jobs NSWindowController has no window")
            return
        }
        recoverOntoVisibleScreen(window)
        NSApp.activate(ignoringOtherApps: true)
        jobsController?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        logJobsWindowState(window, phase: "ordered")
        Task { [weak self, weak window] in
            let queueCount = await self?.model.queue.snapshots().count ?? 0
            guard let self, let window else { return }
            Self.logger.notice("current JobQueue job count=\(queueCount)")
            self.logJobsWindowState(window, phase: "next-runloop")
        }
    }

    public func presentExtractionDestination(for archive: URL, completion: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Extract \(archive.lastPathComponent)"
        panel.prompt = "Extract"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in completion(url) }
        }
    }

    private func presentPassword() {
        presentInteraction(kind: .password, title: "Archive Password", view: AnyView(PasswordPromptView(model: model) { [weak self] in self?.closeInteraction() }))
    }

    private func presentInteraction(kind: RequiredInteractionKind, title: String, view: AnyView) {
        let plan = AuxiliaryPresentationPlan(kind: kind)
        isPresentingRequiredInteraction = true
        interactionController?.close()
        Self.logger.notice("required interaction NSPanel creation invoked; kind=\(kind.rawValue, privacy: .public)")
        interactionController = makeWindow(title: title, size: NSSize(width: 520, height: 240),
                                           identifier: Self.interactionWindowIdentifier,
                                           view: view, panel: true)
        guard let controller = interactionController, let window = controller.window else { return }
        recoverOntoVisibleScreen(window)
        logInteractionState(window, kind: kind, phase: "requested")

        // A required interaction is made visible before activation. This prevents AppKit's
        // reopen callback from observing a windowless application and creating the browser.
        if plan.showBeforeActivation {
            Self.logger.notice("required interaction showWindow/orderFront invoked before activation")
            controller.showWindow(nil)
            window.orderFrontRegardless()
        }
        if plan.activatesApplication {
            Self.logger.notice("required interaction NSApp.activate invoked")
            NSApp.activate(ignoringOtherApps: true)
        }
        Self.logger.notice("required interaction makeKeyAndOrderFront invoked")
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        logInteractionState(window, kind: kind, phase: "ordered")
        Task { @MainActor [weak self, weak window] in
            guard let self, let window else { return }
            self.logInteractionState(window, kind: kind, phase: "next-runloop")
        }
    }

    private func closeInteraction() {
        interactionController?.close()
        interactionController = nil
        isPresentingRequiredInteraction = false
    }

    private func makeWindow(title: String, size: NSSize, identifier: NSUserInterfaceItemIdentifier? = nil,
                            view: AnyView, panel: Bool = false) -> NSWindowController {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let window: NSWindow = panel
            ? NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
            : NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title; window.identifier = identifier
        if let panel = window as? NSPanel {
            panel.becomesKeyOnlyIfNeeded = false
            panel.worksWhenModal = true
            panel.hidesOnDeactivate = false
        }
        window.contentViewController = NSHostingController(rootView: view)
        window.isReleasedWhenClosed = false; window.center()
        return NSWindowController(window: window)
    }

    private func activate(_ controller: NSWindowController?) {
        NSApp.activate(ignoringOtherApps: true); controller?.showWindow(nil); controller?.window?.makeKeyAndOrderFront(nil)
    }

    private func recoverOntoVisibleScreen(_ window: NSWindow) {
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }),
              let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - window.frame.width / 2,
                                      y: screen.visibleFrame.midY - window.frame.height / 2))
    }

    private func logJobsWindowState(_ window: NSWindow, phase: String) {
        let identifier = window.identifier?.rawValue ?? "none"
        let registered = NSApp.windows.contains { $0 === window }
        Self.logger.notice("Jobs window phase=\(phase, privacy: .public); identifier=\(identifier, privacy: .public); registered=\(registered); isVisible=\(window.isVisible); isKeyWindow=\(window.isKeyWindow); isMainWindow=\(window.isMainWindow)")
        NSLog("[Archivist Jobs] phase=%@ identifier=%@ registered=%@ isVisible=%@ isKeyWindow=%@ isMainWindow=%@",
              phase, identifier, String(registered), String(window.isVisible), String(window.isKeyWindow), String(window.isMainWindow))
    }

    private func logInteractionState(_ window: NSWindow, kind: RequiredInteractionKind, phase: String) {
        let browser = mainController?.window
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        Self.logger.notice("presentInteraction phase=\(phase, privacy: .public) kind=\(kind.rawValue, privacy: .public); browserExists=\(browser != nil); browserVisible=\(browser?.isVisible ?? false); panelExists=true; panelVisible=\(window.isVisible); panelKey=\(window.isKeyWindow); panelMain=\(window.isMainWindow); appActive=\(NSApp.isActive); frontmost=\(frontmost, privacy: .public)")
        NSLog("[Archivist Interaction] phase=%@ kind=%@ browserExists=%@ browserVisible=%@ panelVisible=%@ panelKey=%@ panelMain=%@ appActive=%@ frontmost=%@",
              phase, kind.rawValue, String(browser != nil), String(browser?.isVisible ?? false),
              String(window.isVisible), String(window.isKeyWindow), String(window.isMainWindow),
              String(NSApp.isActive), frontmost)
    }
}

public enum RequiredInteractionKind: String, CaseIterable, Sendable {
    case conflict, password, error
}

public struct AuxiliaryPresentationPlan: Equatable, Sendable {
    public let kind: RequiredInteractionKind
    public let requestsMainWindow = false
    public let activatesApplication = true
    public let showBeforeActivation = true
    public init(kind: RequiredInteractionKind) { self.kind = kind }
}

public struct PasswordPromptView: View {
    @ObservedObject private var model: ArchiveAppModel
    private let completed: () -> Void
    public init(model: ArchiveAppModel, completed: @escaping () -> Void = {}) { self.model = model; self.completed = completed }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Archive Password").font(.title2)
            SecureField("Password", text: $model.password).privacySensitive().textContentType(.password)
            Text("Passwords are used only for this operation and are not saved.").foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { model.cancelPassword(); completed() }; Button("Continue") { model.submitPassword(); completed() }.keyboardShortcut(.defaultAction).disabled(model.password.isEmpty) }
        }.padding(24).frame(width: 420)
    }
}
