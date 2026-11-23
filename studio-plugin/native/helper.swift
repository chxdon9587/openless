import AppKit
import ApplicationServices

struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }
func configure() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    let dialog = NSAlert()
    dialog.messageText = "OpenLess 听写 · OpenAI API Key"
    dialog.informativeText = "音频和转写将发送至 OpenAI。密钥加密保存到 Studio 全局设置。"
    let field = NSSecureTextField(frame: NSRect(x: 0,y: 0,width: 360,height: 26))
    dialog.accessoryView = field
    dialog.addButton(withTitle: "保存")
    dialog.addButton(withTitle: "取消")
    dialog.window.initialFirstResponder = field
    guard dialog.runModal() == .alertFirstButtonReturn else { return }
    let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { throw Failure("密钥为空") }
    FileHandle.standardOutput.write(Data(key.utf8))
}
func paste(_ target: String) throws {
    guard let text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8), !text.isEmpty else { throw Failure("文本为空") }
    let board = NSPasteboard.general
    board.clearContents()
    guard board.setString(text, forType: .string) else { throw Failure("复制失败") }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == Int32(target),
          AXIsProcessTrusted(), let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { print("已复制，请粘贴"); return }
    for event in [down, up] { event.flags = .maskCommand; event.post(tap: .cghidEventTap) }
    print("已发送粘贴")
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
