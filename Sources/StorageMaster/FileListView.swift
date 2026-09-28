import SwiftUI
import AppKit
import StorageCore

struct FileListView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            if model.page == .cleanup {
                HStack(spacing: 8) {
                    filterPill("全部", kind: nil)
                    ForEach(CleanupKind.allCases.filter { $0 != .large }) { kind in filterPill(kind.title, kind: kind) }
                    Spacer()
                }
                if model.filter == .stale {
                    Label("超过一年未修改，且达到当前大小门槛。目录按内部最新修改时间判断；时间久不代表无用，请人工确认。",
                          systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            HStack(spacing: 13) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    TextField("搜索名称或路径", text: $model.search).textFieldStyle(.plain)
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary) }
                            .buttonStyle(.plain)
                    }
                }.padding(10).frame(maxWidth: 310).background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
                Spacer()
                if model.page == .large {
                    Picker("文件大小", selection: $model.minimumSize) {
                        Text("大于 10 MB").tag(Int64(10_000_000))
                        Text("大于 100 MB").tag(Int64(100_000_000))
                        Text("大于 1 GB").tag(Int64(1_000_000_000))
                    }.frame(width: 188).onChange(of: model.minimumSize) { _, _ in model.scan() }
                }
                Picker("排序", selection: $model.sortNewest) {
                    Text("体积从大到小").tag(false)
                    Text("最近修改优先").tag(true)
                }.labelsHidden().frame(width: 140)
            }.font(.system(size: 11))
            VStack(spacing: 0) {
                HStack {
                    Text("文件名称").padding(.leading, 37)
                    Spacer()
                    Text(L10n.format("%d 项 · %@", model.visibleItems.count,
                                     StorageFormat.bytes(model.visibleItems.reduce(0) { $0 + $1.bytes })))
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 16).frame(height: 40).background(Theme.sidebar.opacity(0.55))
                if model.visibleItems.isEmpty {
                    VStack(spacing: 12) {
                        if model.page == .cleanup && model.search.isEmpty && model.largeFileCount > 0 {
                            Image(systemName: "doc.viewfinder").font(.system(size: 32)).foregroundStyle(Theme.blue)
                            Text(L10n.format("这个分类没有建议，另有 %d 个大文件", model.largeFileCount))
                                .font(.system(size: 15, weight: .medium))
                            Text("PPT、视频和普通文档列在「大文件」中，需要你判断是否保留。")
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            Button(L10n.format("查看 %d 个大文件", model.largeFileCount)) { model.navigate(.large) }
                                .buttonStyle(PrimaryButton()).padding(.top, 5)
                        } else {
                            Image(systemName: "magnifyingglass").font(.system(size: 32)).foregroundStyle(Theme.secondary)
                            Text(L10n.string(model.search.isEmpty ? "这个范围内没有匹配的文件" : "没有找到匹配结果"))
                                .font(.system(size: 15, weight: .medium))
                            Text(L10n.string(model.page == .large ? "可以降低大小门槛，或扫描其他文件夹。" :
                                "试试其他分类或文件夹。未列为候选不代表不占空间。"))
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 60)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.visibleItems) { item in
                            FileRow(item: item, model: model)
                            Divider().overlay(Theme.line).padding(.leading, 54)
                        }
                    }
                }
            }.background(.white, in: RoundedRectangle(cornerRadius: 11))
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line))
            Label(L10n.string(model.page == .large ? "大文件仅按体积筛选，不代表可以安全删除。构建目录已合并展示在清理建议中。" :
                    "候选是检查线索。构建目录合并显示，清理前请退出相关应用并确认文件用途。"),
                  systemImage: "info.circle")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }
    }
    private func filterPill(_ text: String, kind: CleanupKind?) -> some View {
        Button { model.filter = kind } label: {
            Text(L10n.string(text)).font(.system(size: 11, weight: model.filter == kind ? .semibold : .regular))
                .padding(.horizontal, 13).padding(.vertical, 8)
                .foregroundStyle(model.filter == kind ? .white : Theme.secondary)
                .background(model.filter == kind ? Theme.blue : .white, in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct FileRow: View {
    let item: ScanItem
    @Bindable var model: AppModel
    var retained = false
    var body: some View {
        HStack(spacing: 13) {
            Button { model.toggle(item) } label: {
                Image(systemName: model.selection.contains(item.id) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17)).foregroundStyle(model.selection.contains(item.id) ? Theme.blue : Theme.secondary.opacity(0.5))
            }.buttonStyle(.plain).disabled(model.busy || retained)
                .accessibilityLabel(L10n.format("选择 %@", item.name))
                .accessibilityValue(L10n.string(model.selection.contains(item.id) ? "已选择" : "未选择"))
            SymbolBadge(symbol: item.isDirectory ? "folder.fill" : item.kind.symbol, color: Theme.color(item.kind), size: 36)
            Button { model.detail = item } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        if retained {
                            Text("保留此份").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.green)
                        }
                    }
                    Text(StorageFormat.path(item.url.deletingLastPathComponent())).font(.system(size: 10))
                        .foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            FileDatesView(created: item.created, modified: item.latestModified,
                          modificationLabel: item.isDirectory ? "最新修改" : "修改")
            VStack(alignment: .trailing, spacing: 5) {
                Text(StorageFormat.bytes(item.bytes)).font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(item.kind.risk).font(.system(size: 9)).foregroundStyle(Theme.color(item.kind))
            }.frame(width: 103, alignment: .trailing)
            Button { model.reveal(item.url) } label: {
                Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }.buttonStyle(.plain).help(L10n.string("在 Finder 中显示")).padding(.leading, 7)
        }.padding(.horizontal, 17).padding(.vertical, 14)
            .background(model.selection.contains(item.id) ? Theme.blue.opacity(0.035) : .clear)
            .contextMenu {
                Button("查看详情") { model.detail = item }
                Button("在 Finder 中显示") { model.reveal(item.url) }
                Button("复制路径") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.url.path, forType: .string)
                }
            }
    }
}

struct DuplicateView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel {
                HStack(spacing: 17) {
                    SymbolBadge(symbol: "square.on.square", color: Theme.purple, size: 45)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.hashing ? model.hashProgress : L10n.string("内容相同，才算重复"))
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.format("比较 %@ 以上本地文件的 SHA-256；跳过构建目录与受保护数据。",
                                         StorageFormat.bytes(model.result?.minimumItemBytes ?? 100_000_000)))
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Text("每组建议保留第一份，其他副本仍需手动选择。不同位置的副本可能有各自用途。")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                    if model.hashing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(L10n.string(model.duplicatesFinished ? "重新比对" : "查找重复文件")) { model.findDuplicates() }
                            .buttonStyle(PrimaryButton()).disabled(model.busy)
                    }
                }
            }
            if model.duplicatesFinished {
                SectionHeading(title: L10n.format("找到 %d 组重复文件", model.duplicates.count),
                               subtitle: L10n.format("多余副本占用 %@",
                                                     StorageFormat.bytes(model.duplicates.reduce(0) { $0 + $1.redundantBytes })))
                if model.duplicates.isEmpty {
                    ContentUnavailableView("未发现重复内容", systemImage: "checkmark.seal",
                                           description: Text("当前扫描范围内，符合比对条件的文件没有重复。"))
                }
                ForEach(model.duplicates) { group in
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "equal.circle").foregroundStyle(Theme.purple)
                            Text(L10n.format("%d 份相同内容", group.items.count)).fontWeight(.medium)
                            Spacer()
                            Text(L10n.format("多余 %@", StorageFormat.bytes(group.redundantBytes)))
                                .foregroundStyle(Theme.secondary)
                        }.font(.system(size: 11)).padding(14).background(Theme.purple.opacity(0.05))
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            FileRow(item: item, model: model, retained: index == 0)
                            if index < group.items.count - 1 { Divider().padding(.leading, 54) }
                        }
                    }.background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                }
            } else if !model.hashing {
                VStack(spacing: 15) {
                    Image(systemName: "doc.on.doc").font(.system(size: 43, weight: .ultraLight)).foregroundStyle(Theme.purple)
                    Text("给重复下载的文件做一次比对").font(.system(size: 16, weight: .medium))
                    Text("比对会读取文件内容。文件越多、越大，耗时越长，可随时停止。")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 55)
            }
        }
    }
}

struct FileDetail: View {
    let item: ScanItem
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 14) {
                SymbolBadge(symbol: item.isDirectory ? "folder.fill" : item.kind.symbol, color: Theme.color(item.kind), size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.system(size: 21, weight: .semibold)).lineLimit(2)
                    Text(item.kind.title).foregroundStyle(Theme.secondary)
                }
            }
            Divider()
            detailLine("实际占用", value: StorageFormat.bytes(item.bytes))
            if !item.isDirectory { detailLine("文件大小", value: StorageFormat.bytes(item.logicalBytes)) }
            detailLine("创建时间", value: StorageFormat.date(item.created, includeTime: true))
            detailLine(item.isDirectory ? "目录修改" : "最后修改", value: StorageFormat.date(item.modified, includeTime: true))
            if item.isDirectory {
                detailLine("最新修改", value: StorageFormat.date(item.latestModified, includeTime: true))
                Text("最新修改取目录自身与内部所有已扫描项目的最新时间，包含小文件。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            detailLine("完整路径", value: item.url.path)
            Label(item.kind.caution, systemImage: "info.circle")
                .foregroundStyle(Theme.color(item.kind)).padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.color(item.kind).opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Button("在 Finder 中显示") { model.reveal(item.url) }.buttonStyle(QuietButton())
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(PrimaryButton())
            }
        }.font(.system(size: 12)).padding(28).frame(width: 570)
    }
    private func detailLine(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(L10n.string(label)).foregroundStyle(Theme.secondary).frame(width: 76, alignment: .leading)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct TrashConfirmation: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            SymbolBadge(symbol: "trash", color: Theme.orange, size: 48)
            Text(L10n.format("将 %d 项移到废纸篓？", model.selectedItems.count))
                .font(.system(size: 23, weight: .bold))
            Text(L10n.format("所选内容占用约 %@。移入后仍占磁盘空间；请在 Finder 中检查废纸篓，确认后自行清空。",
                             StorageFormat.bytes(model.selectedBytes)))
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.selectedItems) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.isDirectory ? "folder" : "doc").foregroundStyle(Theme.color(item.kind))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.url.path).font(.system(size: 11, weight: .medium)).textSelection(.enabled)
                                Text(item.kind.caution).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Text(StorageFormat.bytes(item.bytes)).font(.system(size: 11, weight: .medium)).fixedSize()
                        }
                    }
                }.padding(15)
            }.frame(maxHeight: 265).background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
            Text("执行前会重新检查路径和扫描记录；发生变化的文件将跳过。")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            HStack {
                Spacer()
                Button("取消") { model.showTrashConfirmation = false }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button("确认移到废纸篓") { model.trashSelected() }.buttonStyle(PrimaryButton())
            }
        }.padding(30).frame(width: 620)
    }
}
