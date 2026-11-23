import AppKit

// A status panel must never become the destination for the user's dictation.
final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let panel = StatusPanel(contentRect: NSRect(x: 0, y: 0, width: 278, height: 52),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
panel.ignoresMouseEvents = true
panel.hidesOnDeactivate = false
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
let surface = NSView(frame: panel.frame)
surface.wantsLayer = true
surface.layer?.cornerRadius = 16
surface.layer?.backgroundColor = NSColor(srgbRed: 0.09, green: 0.12, blue: 0.16, alpha: 0.97).cgColor
panel.contentView = surface
let icon = NSImageView(frame: NSRect(x: 14, y: 14, width: 24, height: 24))
surface.addSubview(icon)
let label = NSTextField(labelWithString: "")
label.frame = NSRect(x: 49, y: 15, width: 215, height: 22)
label.font = .systemFont(ofSize: 15, weight: .medium)
label.textColor = .white
label.lineBreakMode = .byTruncatingTail
surface.addSubview(label)
let clock = NSTextField(labelWithString: "")
clock.frame = NSRect(x: 208, y: 15, width: 54, height: 21)
clock.alignment = .right
clock.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
clock.textColor = .lightGray
surface.addSubview(clock)
let screen = NSScreen.main ?? NSScreen.screens.first
if let frame = screen?.visibleFrame {
    panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 28))
}
var timer: Timer?
func show(_ status: String) {
    timer?.invalidate()
    clock.stringValue = ""
    var symbol = "info.circle"
    var color = NSColor.systemOrange
    var message = status
    switch status {
    case "准备录音": symbol = "mic"; color = .lightGray
    case "录音中", "录音中 · 再按结束":
        symbol = "mic.fill"; color = .systemRed; message = status == "录音中" ? "录音中 · 松开结束" : status
        let start = ProcessInfo.processInfo.systemUptime
        clock.stringValue = "00:00"
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            let sec = Int(ProcessInfo.processInfo.systemUptime - start)
            clock.stringValue = String(format: "%02d:%02d", sec / 60, sec % 60)
        }
    case "识别中": symbol = "text.bubble"; color = .systemCyan; message = "正在转写"
    case "润色中": symbol = "sparkles"; color = .systemCyan; message = "正在润色"
    case "已发送粘贴": symbol = "checkmark.circle.fill"; color = .systemGreen
    default: break
    }
    icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    icon.contentTintColor = color
    label.stringValue = message
    panel.orderFrontRegardless()
}
DispatchQueue.global().async {
    while let line = readLine() {
        DispatchQueue.main.async { show(line) }
    }
    DispatchQueue.main.async { app.terminate(nil) }
}
app.run()
