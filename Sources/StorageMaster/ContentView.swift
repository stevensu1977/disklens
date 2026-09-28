import SwiftUI
import AppKit
import StorageCore

struct ContentView: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                toolbar
                ScrollView {
                    VStack(alignment: .leading, spacing: 23) {
                        heading
                        if let notice = model.notice { banner(notice, symbol: "info.circle", color: Theme.blue) }
                        if let error = model.error { banner(error, symbol: "exclamationmark.triangle", color: Theme.orange) }
                        if model.scanning { scanProgress }
                        if model.page == .overview {
                            OverviewView(model: model)
                        } else if model.result == nil {
                            WelcomeView(model: model)
                        } else if model.page == .duplicates {
                            DuplicateView(model: model)
                        } else {
                            FileListView(model: model)
                        }
                    }.padding(30)
                }
                bottomBar
            }
            .background(Theme.background)
        }
        .id(model.language)
        .foregroundStyle(Theme.ink)
        .font(.system(size: 13))
        .tint(Theme.blue)
        .environment(\.locale, model.language.locale)
        .sheet(isPresented: $model.showTrashConfirmation) { TrashConfirmation(model: model).id(model.language) }
        .sheet(item: $model.detail) { item in FileDetail(item: item, model: model).id(model.language) }
        .sheet(isPresented: $model.showPermissions) { permissions.id(model.language) }
        .sheet(isPresented: $model.showScanIssues) { scanIssues.id(model.language) }
        .sheet(isPresented: $model.showFolders) { FolderGroupsView(model: model).id(model.language) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppBrandIcon().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("盘点 · DiskLens").font(.system(size: 15, weight: .bold))
                    Text("给重要的事，腾点空间").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }.padding(.top, 48).padding(.bottom, 18).padding(.horizontal, 21)
            languageSwitch.padding(.bottom, 24)
            Text("工作空间").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 27).padding(.bottom, 11)
            ForEach(Page.allCases) { page in
                Button { model.navigate(page) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.symbol).font(.system(size: 15)).frame(width: 20)
                        Text(page.title).font(.system(size: 12, weight: model.page == page ? .semibold : .regular))
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Spacer()
                        if page == .cleanup, let count = model.result?.suggestions.count, count > 0 {
                            Text("\(count)").font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.blue.opacity(0.1), in: Capsule())
                        } else if page == .large, model.largeFileCount > 0 {
                            Text("\(model.largeFileCount)").font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.blue.opacity(0.1), in: Capsule())
                        }
                    }.padding(.horizontal, 14).frame(height: 43)
                        .foregroundStyle(model.page == page ? Theme.blue : Theme.ink.opacity(0.75))
                        .background(model.page == page ? Theme.blue.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, 13).padding(.bottom, 4)
            }
            Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 25).padding(.vertical, 25)
            Text("快速扫描").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 27).padding(.bottom, 12)
            ForEach(StandardScanLocation.available) { location in
                shortcut(location)
            }
            Spacer()
            sidebarCapacity
            Button { model.showPermissions = true } label: {
                Label("权限与使用说明", systemImage: "questionmark.circle").font(.system(size: 11))
            }.buttonStyle(.plain).foregroundStyle(Theme.secondary).padding(.leading, 26).padding(.bottom, 23)
        }.frame(width: 230).background(Theme.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private var languageSwitch: some View {
        HStack(spacing: 7) {
            Text("界面语言").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(AppLanguage.allCases) { language in
                    Button { model.setLanguage(language) } label: {
                        Text(language.badge)
                            .font(.system(size: 10, weight: model.language == language ? .semibold : .medium))
                            .frame(minWidth: 30, minHeight: 25)
                            .foregroundStyle(model.language == language ? .white : Theme.secondary)
                            .background(model.language == language ? Theme.blue : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help(language.title)
                    .accessibilityLabel(language.title)
                }
            }
            .padding(3)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("界面语言"))
    }

    private var sidebarCapacity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.capacity?.name ?? L10n.string("本地磁盘"), systemImage: "internaldrive")
                .font(.system(size: 11, weight: .medium)).lineLimit(1)
            VStack(alignment: .leading, spacing: 4) {
                Text("总容量").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Text(model.capacity.map { StorageFormat.bytes($0.total) } ?? "—")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            GeometryReader { geometry in
                Capsule().fill(Theme.line)
                Capsule().fill(Theme.blue)
                    .frame(width: geometry.size.width * min(1, max(0, model.capacity?.fraction ?? 0)))
            }.frame(height: 5)
            HStack {
                Text(L10n.format("已用 %@", model.capacity.map { StorageFormat.bytes($0.used) } ?? "—"))
                Spacer(minLength: 0)
            }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
            Text(L10n.format("可用 %@", model.capacity.map { StorageFormat.bytes($0.available) } ?? "—"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle((model.capacity?.fraction ?? 0) > 0.9 ? Theme.orange : Theme.green)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16).padding(.vertical, 16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("磁盘容量")
    }

    private func shortcut(_ location: StandardScanLocation) -> some View {
        Button { model.scan(location.url); model.navigate(.overview) } label: {
            Label(L10n.string(location.title), systemImage: location.symbol).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 27).padding(.vertical, 11)
        }.buttonStyle(.plain).foregroundStyle(Theme.secondary).disabled(model.busy)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if !model.history.isEmpty {
                Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).disabled(model.busy).help(L10n.string("返回上一个扫描位置"))
            }
            Image(systemName: "internaldrive").foregroundStyle(Theme.secondary)
            Text(model.capacity?.name ?? L10n.string("本地磁盘")).font(.system(size: 11, weight: .medium))
            Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Theme.secondary)
            FolderBreadcrumbs(url: model.root, enabled: !model.busy, onSelect: model.openAncestor)
            Spacer(minLength: 10)
            Button { model.chooseFolder() } label: { Label("选择文件夹", systemImage: "folder.badge.plus") }
                .buttonStyle(QuietButton()).disabled(model.busy)
            if model.scanning || model.hashing {
                Button { model.cancel() } label: { Label("停止", systemImage: "stop.fill") }.buttonStyle(PrimaryButton())
            } else {
                Button { model.scan() } label: {
                    Label(L10n.string(model.result == nil ? "开始扫描" : "重新扫描"),
                          systemImage: model.result == nil ? "viewfinder" : "arrow.clockwise")
                }.buttonStyle(PrimaryButton()).disabled(model.cleaning)
            }
        }.padding(.horizontal, 30).frame(height: 72).background(.white.opacity(0.8))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var heading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(model.page.title).font(.system(size: 27, weight: .bold))
                Text(model.page.subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if let result = model.result {
                HStack(spacing: 6) {
                    Text("≥ \(StorageFormat.bytes(result.minimumItemBytes))")
                        .font(.system(size: 10)).foregroundStyle(Theme.blue).padding(.trailing, 6)
                    Circle().fill(result.isComplete ? Theme.green : Theme.orange).frame(width: 6, height: 6)
                    Text(result.isComplete ? (result.cacheUpdatedAt.map {
                        L10n.format("缓存已更新 %@", $0.formatted(date: .omitted, time: .shortened))
                    } ?? L10n.format("扫描完成 %@", result.finishedAt.formatted(date: .omitted, time: .shortened))) :
                            L10n.string(model.scanning ? "部分结果 · 扫描中" : "部分结果 · 已停止"))
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            } else {
                Text(L10n.format("大文件优先 · ≥ %@", StorageFormat.bytes(model.minimumSize)))
                    .font(.system(size: 10)).foregroundStyle(Theme.blue)
            }
        }
    }

    private var scanProgress: some View {
        Panel {
            HStack(spacing: 14) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("边扫边看 · 优先查找大文件…").fontWeight(.medium)
                        Spacer()
                        Text(L10n.format("%@ 个文件 · %@", model.progress.count.formatted(),
                                         StorageFormat.bytes(model.progress.bytes)))
                            .foregroundStyle(Theme.secondary)
                    }
                    Text(model.progress.path).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }
    private func banner(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.system(size: 11)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                if model.error == text { model.error = nil } else { model.notice = nil }
            } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
        }.padding(13).background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
    private var bottomBar: some View {
        HStack(spacing: 10) {
            if model.selection.isEmpty {
                Image(systemName: "checkmark.shield").foregroundStyle(Theme.green)
                Text("扫描不会修改任何文件").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                if let result = model.result {
                    Text(L10n.format("%@ 个文件 · 用时 %d 秒", result.fileCount.formatted(), Int(result.elapsed)))
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    if result.skippedCount > 0 {
                        Button(L10n.format("%d 项已跳过", result.skippedCount)) { model.showScanIssues = true }
                            .buttonStyle(.plain).foregroundStyle(Theme.orange).font(.system(size: 10))
                    }
                }
            } else {
                Text(L10n.format("已选 %d 项", model.selectedItems.count)).font(.system(size: 12))
                Text(StorageFormat.bytes(model.selectedBytes)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.blue)
                Button("取消选择") { model.selection.removeAll() }.buttonStyle(.plain).foregroundStyle(Theme.secondary).padding(.leading, 8)
                Spacer()
                Text("可从废纸篓恢复").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Button {
                    model.showTrashConfirmation = true
                } label: {
                    Label(L10n.string(model.cleaning ? "正在移到废纸篓…" : "移到废纸篓"), systemImage: "trash")
                }.buttonStyle(PrimaryButton()).disabled(model.busy)
            }
        }.padding(.horizontal, 30).frame(height: 64).background(.white)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            SymbolBadge(symbol: "lock.shield", size: 48)
            Text("让扫描看得更完整").font(.system(size: 23, weight: .bold))
            Text("选择文件夹即可开始。若部分目录因权限未读取，可在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中添加 DiskLens，然后退出并重新打开应用。")
            Text("扫描仅在本机进行，不联网、不上传文件；不请求管理员权限。系统目录、照片图库、应用包和敏感的应用数据不会成为清理候选。")
            Text("占用按文件实际分配空间估算。APFS 克隆、压缩、快照与受限目录可能造成差异；移到废纸篓不会立即释放磁盘空间。")
                .foregroundStyle(Theme.secondary)
            HStack {
                Button("打开隐私设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                }.buttonStyle(QuietButton())
                Spacer()
                Button("知道了") { model.showPermissions = false }.buttonStyle(PrimaryButton())
            }
        }.font(.system(size: 12)).lineSpacing(5).padding(30).frame(width: 540)
    }
    private var scanIssues: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("快速扫描跳过的项目").font(.system(size: 22, weight: .bold))
            Text("为加快扫描，已跳过 .git。权限受限、其他卷和未下载的云端文件也不计入结果；以下最多显示 20 个位置。")
                .foregroundStyle(Theme.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(model.result?.issues ?? [], id: \.self) { Text($0).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 280)
            HStack {
                Button("查看权限说明") { model.showScanIssues = false; model.showPermissions = true }.buttonStyle(QuietButton())
                Spacer()
                Button("完成") { model.showScanIssues = false }.buttonStyle(PrimaryButton())
            }
        }.font(.system(size: 12)).padding(28).frame(width: 580)
    }
}
