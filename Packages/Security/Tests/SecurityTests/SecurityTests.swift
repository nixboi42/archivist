import Domain
import Foundation
import Testing
@testable import ArchiveSecurity

@Test(arguments: ["../evil", "../../evil", "foo/../../../evil", "/etc/passwd", "////etc/passwd", "C:\\Windows\\System32\\foo", "C:/Windows/System32/foo", "\\\\server\\share\\foo", "//server/share/foo", "..\\..\\evil", "../..\\foo"])
func rejectsUnsafePaths(_ path: String) { #expect(throws: ArchiveSecurityError.self) { try PathValidator().validate(path) } }

@Test(arguments: ["file.txt", "folder/file.txt", "folder/subfolder/file", "Türkçe/çalışma.txt", "日本語/資料.txt", "emoji/📦.txt"])
func acceptsInternationalSafePaths(_ path: String) throws { #expect(try PathValidator().validate(path).string == path.precomposedStringWithCanonicalMapping) }

@Test func normalizesDotAndRedundantSeparators() throws {
    #expect(try PathValidator().validate("./foo").string == "foo")
    #expect(try PathValidator().validate("foo/./bar//").string == "foo/bar")
}

@Test func unicodeCollisionsAreDetectedButTurkishLettersRemainDistinct() throws {
    var tracker = UnicodeCollisionTracker(); let validator = PathValidator()
    try tracker.insert(original: "é.txt", normalized: try validator.validate("é.txt"))
    #expect(throws: ArchiveSecurityError.self) { try tracker.insert(original: "e\u{301}.txt", normalized: try validator.validate("e\u{301}.txt")) }
    var turkish = UnicodeCollisionTracker()
    try turkish.insert(original: "I.txt", normalized: try validator.validate("I.txt"))
    try turkish.insert(original: "ı.txt", normalized: try validator.validate("ı.txt"))
}

@Test func symlinkContainmentUsesLinkParent() throws {
    let v = PathValidator(), policy = SymlinkPolicy()
    #expect(try policy.validate(target: "file", symlinkPath: v.validate("dir/link")).path.string == "dir/file")
    #expect(try policy.validate(target: "../file", symlinkPath: v.validate("dir/link")).path.string == "file")
    #expect(throws: ArchiveSecurityError.self) { try policy.validate(target: "../../outside", symlinkPath: v.validate("dir/link")) }
    #expect(throws: ArchiveSecurityError.self) { try policy.validate(target: "/etc/passwd", symlinkPath: v.validate("link")) }
}

@Test func hardlinksSupportDeferredInternalTargets() throws {
    let policy = HardlinkPolicy(), target = try PathValidator().validate("later/file")
    #expect(try policy.validate(target: "later/file", knownPaths: []).requiresDeferredMaterialization)
    #expect(!((try policy.validate(target: "later/file", knownPaths: [target])).requiresDeferredMaterialization))
    #expect(throws: ArchiveSecurityError.self) { try policy.validate(target: "../outside", knownPaths: []) }
    #expect(throws: ArchiveSecurityError.self) { try policy.validate(target: "/etc/file", knownPaths: []) }
}

@Test func bombDetectionSupportsPreflightAndStreaming() throws {
    let limits = SecurityPolicy.ResourceLimits(maximumEntries: 100, maximumExpandedBytes: 1_000_000, maximumCompressionRatio: 100)
    let detector = BombDetector(limits: limits)
    try detector.preflight(.init(entryCount: 10, uncompressedBytes: 500_000, compressedBytes: 10_000))
    #expect(throws: ArchiveSecurityError.self) { try detector.preflight(.init(entryCount: 101)) }
    #expect(throws: ArchiveSecurityError.self) { try detector.preflight(.init(uncompressedBytes: 1_000_001)) }
    #expect(throws: ArchiveSecurityError.self) { try detector.preflight(.init(uncompressedBytes: 100_000, compressedBytes: 1)) }
    try detector.preflight(.init())
    var state = BombDetector.State()
    try detector.observeEntry(state: &state, uncompressedBytes: nil, compressedBytes: nil)
    try detector.observeProducedBytes(900_000, state: &state)
    #expect(throws: ArchiveSecurityError.self) { try detector.observeProducedBytes(100_001, state: &state) }
}

@Test func largeLegitimateArchiveFitsDefaultPolicy() throws {
    try BombDetector(limits: SecurityPolicy.secureDefault.resourceLimits).preflight(.init(entryCount: 1_000, uncompressedBytes: 200 * 1_024 * 1_024 * 1_024, compressedBytes: 100 * 1_024 * 1_024 * 1_024))
}

@Test func diskAssessmentAccountsForTemporaryOverhead() {
    let limiter = ResourceLimiter()
    #expect(limiter.assess(requiredOutputBytes: 800, resources: .init(availableDiskBytes: 1_000, temporaryOverheadBytes: 100)) == .sufficient)
    #expect(limiter.assess(requiredOutputBytes: 950, resources: .init(availableDiskBytes: 1_000, temporaryOverheadBytes: 100)) == .insufficient(required: 1_050, available: 1_000))
    #expect(limiter.assess(requiredOutputBytes: nil, resources: .init(availableDiskBytes: 1_000)) == .unknown)
}

@Test func plannerDetectsCollisionAndBuildsContainedURLs() throws {
    let root = URL(fileURLWithPath: "/tmp/extract", isDirectory: true)
    let plan = try SecureExtractionPlanner().plan(destinationRoot: root, entries: [.init(path: "folder/file", kind: .regularFile, uncompressedSize: 1)])
    #expect(plan[0].destinationURL.path == "/tmp/extract/folder/file")
    #expect(throws: ArchiveSecurityError.self) { try SecureExtractionPlanner().plan(destinationRoot: root, entries: [.init(path: "é", kind: .regularFile), .init(path: "e\u{301}", kind: .regularFile)]) }
}

@Test func generatedNormalizationPropertiesHold() throws {
    let validator = PathValidator()
    for a in ["a", "Türkçe", "日本語", "📦"] {
        for b in ["file", "sub", "é"] {
            let accepted = try validator.validate("./\(a)//\(b)")
            #expect(!accepted.string.hasPrefix("/")); #expect(!accepted.components.contains(".."))
            #expect(try validator.validate(accepted.string) == accepted)
        }
    }
}

@Test func hardSafetyAndPolicyAreStructurallyDistinct() {
    do { _ = try PathValidator().validate("/etc") } catch let error as ArchiveSecurityError { #expect(error.level == .hardSafety) } catch { Issue.record(error) }
    do { _ = try PathValidator().validate("../etc") } catch let error as ArchiveSecurityError { #expect(error.level == .policy) } catch { Issue.record(error) }
}
