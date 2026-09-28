import Foundation
import CryptoKit
import StorageTraversal

/// A native metadata walk. Small files never become Swift objects or cleanup records.
public struct DiskScanner: Sendable {
    public var minimumItemBytes: Int64
    public var skipGit: Bool
    public var staleBefore: Date
    var progressInterval: TimeInterval = 0.4
    public init(minimumItemBytes: Int64 = 100_000_000, skipGit: Bool = true, referenceDate: Date = Date()) {
        self.minimumItemBytes = minimumItemBytes
        self.skipGit = skipGit
        self.staleBefore = CleanupAgePolicy.cutoff(relativeTo: referenceDate)
    }
    public func scan(_ root: URL, progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) throws -> ScanResult {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw StorageError.invalidRoot
        }
        let collector = ScanCollector(root: root, minimum: minimumItemBytes, staleBefore: staleBefore,
                                      interval: progressInterval, progress: progress)
        let pointer = Unmanaged.passUnretained(collector).toOpaque()
        let status = root.path.withCString {
            sm_walk($0, minimumItemBytes, skipGit ? 1 : 0, { entry, pointer in
                guard let entry, let pointer else { return 1 }
                if Task.isCancelled { return 1 }
                return autoreleasepool {
                    Unmanaged<ScanCollector>.fromOpaque(pointer).takeUnretainedValue().receive(entry.pointee)
                    return 0
                }
            }, pointer)
        }
        if status == 1 { throw CancellationError() }
        if status != 0 { throw StorageError.unreadable(root.path) }
        let remainder = collector.bytes - collector.groups.reduce(0) { $0 + $1.bytes }
        if remainder > 0 {
            collector.groups.append(DiskGroup(url: root, bytes: remainder, isDirectory: false, isRemainder: true))
        }
        progress(ScanProgress(count: collector.count, bytes: collector.bytes, path: root.path))
        return ScanResult(root: root, items: collector.items.sorted { $0.bytes > $1.bytes },
                          groups: collector.groups.sorted { $0.bytes > $1.bytes },
                          totalBytes: collector.bytes, fileCount: collector.count,
                          skippedCount: collector.skipped, issues: collector.issues,
                          finishedAt: Date(), elapsed: Date().timeIntervalSince(collector.start),
                          minimumItemBytes: minimumItemBytes)
    }
    /// The same native metadata digest verifies descendant identity and change times before trashing.
    public static func fingerprint(at url: URL) throws -> String {
        let sink = FingerprintSink()
        let pointer = Unmanaged.passUnretained(sink).toOpaque()
        let status = url.path.withCString {
            sm_walk($0, Int64.max, 0, { entry, pointer in
                guard let entry, let pointer else { return 1 }
                if Task.isCancelled { return 1 }
                let sink = Unmanaged<FingerprintSink>.fromOpaque(pointer).takeUnretainedValue()
                let value = entry.pointee
                if value.kind == SM_ISSUE { sink.complete = false }
                if value.depth == 0 && (value.kind == SM_FILE || value.kind == SM_LEAVE) {
                    sink.value = metadataDigest(value)
                    sink.complete = sink.complete && value.complete != 0
                }
                return 0
            }, pointer)
        }
        if status == 1 { throw CancellationError() }
        guard status == 0, sink.complete, let value = sink.value else { throw StorageError.unreadable(url.path) }
        return value
    }
}

private final class FingerprintSink {
    var value: String?
    var complete = true
}
private func metadataDigest(_ entry: SMEntry) -> String {
    let alphabet = Array("0123456789abcdef".utf8)
    return withUnsafeBytes(of: entry.digest) { bytes in
        var output = [UInt8]()
        output.reserveCapacity(64)
        for byte in bytes { output.append(alphabet[Int(byte >> 4)]); output.append(alphabet[Int(byte & 15)]) }
        return String(decoding: output, as: UTF8.self)
    }
}
private func fileStamp(_ entry: SMEntry) -> FileStamp {
    FileStamp(device: entry.device, inode: entry.inode, logicalBytes: entry.logical_bytes,
              modified: Date(timeIntervalSince1970: entry.modified),
              created: entry.created == 0 ? nil : Date(timeIntervalSince1970: entry.created))
}

private final class ScanCollector {
    struct Frame {
        let url: URL
        let stamp: FileStamp
        let kind: CleanupKind?
        let covered: Bool
        let aggregate: Bool
        var safe: Bool
    }
    let root: URL
    let minimum: Int64
    let staleBefore: Date
    let interval: TimeInterval
    let start = Date()
    let progress: @Sendable (ScanProgress) -> Void
    var lastProgress = Date.distantPast
    var frames: [Frame] = []
    var items: [ScanItem] = []
    var groups: [DiskGroup] = []
    var count = 0
    var bytes: Int64 = 0
    var skipped = 0
    var issues: [String] = []
    init(root: URL, minimum: Int64, staleBefore: Date, interval: TimeInterval, progress: @escaping @Sendable (ScanProgress) -> Void) {
        self.root = root; self.minimum = minimum; self.staleBefore = staleBefore
        self.interval = interval; self.progress = progress
    }
    func receive(_ entry: SMEntry) {
        count = Int(entry.file_count)
        bytes = entry.total_bytes
        switch Int(entry.kind) {
        case SM_ENTER:
            let url = URL(fileURLWithPath: String(cString: entry.path))
            let covered = frames.last.map { $0.covered || $0.aggregate } ?? false
            let kind = PathPolicy.kind(for: url, isDirectory: true)
            frames.append(Frame(url: url, stamp: fileStamp(entry), kind: kind, covered: covered,
                                aggregate: kind != nil && !covered && entry.depth > 0,
                                safe: !PathPolicy.protected(url)))
        case SM_LEAVE:
            guard let frame = frames.popLast() else { return }
            if !frame.safe, !frames.isEmpty { frames[frames.count - 1].safe = false }
            let latestModified = Date(timeIntervalSince1970: entry.latest_modified)
            let staleDirectory = frame.safe && entry.complete != 0 && entry.bytes >= minimum &&
                !frame.covered && !frame.aggregate && entry.depth > 0 &&
                latestModified < staleBefore && !PathPolicy.isEssentialDirectory(frame.url)
            if frame.safe, entry.complete != 0, entry.bytes >= minimum,
               frame.aggregate || staleDirectory {
                // Retain child candidates for searches, category filters and incremental cleanup.
                // Suggestion and selection totals coalesce overlapping paths.
                let kind = frame.kind ?? .stale
                items.append(ScanItem(url: frame.url, bytes: entry.bytes, logicalBytes: entry.bytes, kind: kind,
                                      isDirectory: true, modified: frame.stamp.modified,
                                      stamp: frame.stamp, fingerprint: metadataDigest(entry),
                                      fileCount: Int(entry.subtree_file_count),
                                      latestContentModification: latestModified))
            }
            if entry.depth == 1, entry.bytes > 0 {
                groups.append(DiskGroup(url: frame.url, bytes: entry.bytes, isDirectory: true,
                                        modified: frame.stamp.modified, created: frame.stamp.created,
                                        latestContentModification: latestModified))
            }
        case SM_FILE:
            let url = URL(fileURLWithPath: String(cString: entry.path))
            let stamp = fileStamp(entry)
            if entry.depth == 1, entry.bytes > 0 {
                groups.append(DiskGroup(url: url, bytes: entry.bytes, isDirectory: false,
                                        modified: stamp.modified, created: stamp.created))
            }
            let protected = PathPolicy.protected(url)
            if protected, !frames.isEmpty { frames[frames.count - 1].safe = false }
            guard !protected, !(frames.last.map { $0.covered || $0.aggregate } ?? false) else { break }
            items.append(ScanItem(url: url, bytes: entry.bytes, logicalBytes: entry.logical_bytes,
                                  kind: PathPolicy.kind(for: url, isDirectory: false) ??
                                    (stamp.modified < staleBefore ? .stale : .large),
                                  isDirectory: false, modified: stamp.modified,
                                  stamp: stamp, fingerprint: metadataDigest(entry)))
        case SM_ISSUE:
            skipped += 1
            let path = String(cString: entry.path)
            if issues.count < 20 { issues.append(path) }
            if frames.last?.url.path == path { _ = frames.popLast() }
        default: break
        }
        if Date().timeIntervalSince(lastProgress) >= interval {
            lastProgress = Date()
            var snapshotGroups = groups
            let remainder = bytes - groups.reduce(0) { $0 + $1.bytes }
            if remainder > 0 {
                snapshotGroups.append(DiskGroup(url: root, bytes: remainder, isDirectory: false,
                                               isRemainder: true, caption: "尚未细分的空间"))
            }
            let snapshot = ScanResult(root: root, items: items.sorted { $0.bytes > $1.bytes },
                                      groups: snapshotGroups.sorted { $0.bytes > $1.bytes },
                                      totalBytes: bytes, fileCount: count, skippedCount: skipped,
                                      issues: issues, finishedAt: Date(), elapsed: Date().timeIntervalSince(start),
                                      minimumItemBytes: minimum, isComplete: false)
            progress(ScanProgress(count: count, bytes: bytes, path: String(cString: entry.path), partial: snapshot))
        }
    }
}

public enum DuplicateFinder {
    public static func find(in items: [ScanItem], progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) throws -> [DuplicateGroup] {
        let files = items.filter { !$0.isDirectory }
        let batches = Dictionary(grouping: files, by: \.logicalBytes).values.filter { $0.count > 1 }
        let total = batches.reduce(0) { $0 + $1.count }
        var completed = 0
        var result: [DuplicateGroup] = []
        for batch in batches {
            var hashes: [String: [ScanItem]] = [:]
            for item in batch {
                try Task.checkCancellation()
                defer { completed += 1; progress(completed, total) }
                guard (try? DiskScanner.fingerprint(at: item.url)) == item.fingerprint,
                      item.url.resolvingSymlinksInPath().path == item.url.path,
                      let file = try? FileHandle(forReadingFrom: item.url) else { continue }
                var hasher = SHA256()
                do {
                    defer { try? file.close() }
                    while true {
                        try Task.checkCancellation()
                        let bytesRead = try autoreleasepool {
                            let data = try file.read(upToCount: 1_048_576) ?? Data()
                            hasher.update(data: data)
                            return data.count
                        }
                        if bytesRead == 0 { break }
                    }
                    guard try DiskScanner.fingerprint(at: item.url) == item.fingerprint else { continue }
                    let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    hashes[hash, default: []].append(item)
                } catch is CancellationError { throw CancellationError() }
                catch { continue }
            }
            result += hashes.compactMap { hash, entries in
                guard entries.count > 1 else { return nil }
                return DuplicateGroup(id: hash, items: entries.sorted { $0.url.path < $1.url.path })
            }
        }
        return result.sorted { $0.redundantBytes > $1.redundantBytes }
    }
}
