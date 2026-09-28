import Foundation

public enum CleanupKind: String, CaseIterable, Sendable, Identifiable {
    case cache, build, stale, installer, log, large
    public var id: String { rawValue }
    public var title: String {
        let key: String = switch self {
        case .cache: "应用缓存"
        case .build: "构建与依赖"
        case .stale: "长期未修改"
        case .installer: "安装包与归档"
        case .log: "日志文件"
        case .large: "大文件"
        }
        return L10n.string(key)
    }
    public var symbol: String {
        switch self {
        case .cache: "externaldrive.badge.timemachine"
        case .build: "hammer"
        case .stale: "clock.arrow.circlepath"
        case .installer: "shippingbox"
        case .log: "doc.text"
        case .large: "doc"
        }
    }
    public var caution: String {
        let key: String = switch self {
        case .cache: "通常可重新生成。请先退出相关应用；离线缓存可能需要重新下载。"
        case .build: "可重新构建或安装依赖。请先停止构建任务，确认不需要离线使用这些内容。"
        case .stale: "超过一年未修改，可能仍是重要文档、归档或备份。请先检查内容，确认不再需要或已有备份后再清理。"
        case .installer: "确认软件已安装，且不再需要此安装包或归档备份。"
        case .log: "确认不再需要这些日志排查问题，并先退出正在写入日志的应用。"
        case .large: "仅因体积较大而列出，不代表无用。请打开检查内容，确认已有备份或不再需要。"
        }
        return L10n.string(key)
    }
    public var risk: String {
        let key: String = switch self {
        case .cache, .log: "通常可再生"
        case .build: "需重新构建"
        case .installer, .large, .stale: "请人工确认"
        }
        return L10n.string(key)
    }
}

public struct FileStamp: Sendable, Equatable {
    public let device: UInt64
    public let inode: UInt64
    public let logicalBytes: Int64
    public let modified: Date
    public var created: Date? = nil
}

public struct ScanItem: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let bytes: Int64
    public let logicalBytes: Int64
    public let kind: CleanupKind
    public let isDirectory: Bool
    public let modified: Date
    public let stamp: FileStamp
    public let fingerprint: String
    public var fileCount: Int = 1
    public var latestContentModification: Date? = nil
    public var created: Date? { stamp.created }
    public var latestModified: Date { latestContentModification ?? modified }
    public var name: String { url.lastPathComponent }
}

public struct DiskGroup: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public var bytes: Int64
    public let isDirectory: Bool
    public var isRemainder = false
    public var caption: String? = nil
    public var modified: Date? = nil
    public var created: Date? = nil
    public var latestContentModification: Date? = nil
    public var latestModified: Date? { latestContentModification ?? modified }
    public var name: String { caption.map { L10n.string($0) } ?? (isRemainder ? L10n.string("零散小文件") : url.lastPathComponent) }
}

public struct ScanProgress: Sendable {
    public let count: Int
    public let bytes: Int64
    public let path: String
    public let partial: ScanResult?
    public init(count: Int, bytes: Int64, path: String, partial: ScanResult? = nil) {
        self.count = count
        self.bytes = bytes
        self.path = path
        self.partial = partial
    }
}

public struct ScanResult: Sendable {
    public let root: URL
    public var items: [ScanItem]
    public var groups: [DiskGroup]
    public var totalBytes: Int64
    public var fileCount: Int
    public let skippedCount: Int
    public let issues: [String]
    public let finishedAt: Date
    public let elapsed: TimeInterval
    public let minimumItemBytes: Int64
    public var isComplete = true
    public var cacheUpdatedAt: Date? = nil
    public var suggestions: [ScanItem] { PathPolicy.coalesced(items.filter { $0.kind != .large }) }
    public var largeFiles: [ScanItem] { items.filter { !$0.isDirectory } }
    public var suggestedBytes: Int64 { suggestions.reduce(0) { $0 + $1.bytes } }
}

public enum CleanupAgePolicy {
    public static func cutoff(relativeTo date: Date) -> Date {
        Calendar.current.date(byAdding: .year, value: -1, to: date) ??
            date.addingTimeInterval(-365 * 24 * 60 * 60)
    }
}

public struct DiskCapacity: Sendable {
    public let total: Int64
    public let available: Int64
    public let name: String
    public var used: Int64 { max(0, total - available) }
    public var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    public static func read(at url: URL) -> DiskCapacity? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey
        ]), let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil }
        return DiskCapacity(total: Int64(total), available: Int64(available), name: values.volumeName ?? "Macintosh HD")
    }
}

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String
    public let items: [ScanItem]
    public var redundantBytes: Int64 { items.dropFirst().reduce(0) { $0 + $1.bytes } }
}

public enum StorageError: LocalizedError {
    case invalidRoot, unsafePath(String), changed(String), unreadable(String)
    public var errorDescription: String? {
        switch self {
        case .invalidRoot: L10n.string("请选择一个可读取的文件夹。")
        case .unsafePath(let path): L10n.format("为保护数据，不能清理此路径：%@", path)
        case .changed(let path): L10n.format("文件在扫描后发生变化，请重新扫描：%@", path)
        case .unreadable(let path): L10n.format("无法完整读取，请检查权限：%@", path)
        }
    }
}

public enum StorageFormat {
    public static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
    public static func date(_ value: Date?, includeTime: Bool = false) -> String {
        guard let value else { return "—" }
        return value.formatted(Date.FormatStyle(date: .numeric, time: includeTime ? .shortened : .omitted)
            .locale(AppLanguage.saved.locale))
    }
    public static func path(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path == home { return "~" }
        if url.path.hasPrefix(home + "/") { return "~" + url.path.dropFirst(home.count) }
        return url.path
    }
    public static func breadcrumbs(_ url: URL) -> [(title: String, url: URL)] {
        let target = url.standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        var location = PathPolicy.contains(home, target) ? home : URL(fileURLWithPath: "/", isDirectory: true)
        var result = [(title: location == home ? "~" : "/", url: location)]
        for component in target.pathComponents.dropFirst(location.pathComponents.count) {
            location = location.appendingPathComponent(component, isDirectory: true)
            result.append((title: component, url: location))
        }
        return result
    }
}
