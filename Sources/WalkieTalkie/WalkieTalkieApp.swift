import AppKit
import SwiftUI
import Carbon
import Combine

@main enum WalkieTalkieApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let store = AppStore()
    private let updater = UpdateManager()
    private var window: NSWindow!
    private var settingsWindow: NSWindow?
    private var selectionService: SelectionTranslationService?
    private var statusItem: NSStatusItem!
    private var pinMenuItem: NSMenuItem?
    private var shortcutMenuItem: NSMenuItem?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "对讲机"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 440, height: 620)
        window.contentView = NSHostingView(rootView: TranslatorView(store: store))
        window.center()
        window.setFrameAutosaveName("TranslatorWindow")
        window.delegate = self
        store.showSettings = { [weak self] in self?.store.settingsTab = 0; self?.openSettings() }
        updater.showSettings = { [weak self] in self?.store.settingsTab = 1; self?.openSettings() }
        store.onShortcutChange = { [weak self] in self?.registerShortcut() }
        store.$pinned.sink { [weak self] value in self?.window?.level = value ? .floating : .normal }.store(in: &subscriptions)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wave.3.left.circle", accessibilityDescription: "对讲机")
        statusItem.button?.image?.isTemplate = true
        statusItem.menu = buildStatusMenu()
        registerShortcut()
        showTranslator()
        // Register only after windows and callbacks are ready, including on a cold service launch.
        let service = SelectionTranslationService { [weak self] text in
            guard let self else { return }
            self.store.source = .auto
            self.store.input = text
            self.showTranslator()
            self.store.translate()
        }
        selectionService = service
        NSApp.servicesProvider = service
        NSUpdateDynamicServices()
        updater.startIfConfigured()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showTranslator(); return true }
    func applicationWillTerminate(_ notification: Notification) { if let hotKey { UnregisterEventHotKey(hotKey) }; if let eventHandler { RemoveEventHandler(eventHandler) } }
    @objc func showTranslator() { NSApp.activate(ignoringOtherApps: true); window.deminiaturize(nil); window.makeKeyAndOrderFront(nil) }
    @objc func pasteAndShow() { store.paste(); showTranslator() }
    @objc func togglePinned() { store.pinned.toggle() }
    @objc func translateFromMenu() { showTranslator(); store.translate() }
    @objc func copyTranslation() {
        guard !store.output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.output, forType: .string)
    }
    @objc func clearTranslation() { store.clear() }
    @objc func openAPISettings() { store.settingsTab = 0; openSettings() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func openSettings() {
        if settingsWindow == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 602, height: 510), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "对讲机设置"
            panel.contentView = NSHostingView(rootView: SettingsView(store: store, updater: updater, selection: Binding(get: { self.store.settingsTab }, set: { self.store.settingsTab = $0 })))
            panel.isReleasedWhenClosed = false
            panel.center(); settingsWindow = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func registerShortcut() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if eventHandler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, context -> OSStatus in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in
                    if delegate.window.isKeyWindow { delegate.window.orderOut(nil) } else { delegate.showTranslator() }
                }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
        let combinations: [(UInt32, UInt32)] = [(UInt32(kVK_Space), UInt32(controlKey | optionKey)), (UInt32(kVK_Space), UInt32(cmdKey | shiftKey)), (UInt32(kVK_ANSI_T), UInt32(controlKey | shiftKey))]
        let selected = combinations[store.shortcut]
        let result = RegisterEventHotKey(selected.0, selected.1, EventHotKeyID(signature: 0x57414C4B, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        store.shortcutError = result == noErr ? nil : "此快捷键已被占用，请选择其他组合。"
    }
    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        func add(_ title: String, _ action: Selector, to parent: NSMenu, key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = parent.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        // Translation entry points.
        _ = add("打开对讲机", #selector(showTranslator), to: menu)
        _ = add("粘贴并打开", #selector(pasteAndShow), to: menu)
        menu.addItem(.separator())
        // Window behavior and all shortcut references live together.
        pinMenuItem = add("窗口置顶", #selector(togglePinned), to: menu)
        let shortcutItem = NSMenuItem(title: "快捷键", action: nil, keyEquivalent: "")
        let shortcuts = NSMenu(title: "快捷键")
        shortcuts.delegate = self
        shortcutMenuItem = shortcuts.addItem(withTitle: "", action: nil, keyEquivalent: "")
        shortcuts.addItem(.separator())
        _ = add("翻译", #selector(translateFromMenu), to: shortcuts, key: "\r")
        _ = add("复制译文", #selector(copyTranslation), to: shortcuts, key: "c", modifiers: [.command, .shift])
        _ = add("清空原文和译文", #selector(clearTranslation), to: shortcuts, key: "k")
        shortcuts.addItem(.separator())
        _ = add("快捷键设置…", #selector(openAPISettings), to: shortcuts, key: ",")
        shortcutItem.submenu = shortcuts
        menu.addItem(shortcutItem)
        menu.addItem(.separator())
        // App preferences and maintenance.
        _ = add("API 设置…", #selector(openAPISettings), to: menu)
        let update = menu.addItem(withTitle: "检查更新…", action: #selector(UpdateManager.checkForUpdates(_:)), keyEquivalent: "")
        update.target = updater
        menu.addItem(.separator())
        _ = add("退出对讲机", #selector(quit), to: menu, key: "q")
        menuNeedsUpdate(menu)
        return menu
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        pinMenuItem?.state = store.pinned ? .on : .off
        let status = store.shortcutError == nil ? "" : "（被占用）"
        shortcutMenuItem?.title = "呼出 / 隐藏窗口  \(store.shortcutLabel)\(status)"
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(translateFromMenu): return store.canTranslate && !store.busy
        case #selector(copyTranslation): return !store.output.isEmpty
        case #selector(clearTranslation): return !store.input.isEmpty || !store.output.isEmpty || store.error != nil
        case #selector(togglePinned):
            menuItem.state = store.pinned ? .on : .off
            return true
        default: return true
        }
    }
    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于对讲机", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let updateItem = appMenu.addItem(withTitle: "检查更新…", action: #selector(UpdateManager.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updater
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ","); settings.target = self
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "服务")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏对讲机", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出对讲机", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem)
        let windowItem = NSMenuItem(); let menu = NSMenu(title: "窗口")
        menu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = menu; main.addItem(windowItem)
        NSApp.mainMenu = main; NSApp.windowsMenu = menu
    }
}
