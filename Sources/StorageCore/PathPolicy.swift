import Foundation

public enum PathPolicy {
    public static func contains(_ parent: URL, _ child: URL) -> Bool {
        let p = parent.standardizedFileURL.path
        let c = child.standardizedFileURL.path
        return p == c || c.hasPrefix(p == "/" ? "/" : p + "/")
    }

    public static func protected(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let components = url.pathComponents
        let systemRoots = ["/System", "/bin", "/sbin", "/usr", "/private", "/dev", "/Library", "/Applications"]
        if systemRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        if components.contains(where: { $0 == ".git" || $0 == ".Trash" || $0 == ".Trashes" }) { return true }
        if components.contains(where: { component in
            [".app", ".photoslibrary", ".photolibrary", ".musiclibrary", ".backupbundle", ".sparsebundle"].contains { suffix in component.lowercased().hasSuffix(suffix) }
        }) { return true }
        // User Library contains sensitive application data; only documented disposable areas are eligible.
        if let index = components.firstIndex(of: "Library"), index + 1 < components.count {
            let tail = Array(components.dropFirst(index + 1))
            if tail[0] == "Caches" || tail[0] == "Logs" { return false }
            if tail.starts(with: ["Developer", "Xcode", "DerivedData"]) { return false }
            return true
        }
        return false
    }

    public static func kind(for url: URL, isDirectory: Bool) -> CleanupKind? {
        guard !protected(url) else { return nil }
        let parts = url.pathComponents
        if isDirectory {
            if url.deletingLastPathComponent().lastPathComponent == "Caches",
               parts.contains("Library") { return .cache }
            if url.deletingLastPathComponent().lastPathComponent == "DerivedData",
               parts.contains("Xcode") { return .build }
            if ["node_modules", ".build", "__pycache__", ".next", ".nuxt", ".parcel-cache"].contains(url.lastPathComponent) { return .build }
            let parent = url.deletingLastPathComponent()
            if url.lastPathComponent == "target",
               FileManager.default.fileExists(atPath: parent.appendingPathComponent("Cargo.toml").path) { return .build }
            if url.lastPathComponent == ".venv",
               FileManager.default.fileExists(atPath: url.appendingPathComponent("pyvenv.cfg").path) { return .build }
            return nil
        }
        if ["dmg", "pkg", "iso", "zip", "7z", "rar", "tar", "gz"].contains(url.pathExtension.lowercased()) { return .installer }
        if url.pathExtension.lowercased() == "log" { return .log }
        return nil
    }

    /// Coalesce parent/child selection so totals and trash operations never double-count.
    public static func coalesced(_ items: [ScanItem]) -> [ScanItem] {
        // A trailing separator keeps each subtree contiguous, even beside names such as
        // "folder-backup". Sorting once avoids quadratic ancestor checks for large snapshots.
        let keyed = items.map { item in
            let path = item.url.standardizedFileURL.path
            return (item: item, key: path == "/" ? "/" : path + "/")
        }.sorted { $0.key < $1.key }
        var result: [ScanItem] = []
        var previous: String?
        for entry in keyed {
            if let previous, entry.key.hasPrefix(previous) { continue }
            result.append(entry.item)
            previous = entry.key
        }
        return result
    }

    public static func isEssentialDirectory(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let essential = [home, home.appendingPathComponent("Library")] +
            ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"].map { home.appendingPathComponent($0) }
        return essential.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    public static func validateForTrash(_ url: URL, root: URL) throws {
        let normalized = url.standardizedFileURL
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        guard normalized.path != canonicalRoot.path,
              contains(canonicalRoot, normalized),
              normalized.resolvingSymlinksInPath().path == normalized.path,
              !protected(normalized) else { throw StorageError.unsafePath(url.path) }
        guard !isEssentialDirectory(normalized) else {
            throw StorageError.unsafePath(url.path)
        }
    }
}
