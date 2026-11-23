import AppKit

final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

let mint = NSColor(srgbRed: 0.40, green: 0.94, blue: 0.75, alpha: 1)
final class Waveform: NSView {
    private var history = Array(repeating: CGFloat(0), count: 22)
    func reset() {
        history = history.map { _ in 0 }
        needsDisplay = true
    }
    func sample(_ level: Int) {
        let target = CGFloat(level) / 100
        let previous = history.last ?? 0
        history.removeFirst()
        history.append(previous + (target - previous) * (target > previous ? 0.85 : 0.52))
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        for (index, amplitude) in history.enumerated() {
            let height = max(2, amplitude * (bounds.height - 2))
            let rect = NSRect(x: CGFloat(index) * 4, y: (bounds.height - height) / 2, width: 2.5, height: height)
            mint.withAlphaComponent(0.4 + 0.6 * CGFloat(index) / CGFloat(history.count - 1)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.25, yRadius: 1.25).fill()
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let panel = StatusPanel(contentRect: NSRect(x: 0, y: 0, width: 314, height: 62),
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
surface.layer?.cornerRadius = 18
surface.layer?.backgroundColor = NSColor(srgbRed: 0.063, green: 0.098, blue: 0.11, alpha: 0.97).cgColor
surface.layer?.borderWidth = 1
surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
panel.contentView = surface
let tile = NSView(frame: NSRect(x: 12, y: 12, width: 38, height: 38))
tile.wantsLayer = true
tile.layer?.cornerRadius = 12
surface.addSubview(tile)
let icon = NSImageView(frame: NSRect(x: 8, y: 8, width: 22, height: 22))
tile.addSubview(icon)
func label(_ frame: NSRect, size: CGFloat, color: NSColor) -> NSTextField {
    let text = NSTextField(labelWithString: "")
    text.frame = frame
    text.font = .systemFont(ofSize: size, weight: .medium)
    text.textColor = color
    text.lineBreakMode = .byTruncatingTail
    surface.addSubview(text)
    return text
}
let title = label(NSRect(x: 60, y: 30, width: 140, height: 21), size: 15, color: .white)
let detail = label(NSRect(x: 60, y: 10, width: 144, height: 17), size: 12, color: .lightGray)
let clock = label(NSRect(x: 237, y: 34, width: 61, height: 17), size: 12, color: mint)
clock.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
clock.alignment = .right
let wave = Waveform(frame: NSRect(x: 211, y: 8, width: 88, height: 27))
surface.addSubview(wave)
if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
    panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 28))
}
var timer: Timer?
func show(_ status: String) {
    let recording = status == "录音中" || status == "录音中 · 再按结束"
    timer?.invalidate()
    wave.isHidden = !recording
    wave.reset()
    clock.isHidden = !recording
    title.frame = NSRect(x: 60, y: recording ? 30 : 19, width: recording ? 144 : 245, height: 22)
    title.stringValue = status
    detail.isHidden = !recording
    var symbol = "info.circle"
    var color = NSColor.systemOrange
    switch status {
    case "准备录音": symbol = "mic"; color = .lightGray
    case "录音中", "录音中 · 再按结束":
        symbol = "mic.fill"; color = mint
        title.stringValue = "正在听写"
        detail.stringValue = status == "录音中" ? "松开按键结束" : "再按一次结束"
        let start = ProcessInfo.processInfo.systemUptime
        clock.stringValue = "00:00"
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            let sec = Int(ProcessInfo.processInfo.systemUptime - start)
            clock.stringValue = String(format: "%02d:%02d", sec / 60, sec % 60)
        }
    case "识别中": symbol = "text.bubble"; color = .systemCyan; title.stringValue = "正在转写"
    case "润色中": symbol = "sparkles"; color = .systemCyan; title.stringValue = "正在润色"
    case "已输入": symbol = "checkmark"; color = mint
    default: break
    }
    icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    icon.contentTintColor = color
    tile.layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor
    panel.orderFrontRegardless()
}
DispatchQueue.global().async {
    while let line = readLine() {
        DispatchQueue.main.async {
            if line.hasPrefix("level ") {
                if !wave.isHidden, let n = Int(line.dropFirst(6)), (0...100).contains(n) { wave.sample(n) }
            } else { show(line) }
        }
    }
    DispatchQueue.main.async { app.terminate(nil) }
}
app.run()
