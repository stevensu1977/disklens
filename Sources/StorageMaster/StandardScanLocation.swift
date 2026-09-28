import Foundation

enum StandardScanLocation: String, CaseIterable, Identifiable {
    case desktop = "Desktop"
    case downloads = "Downloads"
    case documents = "Documents"

    var id: Self { self }

    private var directory: FileManager.SearchPathDirectory {
        switch self {
        case .desktop: .desktopDirectory
        case .downloads: .downloadsDirectory
        case .documents: .documentDirectory
        }
    }

    var url: URL {
        FileManager.default.urls(for: directory, in: .userDomainMask).first ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(rawValue, isDirectory: true)
    }

    var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static var available: [Self] { allCases.filter(\.isAvailable) }
    static var defaultRoot: URL {
        if documents.isAvailable { return documents.url }
        return available.first?.url ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var title: String {
        switch self {
        case .desktop: "桌面"
        case .downloads: "下载"
        case .documents: "文稿"
        }
    }

    var symbol: String {
        switch self {
        case .desktop: "menubar.dock.rectangle"
        case .downloads: "arrow.down.circle"
        case .documents: "doc.on.doc"
        }
    }

    var description: String {
        switch self {
        case .desktop: "桌面上的大文件与杂项"
        case .downloads: "安装包、压缩包和重复下载"
        case .documents: "大型文档、归档与历史副本"
        }
    }

    var displayPath: String { (url.path as NSString).abbreviatingWithTildeInPath }
}
