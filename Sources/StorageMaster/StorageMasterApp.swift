import SwiftUI
import AppKit
import StorageCore

@main
struct DiskLensApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1060, minHeight: 740)
                .preferredColorScheme(.light)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.refreshCapacity()
                }
                .onAppear {
                    if let index = CommandLine.arguments.firstIndex(of: "--scan"),
                       CommandLine.arguments.indices.contains(index + 1), model.result == nil, !model.scanning {
                        model.scan(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.string("选择扫描文件夹…", language: model.language)) { model.chooseFolder() }.keyboardShortcut("o")
                Button(L10n.string("重新扫描", language: model.language)) { model.scan() }.keyboardShortcut("r").disabled(model.busy)
            }
            CommandGroup(replacing: .appInfo) {
                Button(L10n.string("关于盘点 · DiskLens", language: model.language)) { NSApplication.shared.orderFrontStandardAboutPanel(nil) }
            }
            CommandGroup(replacing: .textFormatting) {}
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.trimMenus() }
    }
    func applicationDidUpdate(_ notification: Notification) { trimMenus() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func trimMenus() {
        guard let mainMenu = NSApp.mainMenu,
              mainMenu.items.count >= 4,
              let fileMenu = mainMenu.items[1].submenu,
              fileMenu.items.contains(where: { $0.action == #selector(NSWindow.performClose(_:)) }),
              mainMenu.items.contains(where: {
                  $0.submenu?.items.contains(where: { $0.action == #selector(NSWindow.performMiniaturize(_:)) }) == true
              }),
              mainMenu.items.contains(where: {
                  $0.submenu?.items.contains(where: { $0.action == NSSelectorFromString("showHelp:") }) == true
              }) else { return }
        if !fileMenu.items.contains(where: { $0.tag == 0xD15C }) {
            let shortcuts: [(String, Selector, NSEvent.ModifierFlags)] = [
                ("z", NSSelectorFromString("undo:"), .command),
                ("z", NSSelectorFromString("redo:"), [.command, .shift]),
                ("x", #selector(NSText.cut(_:)), .command),
                ("c", #selector(NSText.copy(_:)), .command),
                ("v", #selector(NSText.paste(_:)), .command),
                ("a", #selector(NSText.selectAll(_:)), .command)
            ]
            for (key, action, modifiers) in shortcuts {
                let item = NSMenuItem(title: "", action: action, keyEquivalent: key)
                item.keyEquivalentModifierMask = modifiers
                item.isHidden = true
                item.allowsKeyEquivalentWhenHidden = true
                item.tag = 0xD15C
                fileMenu.addItem(item)
            }
        }
        if let editMenu = mainMenu.items.first(where: { item in
            item.submenu?.items.contains(where: {
                $0.action == NSSelectorFromString("undo:") && !$0.isHidden
            }) == true
        }) {
            mainMenu.removeItem(editMenu)
        }
        for item in mainMenu.items.dropFirst(2) where item.submenu?.items.isEmpty == true {
            mainMenu.removeItem(item)
        }
    }
}
