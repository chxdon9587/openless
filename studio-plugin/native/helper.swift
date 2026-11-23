import AppKit
import AVFoundation
import Security
import ApplicationServices

struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }
let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.ulanzi.openless.dictation", kSecAttrAccount as String: "openai"]
func credential() throws -> Data {
    var query = item
    query[kSecReturnData as String] = true
    var value: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
          let data = value as? Data else { throw Failure("请先配置 API Key") }
    return data
}
func configure() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    let dialog = NSAlert()
    dialog.messageText = "OpenLess 听写 · OpenAI API Key"
    dialog.informativeText = "音频和转写将发送至 OpenAI。密钥保存在本机钥匙串。"
    let field = NSSecureTextField(frame: NSRect(x: 0,y: 0,width: 360,height: 26))
    dialog.accessoryView = field
    dialog.addButton(withTitle: "保存")
    dialog.addButton(withTitle: "取消")
    dialog.window.initialFirstResponder = field
    guard dialog.runModal() == .alertFirstButtonReturn else { return }
    let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { throw Failure("密钥为空") }
    let values = [kSecValueData as String: Data(key.utf8)]
    var status = SecItemUpdate(item as CFDictionary, values as CFDictionary)
    if status == errSecItemNotFound {
        status = SecItemAdd(item.merging(values) { _, new in new } as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw Failure("钥匙串保存失败") }
    print("已保存")
}
func record(_ path: String) throws {
    let target = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
        let done = DispatchSemaphore(value: 0)
        var granted = false
        AVCaptureDevice.requestAccess(for: .audio) { allowed in
            granted = allowed
            done.signal()
        }
        done.wait()
        guard granted else { throw Failure("请在系统设置允许麦克风") }
        // Release is buffered on stdin while the system permission dialog is open.
        var input = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        if poll(&input, 1, 0) != 0 { throw Failure("已授权，请重新按住") }
    }
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw Failure("请在系统设置允许麦克风") }
    let recorder = try AVAudioRecorder(url: URL(fileURLWithPath: path), settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
    guard recorder.record() else { throw Failure("麦克风启动失败") }
    print(target); fflush(stdout)
    _ = readLine()
    recorder.stop()
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
    case "credential": FileHandle.standardOutput.write(try credential())
    case "record" where args.count == 2: try record(args[1])
    case "paste" where args.count == 2: try paste(args[1])
    default: throw Failure("未知操作")
    }
} catch {
    let message = (error as? Failure)?.message ?? "原生操作失败"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
