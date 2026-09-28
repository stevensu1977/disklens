import SwiftUI
import StorageCore

struct OverviewView: View {
    @Bindable var model: AppModel
    private var hasCleanupSuggestions: Bool { model.result?.suggestions.isEmpty == false }
    private var reviewItems: [ScanItem] {
        guard let result = model.result else { return [] }
        return result.suggestions.isEmpty ? result.largeFiles : result.suggestions
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .top, spacing: 18) {
                capacityPanel
                opportunityPanel
            }
            if let result = model.result {
                Panel {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            SectionHeading(title: "空间分布", subtitle: result.isComplete ? "面积越大，占用越多" : "仅显示已扫描部分")
                            Spacer()
                            Text(StorageFormat.bytes(result.totalBytes)).font(.system(size: 15, weight: .semibold))
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "folder").foregroundStyle(Theme.blue)
                            FolderBreadcrumbs(url: result.root, enabled: !model.busy,
                                              onSelect: model.openAncestor, fontSize: 10)
                            Button(L10n.format("查看全部 %d 个项目", result.groups.count)) { model.showFolders = true }
                                .buttonStyle(.plain).foregroundStyle(Theme.blue)
                        }.font(.system(size: 10))
                        if result.groups.isEmpty {
                            Text("没有可统计的本地文件。").foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, minHeight: 190)
                        } else {
                            StorageMap(groups: result.groups, onSelect: { group in
                                if group.isRemainder {
                                    model.notice = result.isComplete ?
                                        L10n.format("小于 %@ 的零散文件已合并统计。可在「大文件」页降低门槛后重新扫描。",
                                                    StorageFormat.bytes(result.minimumItemBytes)) :
                                        L10n.string("这部分包含尚未细分的目录和零散小文件，扫描完成后会继续细分。")
                                } else if group.isDirectory { model.scan(group.url) } else { model.reveal(group.url) }
                            }, onSelectOther: { model.showFolders = true }).frame(height: 236)
                        }
                        HStack(spacing: 15) {
                            ForEach(Array(result.groups.prefix(5).enumerated()), id: \.element.id) { index, group in
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 2).fill(Theme.mapColors[index]).frame(width: 7, height: 7)
                                    Text(group.name).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
                recommendations(result)
            } else if !model.scanning {
                WelcomeView(model: model)
            }
        }
    }

    private var capacityPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    SectionHeading(title: model.capacity?.name ?? L10n.string("磁盘空间"))
                    Spacer()
                    if let capacity = model.capacity, capacity.fraction > 0.9 {
                        Text("空间紧张").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.orange.opacity(0.1), in: Capsule())
                    }
                }
                HStack(spacing: 27) {
                    ZStack {
                        Circle().stroke(Theme.line, lineWidth: 13)
                        Circle().trim(from: 0, to: min(1, model.capacity?.fraction ?? 0))
                            .stroke(Theme.blue, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 5) {
                            Text(model.capacity.map { "\(Int($0.fraction * 100))%" } ?? "—")
                                .font(.system(size: 31, weight: .semibold, design: .rounded))
                            Text("已使用").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                    }.frame(width: 131, height: 131).padding(7)
                    VStack(alignment: .leading, spacing: 15) {
                        metric("可用空间", value: model.capacity.map { StorageFormat.bytes($0.available) } ?? "—", color: Theme.green)
                        metric("已用空间", value: model.capacity.map { StorageFormat.bytes($0.used) } ?? "—", color: Theme.blue)
                        HStack(spacing: 5) {
                            Text("总容量").foregroundStyle(Theme.secondary)
                            Text(model.capacity.map { StorageFormat.bytes($0.total) } ?? "—")
                        }.font(.system(size: 10))
                    }
                    Spacer(minLength: 0)
                }
            }.frame(height: 194)
        }
    }
    private func metric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
            Text(L10n.string(title)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded))
        }
    }
    private var opportunityPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "sparkles").font(.system(size: 17)).foregroundStyle(Theme.blue)
                Text("可以从这里开始").font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.result == nil ? L10n.string("等待扫描") :
                     StorageFormat.bytes(reviewItems.reduce(0) { $0 + $1.bytes }))
                    .font(.system(size: model.result == nil ? 29 : 37, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.blue)
                Text(model.result == nil ? L10n.string("扫描后发现值得检查的文件") :
                    (hasCleanupSuggestions ?
                     L10n.format("%d 项清理候选，等待你确认", reviewItems.count) :
                     L10n.format("%d 个大文件，需要人工确认", reviewItems.count)))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Text(L10n.string(hasCleanupSuggestions || model.result == nil ?
                             "优先检查构建产物与缓存。\n文件是否有用，始终由你决定。" :
                             "PPT、视频和文档也会占用空间。\n检查内容与备份，再决定是否保留。"))
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
            Spacer(minLength: 0)
            Button {
                if model.result == nil { model.scan() }
                else { model.navigate(hasCleanupSuggestions ? .cleanup : .large) }
            } label: {
                HStack {
                    Text(L10n.string(model.result == nil ? "扫描当前文件夹" :
                                     (hasCleanupSuggestions ? "查看清理建议" : "查看大文件")))
                    Spacer()
                    Image(systemName: "arrow.right")
                }.font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.blue)
            }.buttonStyle(.plain).disabled(model.result == nil && model.busy)
        }.padding(22).frame(width: 256, height: 238, alignment: .topLeading)
            .background(Color(hex: 0xEDF3FF), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.blue.opacity(0.08)))
    }
    private func recommendations(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeading(title: "值得检查", subtitle: "按用途与修改时间分类，类别可能重叠")
                Spacer()
                Button("查看全部") { model.navigate(.cleanup) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.blue)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                ForEach([CleanupKind.build, .stale, .installer, .cache, .log]) { kind in
                    let items = PathPolicy.coalesced(result.items.filter { $0.kind == kind })
                    Button {
                        model.navigate(.cleanup)
                        model.filter = kind
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SymbolBadge(symbol: kind.symbol, color: Theme.color(kind), size: 31)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                            }
                            Text(kind.title).font(.system(size: 11, weight: .medium))
                            HStack(alignment: .firstTextBaseline) {
                                Text(StorageFormat.bytes(items.reduce(0) { $0 + $1.bytes }))
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                Spacer(minLength: 2)
                                Text(L10n.format("%d 项", items.count))
                                    .font(.system(size: 9)).foregroundStyle(Theme.secondary)
                            }
                        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct WelcomeView: View {
    @Bindable var model: AppModel
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 15) {
                    SymbolBadge(symbol: "folder.badge.gearshape", size: 46)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("先从常用文件夹开始").font(.system(size: 17, weight: .semibold))
                        Text("选择一个位置，查看真实的文件占用与清理建议。").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                }
                HStack(spacing: 13) {
                    ForEach(StandardScanLocation.available) { folder in
                        location(folder)
                    }
                    if StandardScanLocation.available.isEmpty {
                        Button("选择文件夹") { model.chooseFolder() }
                    }
                }
                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                    Text("不自动选中文件，也不会在扫描时删除内容。")
                }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
        }
    }
    private func location(_ folder: StandardScanLocation) -> some View {
        let color: Color = switch folder {
        case .desktop: Theme.blue
        case .downloads: Theme.orange
        case .documents: Theme.green
        }
        return Button { model.scan(folder.url) } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: folder.symbol).font(.system(size: 21)).foregroundStyle(color)
                Text(L10n.string(folder.title)).font(.system(size: 13, weight: .semibold))
                Text(L10n.string(folder.description)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                HStack {
                    Text(folder.displayPath).font(.system(size: 9)).foregroundStyle(Theme.secondary).lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(color)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).disabled(model.busy)
    }
}

private struct MapTile: Identifiable {
    var id: Int
    var group: DiskGroup?
    var bytes: Int64
    var name: String
    var color: Color
}
private struct TileLayout: Identifiable {
    var id: Int { tile.id }
    var tile: MapTile
    var rect: CGRect
}
struct StorageMap: View {
    let groups: [DiskGroup]
    var onSelect: (DiskGroup) -> Void
    var onSelectOther: () -> Void
    private var tiles: [MapTile] {
        var result = groups.prefix(11).enumerated().map { index, group in
            MapTile(id: index, group: group, bytes: group.bytes, name: group.name, color: Theme.mapColors[index])
        }
        if groups.count > 11 {
            result.append(MapTile(id: 11, bytes: groups.dropFirst(11).reduce(0) { $0 + $1.bytes },
                                  name: L10n.format("其他 %d 项", groups.count - 11), color: Theme.mapColors[11]))
        }
        return result
    }
    // Balanced binary treemap preserves area ratios without unreadably thin slice-and-dice strips.
    private func layout(_ tiles: [MapTile], in rect: CGRect) -> [TileLayout] {
        guard !tiles.isEmpty else { return [] }
        if tiles.count == 1 { return [TileLayout(tile: tiles[0], rect: rect)] }
        let total = tiles.reduce(0.0) { $0 + Double($1.bytes) }
        var sum = 0.0
        var split = 1
        var closest = Double.greatestFiniteMagnitude
        for i in 1..<tiles.count {
            sum += Double(tiles[i - 1].bytes)
            let distance = abs(total / 2 - sum)
            if distance < closest { closest = distance; split = i }
        }
        let left = Array(tiles.prefix(split))
        let right = Array(tiles.dropFirst(split))
        let ratio = left.reduce(0.0) { $0 + Double($1.bytes) } / max(1, total)
        let first: CGRect
        let second: CGRect
        if rect.width >= rect.height {
            let width = rect.width * ratio
            first = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
            second = CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
        } else {
            let height = rect.height * ratio
            first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
            second = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
        }
        return layout(left, in: first) + layout(right, in: second)
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(layout(tiles, in: CGRect(origin: .zero, size: geometry.size))) { cell in
                    Button {
                        if let group = cell.tile.group { onSelect(group) } else { onSelectOther() }
                    } label: {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 7).fill(cell.tile.color)
                            if cell.rect.width > 65 && cell.rect.height > 42 {
                                VStack(alignment: .leading, spacing: 5) {
                                    if cell.rect.height > 95 {
                                        Image(systemName: cell.tile.group?.isDirectory == true ? "folder.fill" : "doc.fill")
                                            .font(.system(size: 17)).foregroundStyle(.white.opacity(0.7)).padding(.bottom, 4)
                                    }
                                    Text(cell.tile.name).font(.system(size: cell.rect.width > 170 ? 13 : 10, weight: .semibold)).lineLimit(1)
                                    if cell.rect.height > 61 {
                                        Text(StorageFormat.bytes(cell.tile.bytes)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.82))
                                    }
                                    if cell.rect.height > 145, cell.rect.width > 150,
                                       let group = cell.tile.group, !group.isRemainder {
                                        Text(L10n.format("%@ %@", L10n.string(group.isDirectory ? "最新修改" : "修改"),
                                                         StorageFormat.date(group.latestModified)))
                                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.8))
                                    }
                                }.padding(cell.rect.width > 170 ? 17 : 10).foregroundStyle(.white)
                            }
                        }.frame(width: max(0, cell.rect.width - 4), height: max(0, cell.rect.height - 4)).clipped()
                    }.buttonStyle(.plain).offset(x: cell.rect.minX + 2, y: cell.rect.minY + 2)
                        .help(tileHelp(cell.tile))
                        .accessibilityLabel(L10n.format("%@，%@", cell.tile.name, StorageFormat.bytes(cell.tile.bytes)))
                }
            }
        }
    }
    private func tileHelp(_ tile: MapTile) -> String {
        var text = "\(tile.name) · \(StorageFormat.bytes(tile.bytes))"
        if let group = tile.group, !group.isRemainder {
            text += L10n.format("\n修改时间：%@", StorageFormat.date(group.modified, includeTime: true))
            text += L10n.format("\n创建时间：%@", StorageFormat.date(group.created, includeTime: true))
            if group.isDirectory {
                text += L10n.format("\n含内部项目最新修改：%@", StorageFormat.date(group.latestModified, includeTime: true))
            }
        }
        return text
    }
}

struct FolderGroupsView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("文件夹与文件占用").font(.system(size: 21, weight: .semibold))
                Spacer()
                Button("完成") { model.showFolders = false }.buttonStyle(QuietButton())
            }
            Text(StorageFormat.path(model.root)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            TextField("搜索当前层级的项目", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach((model.result?.groups ?? []).filter {
                        query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                    }) { group in
                        Button {
                            model.showFolders = false
                            if group.isRemainder {
                                model.notice = L10n.string("零散小文件已合并统计，可在「大文件」页降低门槛后重新扫描。")
                            } else if group.isDirectory { model.scan(group.url) } else { model.reveal(group.url) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: group.isDirectory ? "folder.fill" : "doc.fill").foregroundStyle(Theme.blue)
                                Text(group.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                if !group.isRemainder {
                                    FileDatesView(created: group.created, modified: group.latestModified,
                                                  modificationLabel: group.isDirectory ? "最新修改" : "修改")
                                }
                                Text(StorageFormat.bytes(group.bytes)).fontWeight(.medium)
                                    .frame(width: 76, alignment: .trailing)
                                Image(systemName: group.isDirectory ? "chevron.right" : "arrow.up.right")
                                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }.padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }.frame(height: 360)
            Text("目录的「最新修改」包含内部已扫描项目；创建时间为目录自身的时间。")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }.font(.system(size: 12)).padding(28).frame(width: 700)
    }
}
