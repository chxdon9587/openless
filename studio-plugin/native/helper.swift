import AppKit
import ApplicationServices

struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }
final class KeyEntry: NSView, NSTextFieldDelegate {
    let masked = NSSecureTextField()
    private let plain = NSTextField()
    private let toggle = NSButton(checkboxWithTitle: "显示密钥", target: nil, action: nil)
    private let save: NSButton
    private var active: NSTextField { toggle.state == .on ? plain : masked }
    var value: String { active.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(save: NSButton, provider: String) {
        self.save = save
        super.init(frame: NSRect(x: 0, y: 0, width: 364, height: 94))
        let label = NSTextField(labelWithString: "\(provider) API Key")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.frame = NSRect(x: 0, y: 71, width: 360, height: 20)
        addSubview(label)
        for field in [masked as NSTextField, plain] {
            field.frame = NSRect(x: 0, y: 34, width: 364, height: 30)
            field.controlSize = .large
            field.bezelStyle = .roundedBezel
            field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            field.placeholderString = "粘贴你的 API Key"
            field.setAccessibilityLabel("\(provider) API Key")
            field.delegate = self
            addSubview(field)
        }
        plain.isHidden = true
        toggle.frame = NSRect(x: 0, y: 4, width: 130, height: 22)
        toggle.target = self
        toggle.action = #selector(switchVisibility)
        addSubview(toggle)
        save.isEnabled = false
    }
    required init?(coder: NSCoder) { nil }

    @objc private func switchVisibility() {
        let previous = toggle.state == .on ? masked : plain
        let text = previous.stringValue
        previous.isHidden = true
        active.stringValue = text
        active.isHidden = false
        window?.makeFirstResponder(active)
        previous.stringValue = ""
        save.isEnabled = !value.isEmpty
    }
    func controlTextDidChange(_ notification: Notification) { save.isEnabled = !value.isEmpty }
}
func configure() throws {
    let provider = CommandLine.arguments.dropFirst(2).first ?? "OpenAI"
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    // An accessory process needs an Edit menu for standard paste shortcuts.
    let menu = NSMenu()
    let edit = NSMenuItem()
    menu.addItem(edit)
    let commands = NSMenu(title: "编辑")
    commands.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    commands.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    edit.submenu = commands
    app.mainMenu = menu
    app.finishLaunching()
    app.activate(ignoringOtherApps: true)
    let dialog = NSAlert()
    let plugin = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
    if let icon = NSImage(contentsOf: plugin.appendingPathComponent("assets/openless.png")) { dialog.icon = icon }
    dialog.messageText = "配置听写密钥"
    let usage: String
    switch provider {
    case "豆包语音（识别）": usage = "录音将发送至豆包语音做识别。请输入新版豆包语音控制台签发的 API Key。"
    case "火山方舟（润色）": usage = "转写文字将发送至北京区火山方舟做润色。请输入方舟控制台签发的 API Key。"
    default: usage = "听写音频和转写文本将发送至 \(provider)。"
    }
    dialog.informativeText = usage + "密钥加密保存在 Studio 全局设置，所有听写按键共用。"
    let save = dialog.addButton(withTitle: "保存密钥")
    dialog.addButton(withTitle: "取消")
    let entry = KeyEntry(save: save, provider: provider)
    dialog.accessoryView = entry
    dialog.window.initialFirstResponder = entry.masked
    guard dialog.runModal() == .alertFirstButtonReturn else { return }
    guard !entry.value.isEmpty else { throw Failure("密钥为空") }
    FileHandle.standardOutput.write(Data(entry.value.utf8))
}
func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &result) == .success else { return nil }
    return result
}
func selection(_ element: AXUIElement) -> CFRange? {
    guard let value = attribute(element, kAXSelectedTextRangeAttribute as CFString),
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var range = CFRange()
    return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
}
// Read back only the inserted range. Some editors do not implement this AX operation.
func confirmsInsertion(_ element: AXUIElement, at offset: Int, text: String) -> Bool {
    var range = CFRange(location: offset, length: text.utf16.count)
    guard let position = selection(element), position.length == 0,
          position.location == offset + range.length,
          let parameter = AXValueCreate(.cfRange, &range) else { return false }
    var result: CFTypeRef?
    return AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                       parameter, &result) == .success && result as? String == text
}
// Find the application's standard Command-V item by accelerator so this works across UI languages.
func pasteMenuItem(in app: AXUIElement) -> AXUIElement? {
    guard let menu = attribute(app, kAXMenuBarAttribute as CFString),
          CFGetTypeID(menu) == AXUIElementGetTypeID() else { return nil }
    func children(_ e: AXUIElement) -> [AXUIElement] {
        attribute(e, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    }
    for top in children(menu as! AXUIElement) {
        for submenu in children(top) {
            for item in children(submenu) {
                guard let key = attribute(item, kAXMenuItemCmdCharAttribute as CFString) as? String,
                      key.lowercased() == "v",
                      let modifiers = attribute(item, kAXMenuItemCmdModifiersAttribute as CFString) as? NSNumber,
                      modifiers.intValue == 0,
                      (attribute(item, kAXEnabledAttribute as CFString) as? Bool) == true else { continue }
                return item
            }
        }
    }
    return nil
}
func paste(_ target: String) throws {
    guard let text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8), !text.isEmpty else { throw Failure("文本为空") }
    let board = NSPasteboard.general
    board.clearContents()
    guard board.setString(text, forType: .string) else { throw Failure("复制失败") }
    guard let pid = Int32(target), pid > 0, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
        print("焦点已切换 · 请按 ⌘V"); return
    }
    guard AXIsProcessTrusted() else { print("缺少辅助功能权限 · 请按 ⌘V"); return }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.2)
    let focus = attribute(app, kAXFocusedUIElementAttribute as CFString)
    let field = focus.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    let original = field.flatMap(selection)
    if let field, let role = attribute(field, kAXRoleAttribute as CFString) as? String,
       [kAXButtonRole, kAXMenuItemRole, kAXCheckBoxRole, kAXRadioButtonRole].contains(role) {
        print("请点击输入框 · 再按 ⌘V"); return
    }
    // Chromium may acknowledge an AXSelectedText write without firing an input event.
    // Deliver one ordinary Paste through the foreground event stream, then verify separately.
    let item = pasteMenuItem(in: app)
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
        print("焦点已切换 · 请按 ⌘V"); return
    }
    let menuStatus = item.map { AXUIElementPerformAction($0, kAXPressAction as CFString) }
    if menuStatus != .success && menuStatus != .cannotComplete {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            print("已复制 · 请按 ⌘V"); return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.02)
        up.post(tap: .cghidEventTap)
    }
    if let field, let original {
        for _ in 0..<5 {
            if confirmsInsertion(field, at: original.location, text: text) { print("已输入"); return }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
    print("请检查输入框 · 内容已复制")
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "configure": try configure()
    case "paste" where args.count == 2: try paste(args[1])
    default: throw Failure("未知操作")
    }
} catch {
    let message = (error as? Failure)?.message ?? "原生操作失败"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
