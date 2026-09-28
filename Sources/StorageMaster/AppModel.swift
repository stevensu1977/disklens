import SwiftUI
import AppKit
import StorageCore

enum Page: String, CaseIterable, Identifiable {
    case overview = "空间概览", cleanup = "清理建议", large = "大文件", duplicates = "重复文件"
    var id: String { rawValue }
    var title: String { L10n.string(rawValue) }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .cleanup: "sparkles"
        case .large: "doc.zipper"
        case .duplicates: "square.on.square"
        }
    }
    var subtitle: String {
        let key: String = switch self {
        case .overview: "看清空间去向，让 Mac 轻装上阵。"
        case .cleanup: "从可再生的文件开始，把空间留给重要的事。"
        case .large: "找出占据空间的大块头，逐个确认是否还需要。"
        case .duplicates: "比对文件内容，找出多余的一份。"
        }
        return L10n.string(key)
    }
}

@MainActor
@Observable
final class AppModel {
    var page: Page = .overview
    var language = AppLanguage.saved
    var root = StandardScanLocation.defaultRoot
    var capacity: DiskCapacity?
    var result: ScanResult?
    var scanning = false
    var hashing = false
    var hashProgress = ""
    var progress = ScanProgress(count: 0, bytes: 0, path: "")
    var selection = Set<String>()
    var search = ""
    var filter: CleanupKind?
    var minimumSize: Int64 = 100_000_000
    var sortNewest = false
    var duplicates: [DuplicateGroup] = []
    var duplicatesFinished = false
    var showTrashConfirmation = false
    var showPermissions = false
    var showScanIssues = false
    var showFolders = false
    var cleaning = false
    var notice: String?
    var error: String?
    var detail: ScanItem?
    var history: [URL] = []
    private var scanTask: Task<Void, Never>?
    private var hashTask: Task<Void, Never>?
    private var generation = UUID()

    init() {
        capacity = DiskCapacity.read(at: root)
    }
    var busy: Bool { scanning || hashing || cleaning }
    var selectedItems: [ScanItem] { PathPolicy.coalesced((result?.items ?? []).filter { selection.contains($0.id) }) }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var largeFileCount: Int { result?.largeFiles.count ?? 0 }
    var visibleItems: [ScanItem] {
        let source = result?.items ?? []
        let items = source.filter { item in
            let pageMatch = page == .large ? (!item.isDirectory && item.logicalBytes >= minimumSize) : item.kind != .large
            let filterMatch = filter == nil || item.kind == filter
            let searchMatch = search.isEmpty || item.name.localizedCaseInsensitiveContains(search) || item.url.path.localizedCaseInsensitiveContains(search)
            return pageMatch && filterMatch && searchMatch
        }
        let visible = page == .large ? items : PathPolicy.coalesced(items)
        return visible.sorted {
            sortNewest ? $0.latestModified > $1.latestModified : $0.bytes > $1.bytes
        }
    }
    func navigate(_ page: Page) {
        self.page = page
        search = ""
        filter = nil
    }
    func setLanguage(_ value: AppLanguage) {
        guard language != value else { return }
        UserDefaults.standard.set(value.rawValue, forKey: AppLanguage.preferenceKey)
        language = value
        notice = nil
        if hashing { hashProgress = L10n.string("正在筛选同体积文件…") }
    }
    func chooseFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.string("选择要分析的文件夹")
        panel.prompt = L10n.string("开始扫描")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = root
        if panel.runModal() == .OK, let url = panel.url {
            navigate(.overview)
            scan(url)
        }
    }
    func scan(_ url: URL? = nil, addHistory: Bool = true) {
        guard !cleaning else { return }
        scanTask?.cancel()
        hashTask?.cancel()
        hashing = false
        if let url, url != root, addHistory { history.append(root) }
        root = (url ?? root).standardizedFileURL.resolvingSymlinksInPath()
        capacity = DiskCapacity.read(at: root)
        result = nil
        duplicates = []
        duplicatesFinished = false
        selection.removeAll()
        notice = nil
        error = nil
        scanning = true
        progress = ScanProgress(count: 0, bytes: 0, path: root.path)
        let token = UUID()
        generation = token
        let target = root
        let threshold = minimumSize
        scanTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                try DiskScanner(minimumItemBytes: threshold).scan(target) { update in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token, self.scanning else { return }
                        self.progress = update
                        if let partial = update.partial { self.result = partial }
                    }
                }
            }
            do {
                let scanned = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                guard generation == token, !Task.isCancelled else { return }
                result = scanned
                scanning = false
                capacity = DiskCapacity.read(at: target)
            } catch {
                guard generation == token else { return }
                scanning = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func cancel() {
        scanTask?.cancel()
        hashTask?.cancel()
        generation = UUID()
        scanning = false
        hashing = false
        notice = result == nil ? L10n.string("已停止。你可以重新选择文件夹并扫描。") :
            L10n.string("已停止扫描，并保留已找到的结果。当前数字只代表已扫描部分，可以先检查这些大项目。")
    }
    func goBack() {
        guard let previous = history.popLast() else { return }
        scan(previous, addHistory: false)
    }
    func openAncestor(_ url: URL) {
        guard !busy else { return }
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        guard target.path != root.path, PathPolicy.contains(target, root) else { return }
        navigate(.overview)
        if let index = history.lastIndex(where: { $0.standardizedFileURL.path == target.path }) {
            history.removeSubrange(index..<history.endIndex)
            scan(target, addHistory: false)
        } else {
            scan(target)
        }
    }
    func findDuplicates() {
        guard let result, !busy else { return }
        hashing = true
        hashProgress = L10n.string("正在筛选同体积文件…")
        let token = generation
        hashTask = Task {
            let worker = Task.detached(priority: .utility) {
                try DuplicateFinder.find(in: result.items) { done, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token, self.hashing else { return }
                        self.hashProgress = L10n.format("已比对 %d / %d 个文件", done, total)
                    }
                }
            }
            do {
                let found = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                guard generation == token, !Task.isCancelled else { return }
                duplicates = found
                duplicatesFinished = true
                hashing = false
            } catch {
                guard generation == token else { return }
                hashing = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func toggle(_ item: ScanItem) {
        if selection.contains(item.id) { selection.remove(item.id) }
        else { selection.insert(item.id) }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func refreshCapacity() { capacity = DiskCapacity.read(at: root) }
    func trashSelected() {
        guard !selectedItems.isEmpty, let result, !busy else { return }
        let items = selectedItems
        let root = result.root
        cleaning = true
        showTrashConfirmation = false
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                TrashService.move(items, root: root)
            }.value
            cleaning = false
            let updated = result.applyingTrash(report)
            self.result = updated
            duplicates = updated.retainingDuplicateGroups(duplicates)
            let retainedIDs = Set(updated.items.map(\.id))
            selection.formIntersection(retainedIDs)
            if let detail, !retainedIDs.contains(detail.id) { self.detail = nil }
            progress = ScanProgress(count: updated.fileCount, bytes: updated.totalBytes, path: root.path)
            // Refresh just the volume counters. Moving to Trash does not free its blocks.
            capacity = DiskCapacity.read(at: root)
            notice = report.moved.isEmpty ? L10n.string("没有文件移入废纸篓，原有结果已保留。") :
                L10n.format("已将 %d 项（%@）移到废纸篓，列表与占用已更新。清空废纸篓后才会释放空间。",
                            report.moved.count, StorageFormat.bytes(report.bytes))
            error = report.failures.isEmpty ? nil : report.failures.joined(separator: "\n")
        }
    }
}
