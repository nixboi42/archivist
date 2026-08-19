import Foundation

public enum FinderInvocationSelectionSource: String, Sendable {
    case controller
    case menuSnapshot = "menu-snapshot"
}

public struct PreparedFinderInvocation: Sendable {
    public let request: ArchiveFinderRequest
    public let selectionSource: FinderInvocationSelectionSource
}

public enum FinderActionInvocation {
    public static func prepare(
        action: FinderArchiveAction,
        controllerSelection: [URL],
        menuSelection: [URL]
    ) throws -> PreparedFinderInvocation {
        let source: FinderInvocationSelectionSource = controllerSelection.isEmpty ? .menuSnapshot : .controller
        let urls = source == .controller ? controllerSelection : menuSelection
        let request = ArchiveFinderRequest(action: action, urls: urls)
        try FinderRequestValidator().validate(request)
        return PreparedFinderInvocation(request: request, selectionSource: source)
    }
}

/// Objective-C selector contract for the Finder-facing adapter. The extension implements every
/// listed selector explicitly and uses compile-time `#selector` references when constructing items.
public enum FinderActionSelectorContract {
    public static func selectorName(for action: FinderArchiveAction) -> String {
        switch action {
        case .openArchive: "openArchiveAction:"
        case .extractHere: "extractHereAction:"
        case .extractTo: "extractToAction:"
        case .extractToNamed: "extractToNamedAction:"
        case .createSevenZip: "createSevenZipAction:"
        case .createZIP: "createZIPAction:"
        case .createArchive: "createArchiveAction:"
        }
    }
}
