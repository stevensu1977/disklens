import Foundation

public struct TrashReport: Sendable {
    public var moved: [String] = []
    public var failures: [String] = []
    public var bytes: Int64 = 0
}

public enum TrashService {
    /// No permanent-delete API. The UI must obtain explicit confirmation before calling this.
    public static func move(_ items: [ScanItem], root: URL,
                            trash: (URL) throws -> Void = { url in
                                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                            }) -> TrashReport {
        var report = TrashReport()
        for item in PathPolicy.coalesced(items) {
            do {
                try PathPolicy.validateForTrash(item.url, root: root)
                guard try DiskScanner.fingerprint(at: item.url) == item.fingerprint else {
                    throw StorageError.changed(item.url.path)
                }
                try PathPolicy.validateForTrash(item.url, root: root)
                try trash(item.url)
                report.moved.append(item.id)
                report.bytes += item.bytes
            } catch {
                report.failures.append(error.localizedDescription)
            }
        }
        return report
    }
}
