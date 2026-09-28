import XCTest
@testable import StorageCore

final class StorageCoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".disklens-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }
    @discardableResult
    func file(_ path: String, content: String = "test file content") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }
    func scan() throws -> ScanResult {
        try DiskScanner(minimumItemBytes: 1).scan(root)
    }
    func setModified(_ url: URL, to date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
    func testClassificationAndAggregation() throws {
        try file("repo/node_modules/package/index.js")
        try file("repo/node_modules/package/assets.zip")
        try file("repo/.git/objects/pack/large.pack")
        try file("Downloads/installer.dmg")
        try file("Documents/proposal.pdf")
        let result = try scan()
        XCTAssertEqual(result.fileCount, 4)
        XCTAssertEqual(result.items.filter { $0.kind == .build }.count, 1)
        XCTAssertEqual(result.items.filter { $0.kind == .installer }.count, 1)
        XCTAssertEqual(result.items.filter { $0.kind == .large }.count, 1)
        XCTAssertFalse(result.items.contains { $0.url.path.contains("/.git/") })
        XCTAssertEqual(result.groups.reduce(0) { $0 + $1.bytes }, result.totalBytes)
        XCTAssertEqual(result.suggestions.count, 2)
    }
    func testSymlinkIsNeverFollowed() throws {
        let data = try file("real/data.zip")
        let link = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: data.deletingLastPathComponent())
        let result = try scan()
        XCTAssertEqual(result.fileCount, 1)
        XCTAssertFalse(result.items.contains { $0.url.path.contains("/alias/") })
        XCTAssertThrowsError(try PathPolicy.validateForTrash(link.appendingPathComponent("data.zip"), root: root))
    }
    func testHardLinksCountOnceAndAreNotOffered() throws {
        let original = try file("one.bin")
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("two.bin"))
        let result = try scan()
        XCTAssertEqual(result.fileCount, 1)
        XCTAssertEqual(result.items.count, 0)
    }
    func testSensitiveDataIsProtected() {
        for path in [
            "/System/Library/a.zip", "/Applications/Foo.app/data.zip",
            "/Users/person/Documents/Photos.photoslibrary/original.zip",
            "/Users/person/Library/Application Support/App/data.zip",
            "/Users/person/project/.git/objects/pack.zip",
            "/Users/person/.Trash/old.zip",
            "/private/var/data.zip"
        ] {
            XCTAssertTrue(PathPolicy.protected(URL(fileURLWithPath: path)), path)
        }
        XCTAssertFalse(PathPolicy.protected(URL(fileURLWithPath: "/Users/person/Downloads/test.dmg")))
        XCTAssertFalse(PathPolicy.protected(URL(fileURLWithPath: "/Users/person/Library/Caches/app/cache.bin")))
    }
    func testBreadcrumbsResolveHomeAndParentFolders() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let target = home.appendingPathComponent("Documents/Projects/example")
        let crumbs = StorageFormat.breadcrumbs(target)

        XCTAssertEqual(crumbs.map { $0.title }, ["~", "Documents", "Projects", "example"])
        XCTAssertEqual(crumbs.map { $0.url.path }, [
            home,
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Documents/Projects"),
            target
        ].map(\.path))
    }
    func testBreadcrumbsOutsideHomeStartAtFilesystemRoot() {
        let target = URL(fileURLWithPath: "/Volumes/External/project", isDirectory: true)
        let crumbs = StorageFormat.breadcrumbs(target)

        XCTAssertEqual(crumbs.map { $0.title }, ["/", "Volumes", "External", "project"])
        XCTAssertEqual(crumbs.last?.url, target)
    }
    func testPresentationsRemainVisibleAsLargeFilesWithoutCleanupSuggestions() throws {
        try file("Work/Docs/presentation.pptx")
        try file("Work/Docs/legacy.ppt")
        try file("Work/Docs/report.pdf")
        let result = try scan()
        XCTAssertTrue(result.suggestions.isEmpty)
        XCTAssertEqual(result.largeFiles.count, 3)
        XCTAssertEqual(Set(result.largeFiles.map(\.name)), ["presentation.pptx", "legacy.ppt", "report.pdf"])
        XCTAssertTrue(result.largeFiles.allSatisfy { $0.kind == .large })
    }
    func testOldLargeDocumentIsSuggestedAndStillListedAsLargeFile() throws {
        let referenceDate = Date()
        let oldDate = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -2, to: referenceDate))
        let document = try file("Documents/old-report.pptx")
        try setModified(document, to: oldDate)

        let result = try DiskScanner(minimumItemBytes: 1, referenceDate: referenceDate).scan(root)

        XCTAssertEqual(result.suggestions.map(\.url), [document])
        XCTAssertEqual(result.suggestions.first?.kind, .stale)
        XCTAssertEqual(result.largeFiles.map(\.url), [document])
        XCTAssertEqual(result.largeFiles.first?.modified.timeIntervalSince1970 ?? 0,
                       oldDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertNotNil(result.largeFiles.first?.created)
    }
    func testOldDirectoryRequiresEveryDescendantToBeOld() throws {
        let referenceDate = Date()
        let oldDate = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -2, to: referenceDate))
        let oldFile = try file("archive/nested/old.bin", content: String(repeating: "x", count: 16_384))
        let directory = root.appendingPathComponent("archive")
        try setModified(oldFile, to: oldDate)
        try setModified(oldFile.deletingLastPathComponent(), to: oldDate)
        try setModified(directory, to: oldDate)

        var result = try DiskScanner(minimumItemBytes: 8_000, referenceDate: referenceDate).scan(root)
        XCTAssertEqual(result.suggestions.map(\.url), [directory])
        XCTAssertEqual(result.items.first { $0.url == directory }?.latestModified.timeIntervalSince1970 ?? 0,
                       oldDate.timeIntervalSince1970, accuracy: 1)

        let recentFile = try file("archive/nested/recent.bin")
        result = try DiskScanner(minimumItemBytes: 8_000, referenceDate: referenceDate).scan(root)
        XCTAssertFalse(result.items.contains { $0.url == directory })
        XCTAssertEqual(result.suggestions.map(\.url), [oldFile])
        XCTAssertTrue(result.groups.contains { $0.url == directory && $0.latestModified! > oldDate })
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentFile.path))
    }
    func testSkippedGitPreventsOldDirectorySuggestion() throws {
        let referenceDate = Date()
        let oldDate = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -2, to: referenceDate))
        let document = try file("archive/old.bin")
        try file("archive/.git/objects/pack")
        let directory = root.appendingPathComponent("archive")
        try setModified(document, to: oldDate)
        try setModified(directory, to: oldDate)

        let result = try DiskScanner(minimumItemBytes: 1, referenceDate: referenceDate).scan(root)

        XCTAssertFalse(result.items.contains { $0.url == directory })
        XCTAssertEqual(result.suggestions.map(\.url), [document])
        XCTAssertGreaterThan(result.skippedCount, 0)
    }
    func testScanRootIsNeverSuggestedAsOldDirectory() throws {
        let referenceDate = Date()
        let oldDate = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -2, to: referenceDate))
        let document = try file("old.bin")
        try setModified(document, to: oldDate)
        try setModified(root, to: oldDate)

        let result = try DiskScanner(minimumItemBytes: 1, referenceDate: referenceDate).scan(root)

        XCTAssertEqual(result.suggestions.map(\.url), [document])
    }
    func testProtectedBundlesAreCountedButNotOffered() throws {
        try file("App.app/Contents/archive.zip")
        try file("Photos.photoslibrary/originals/photo.zip")
        let result = try scan()
        XCTAssertEqual(result.fileCount, 2)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertGreaterThan(result.totalBytes, 0)
    }
    func testAggregateContainingGitRepositoryIsNotOffered() throws {
        try file("node_modules/package/.git/objects/data")
        try file("node_modules/package/index.js")
        XCTAssertTrue(try scan().items.isEmpty)
    }
    func testRustTargetRequiresManifest() throws {
        let target = try file("repo/target/debug/program").deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertNil(PathPolicy.kind(for: target, isDirectory: true))
        try file("repo/Cargo.toml")
        XCTAssertEqual(PathPolicy.kind(for: target, isDirectory: true), .build)
    }
    func testRootAndSiblingCannotBeTrashed() throws {
        XCTAssertThrowsError(try PathPolicy.validateForTrash(root, root: root))
        XCTAssertThrowsError(try PathPolicy.validateForTrash(URL(fileURLWithPath: root.path + "-sibling/file"), root: root))
        XCTAssertThrowsError(try PathPolicy.validateForTrash(root.appendingPathComponent("../outside.zip"), root: root))
    }
    func testUnchangedItemCanBeTrashedThroughInjectedOperation() throws {
        let target = try file("installer.dmg")
        let item = try XCTUnwrap(scan().items.first)
        var called: [URL] = []
        let report = TrashService.move([item], root: root) { url in called.append(url) }
        XCTAssertEqual(called, [target])
        XCTAssertEqual(report.moved, [target.path])
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }
    func testChangedFileIsRejected() throws {
        let url = try file("installer.dmg")
        let item = try XCTUnwrap(scan().items.first)
        try Data("changed file with different contents and size".utf8).write(to: url)
        let report = TrashService.move([item], root: root) { _ in XCTFail("Must never trash a changed file") }
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(report.moved.isEmpty)
    }
    func testChangesInsideDirectoryAreRejected() throws {
        let child = try file("node_modules/inside/file.js")
        let item = try XCTUnwrap(scan().items.first)
        try Data("new content and size".utf8).write(to: child)
        let report = TrashService.move([item], root: root) { _ in XCTFail("Must not trash changed contents") }
        XCTAssertEqual(report.failures.count, 1)
    }
    func testUnchangedDirectoryFingerprintMatches() throws {
        try file("node_modules/pkg/file.js")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("node_modules/bin"),
            withDestinationURL: root.appendingPathComponent("node_modules/pkg"))
        let item = try XCTUnwrap(scan().items.first)
        XCTAssertEqual(try DiskScanner.fingerprint(at: item.url), item.fingerprint)
    }
    func testReplacedAncestorSymlinkIsRejected() throws {
        try file("parent/file.zip")
        let item = try XCTUnwrap(scan().items.first)
        try FileManager.default.moveItem(at: root.appendingPathComponent("parent"), to: root.appendingPathComponent("relocated"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("parent"),
                                                  withDestinationURL: root.appendingPathComponent("relocated"))
        let report = TrashService.move([item], root: root) { _ in XCTFail("Must reject replaced ancestor") }
        XCTAssertEqual(report.failures.count, 1)
    }
    func testParentChildSelectionDoesNotDoubleCount() throws {
        try file("node_modules/package/archive.zip")
        let parent = try XCTUnwrap(scan().items.first)
        let childScan = try DiskScanner(minimumItemBytes: 1).scan(root.appendingPathComponent("node_modules/package"))
        let child = try XCTUnwrap(childScan.items.first)
        XCTAssertEqual(PathPolicy.coalesced([child, parent, parent]).map(\.id), [parent.id])
    }
    func testDuplicateDetectionUsesContentNotOnlySize() throws {
        try file("one.bin", content: "identical data")
        try file("two.bin", content: "identical data")
        try file("other.bin", content: "different data")
        let duplicates = try DuplicateFinder.find(in: scan().items)
        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(Set(duplicates[0].items.map(\.name)), Set(["one.bin", "two.bin"]))
    }
    func testDuplicateFinderSkipsChangedFile() throws {
        try file("one.bin", content: "identical data")
        let second = try file("two.bin", content: "identical data")
        let result = try scan()
        try Data("changed".utf8).write(to: second)
        XCTAssertTrue(try DuplicateFinder.find(in: result.items).isEmpty)
    }
    func testPartialTrashFailureIsReportedPerItem() throws {
        try file("one.zip")
        try file("two.zip")
        let items = try scan().items
        let report = TrashService.move(items, root: root) { url in
            if url.lastPathComponent == "one.zip" { throw StorageError.unreadable(url.path) }
        }
        XCTAssertEqual(report.moved.count, 1)
        XCTAssertEqual(report.failures.count, 1)
    }
    func testMissingAndFileRootRejected() throws {
        let file = try file("file.txt")
        XCTAssertThrowsError(try DiskScanner().scan(file))
        XCTAssertThrowsError(try DiskScanner().scan(root.appendingPathComponent("missing")))
    }
    func testQuickScanKeepsSmallFilesOutOfCandidatesButCountsTheirSpace() throws {
        for i in 0..<100 { try file("small-\(i).zip") }
        let result = try DiskScanner().scan(root)
        XCTAssertEqual(result.fileCount, 100)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertTrue(result.groups[0].isRemainder)
        XCTAssertEqual(result.groups[0].bytes, result.totalBytes)
    }
    func testManySmallDependenciesCanProduceOneLargeDirectoryCandidate() throws {
        for i in 0..<10 { try file("node_modules/pkg/file-\(i).js") }
        let result = try DiskScanner(minimumItemBytes: 20_000).scan(root)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].name, "node_modules")
        XCTAssertGreaterThanOrEqual(result.items[0].bytes, 20_000)
    }
    func testGitWorktreeMarkerProtectsAggregate() throws {
        try file(".build/worktree/.git", content: "gitdir: /somewhere")
        try file(".build/worktree/source.swift")
        let result = try scan()
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.skippedCount, 1)
    }
    func testNativeScanDoesNotChangeCurrentWorkingDirectory() throws {
        try file("nested/sub/file.zip")
        let before = FileManager.default.currentDirectoryPath
        _ = try scan()
        XCTAssertEqual(FileManager.default.currentDirectoryPath, before)
    }
    func testProgressStreamsUsablePartialResultsBeforeCompletion() throws {
        try file("node_modules/pkg/index.js")
        try file("archive.zip")
        let log = ProgressLog()
        var scanner = DiskScanner(minimumItemBytes: 1)
        scanner.progressInterval = 0
        let result = try scanner.scan(root) { log.append($0) }
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(log.values.contains { $0.partial?.items.isEmpty == false })
        for update in log.values {
            if let partial = update.partial {
                XCTAssertFalse(partial.isComplete)
                XCTAssertEqual(partial.groups.reduce(0) { $0 + $1.bytes }, partial.totalBytes)
            }
        }
        XCTAssertNil(log.values.last?.partial)
        XCTAssertEqual(log.values.last?.bytes, result.totalBytes)
    }
    func testCancellation() async throws {
        for i in 0..<30 { try file("folder\(i)/file.zip") }
        let target = root!
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DiskScanner().scan(target)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled scans must throw")
        } catch is CancellationError {
            // Expected.
        }
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [ScanProgress] = []
    var values: [ScanProgress] {
        lock.lock()
        defer { lock.unlock() }
        return updates
    }
    func append(_ progress: ScanProgress) {
        lock.lock()
        defer { lock.unlock() }
        updates.append(progress)
    }
}
