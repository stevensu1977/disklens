import Foundation

extension ScanResult {
    /// Apply only confirmed moves to the current snapshot; no filesystem access or rescanning.
    /// A second application of the same report is a no-op because the moved records are gone.
    public func applyingTrash(_ report: TrashReport, at date: Date = Date()) -> ScanResult {
        let movedIDs = Set(report.moved)
        let removed = PathPolicy.coalesced(items.filter { movedIDs.contains($0.id) })
        guard !removed.isEmpty else { return self }

        var updated = self
        updated.items.removeAll { item in
            removed.contains { moved in
                PathPolicy.contains(moved.url, item.url) ||
                // A containing candidate's recursive fingerprint is now stale. It cannot be
                // re-baselined without a new inspection; unrelated siblings stay usable.
                (item.isDirectory && PathPolicy.contains(item.url, moved.url))
            }
        }
        updated.totalBytes = max(0, totalBytes - removed.reduce(0) { $0 + $1.bytes })
        updated.fileCount = max(0, fileCount - removed.reduce(0) { $0 + $1.fileCount })

        for item in removed {
            // A partial snapshot may not have a completed top-level folder yet. In that
            // case its bytes are in the remainder tile, not in another directory tile.
            if let index = updated.groups.firstIndex(where: {
                !$0.isRemainder && PathPolicy.contains($0.url, item.url)
            }) {
                updated.groups[index].bytes = max(0, updated.groups[index].bytes - item.bytes)
            } else if let index = updated.groups.firstIndex(where: \.isRemainder) {
                updated.groups[index].bytes = max(0, updated.groups[index].bytes - item.bytes)
            }
        }
        updated.groups.removeAll { $0.bytes == 0 }
        updated.groups.sort { $0.bytes > $1.bytes }
        updated.cacheUpdatedAt = date
        return updated
    }

    public func retainingDuplicateGroups(_ groups: [DuplicateGroup]) -> [DuplicateGroup] {
        let retainedIDs = Set(items.map(\.id))
        return groups.compactMap { group in
            let remaining = group.items.filter { retainedIDs.contains($0.id) }
            guard remaining.count > 1 else { return nil }
            return DuplicateGroup(id: group.id, items: remaining)
        }.sorted { $0.redundantBytes > $1.redundantBytes }
    }
}
