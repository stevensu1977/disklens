import XCTest
@testable import StorageCore

extension StorageCoreTests {
    func testCachedDirectoryRemovalMatchesFreshStatistics() throws {
        try file("project/node_modules/a/index.js")
        try file("project/node_modules/b/index.js")
        try file("project/node_modules/b/metadata.json")
        try file("project/README.md")
        try file("archive.zip")
        let before = try scan()
        let directory = try XCTUnwrap(before.items.first { $0.kind == .build })
        XCTAssertEqual(directory.fileCount, 3)

        // The injected trash operation removes only this test's disposable fixture.
        let report = TrashService.move([directory], root: root) {
            try FileManager.default.removeItem(at: $0)
        }
        let updated = before.applyingTrash(report)
        let fresh = try scan()
        XCTAssertEqual(updated.fileCount, fresh.fileCount)
        XCTAssertEqual(updated.totalBytes, fresh.totalBytes)
        XCTAssertEqual(updated.groups.map(\.bytes), fresh.groups.map(\.bytes))
        XCTAssertEqual(Set(updated.items.map(\.id)), Set(fresh.items.map(\.id)))
        XCTAssertEqual(updated.finishedAt, before.finishedAt)
        XCTAssertNotNil(updated.cacheUpdatedAt)
    }

    func testSequentialCachedCleanupKeepsSiblingFingerprintsUsable() throws {
        try file("project/node_modules/pkg/index.js")
        try file("project/.next/chunk.js")
        try file("project/README.md")
        let before = try scan()
        let first = try XCTUnwrap(before.items.first { $0.name == "node_modules" })
        let sibling = try XCTUnwrap(before.items.first { $0.name == ".next" })
        let report = TrashService.move([first], root: root) {
            try FileManager.default.removeItem(at: $0)
        }
        let updated = before.applyingTrash(report)
        let retained = try XCTUnwrap(updated.items.first { $0.id == sibling.id })
        XCTAssertEqual(retained.fingerprint, sibling.fingerprint)
        let nextReport = TrashService.move([retained], root: root) {
            try FileManager.default.removeItem(at: $0)
        }
        XCTAssertTrue(nextReport.failures.isEmpty)
        XCTAssertEqual(nextReport.moved, [sibling.id])
        let final = updated.applyingTrash(nextReport)
        XCTAssertEqual(final.totalBytes, try scan().totalBytes)
        XCTAssertEqual(final.fileCount, 1)
    }

    func testCachedPartialFailureRemovesOnlyConfirmedMoves() throws {
        try file("one.zip")
        try file("two.zip")
        let before = try scan()
        let report = TrashService.move(before.items, root: root) { url in
            if url.lastPathComponent == "two.zip" { throw StorageError.unreadable(url.path) }
            try FileManager.default.removeItem(at: url)
        }
        let updated = before.applyingTrash(report)
        XCTAssertEqual(updated.items.map(\.name), ["two.zip"])
        XCTAssertEqual(updated.fileCount, 1)
        XCTAssertEqual(updated.totalBytes, try scan().totalBytes)
        XCTAssertEqual(updated.groups.map(\.name), ["two.zip"])
        XCTAssertEqual(report.failures.count, 1)
    }

    func testCachedRemovalIsIdempotentAndIgnoresUnknownIDs() throws {
        try file("one.zip")
        try file("two.zip")
        let before = try scan()
        let item = before.items[0]
        var report = TrashReport()
        report.moved = [item.id, item.id, root.appendingPathComponent("missing.zip").path]
        report.bytes = Int64.max // Cached metadata, not a possibly unrelated report total, drives deltas.
        let updated = before.applyingTrash(report)
        let twice = updated.applyingTrash(report)
        XCTAssertEqual(updated.totalBytes, before.totalBytes - item.bytes)
        XCTAssertEqual(twice.totalBytes, updated.totalBytes)
        XCTAssertEqual(twice.fileCount, updated.fileCount)
        XCTAssertEqual(twice.cacheUpdatedAt, updated.cacheUpdatedAt)
    }

    func testCachedPartialSnapshotSubtractsFromRemainder() throws {
        try file("project/node_modules/pkg/index.js")
        try file("project/README.md")
        var partial = try scan()
        partial.isComplete = false
        partial.groups = [DiskGroup(url: root, bytes: partial.totalBytes, isDirectory: false,
                                    isRemainder: true, caption: "尚未细分的空间")]
        let item = try XCTUnwrap(partial.items.first { $0.kind == .build })
        var report = TrashReport()
        report.moved = [item.id]
        let updated = partial.applyingTrash(report)
        XCTAssertFalse(updated.isComplete)
        XCTAssertEqual(updated.groups[0].bytes, updated.totalBytes)
        XCTAssertEqual(updated.fileCount, 1)
        XCTAssertEqual(updated.groups[0].caption, "尚未细分的空间")
    }

    func testCachedRemovalDoesNotSubtractRemainderTwice() throws {
        try file("project/node_modules/pkg/index.js")
        try file("small.txt")
        var before = try scan()
        let small = try XCTUnwrap(before.groups.first { $0.name == "small.txt" })
        before.groups.removeAll { $0.id == small.id }
        before.groups.append(DiskGroup(url: root, bytes: small.bytes, isDirectory: false, isRemainder: true))
        var report = TrashReport()
        report.moved = [try XCTUnwrap(before.items.first { $0.kind == .build }).id]
        let updated = before.applyingTrash(report)
        XCTAssertEqual(updated.groups.count, 1)
        XCTAssertTrue(updated.groups[0].isRemainder)
        XCTAssertEqual(updated.groups[0].bytes, small.bytes)
        XCTAssertEqual(updated.totalBytes, small.bytes)
    }

    func testCachedDuplicateGroupsShrinkWithoutRehashing() throws {
        try file("one.bin", content: "same content")
        try file("two.bin", content: "same content")
        try file("three.bin", content: "same content")
        let before = try scan()
        let duplicates = try DuplicateFinder.find(in: before.items)
        XCTAssertEqual(duplicates.first?.items.count, 3)
        var report = TrashReport()
        report.moved = [before.items[0].id]
        let updated = before.applyingTrash(report)
        let smaller = updated.retainingDuplicateGroups(duplicates)
        XCTAssertEqual(smaller.first?.items.count, 2)
        XCTAssertEqual(smaller.first?.redundantBytes, before.items[0].bytes)
        report.moved = [updated.items[0].id]
        XCTAssertTrue(updated.applyingTrash(report).retainingDuplicateGroups(smaller).isEmpty)
    }

    func testCachedOverlappingSelectionsAreCountedOnce() throws {
        try file("node_modules/pkg/one.zip")
        try file("node_modules/pkg/two.zip")
        var before = try scan()
        let parent = try XCTUnwrap(before.items.first)
        let children = try DiskScanner(minimumItemBytes: 1).scan(root.appendingPathComponent("node_modules/pkg"))
        before.items += children.items
        var report = TrashReport()
        report.moved = before.items.map(\.id)
        let updated = before.applyingTrash(report)
        XCTAssertEqual(before.totalBytes, parent.bytes)
        XCTAssertEqual(updated.totalBytes, 0)
        XCTAssertEqual(updated.fileCount, 0)
        XCTAssertTrue(updated.items.isEmpty)
        XCTAssertTrue(updated.groups.isEmpty)
    }

    func testCachedChildRemovalInvalidatesOnlyItsContainingCandidate() throws {
        try file("node_modules/pkg/one.zip")
        try file("node_modules/pkg/two.zip")
        try file("unrelated.zip")
        var before = try scan()
        let children = try DiskScanner(minimumItemBytes: 1).scan(root.appendingPathComponent("node_modules/pkg"))
        let child = children.items[0]
        before.items.append(child)
        var report = TrashReport()
        report.moved = [child.id]
        let updated = before.applyingTrash(report)
        XCTAssertEqual(updated.items.map(\.name), ["unrelated.zip"])
        XCTAssertEqual(updated.totalBytes, before.totalBytes - child.bytes)
        XCTAssertEqual(updated.groups.reduce(0) { $0 + $1.bytes }, updated.totalBytes)
    }

    func testFailedCleanupLeavesCachedResultUntouched() throws {
        try file("archive.zip")
        let before = try scan()
        var report = TrashReport()
        report.failures = ["File changed"]
        let updated = before.applyingTrash(report)
        XCTAssertEqual(updated.items.map(\.id), before.items.map(\.id))
        XCTAssertEqual(updated.totalBytes, before.totalBytes)
        XCTAssertEqual(updated.fileCount, before.fileCount)
        XCTAssertNil(updated.cacheUpdatedAt)
    }
}
