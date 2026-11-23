import AppKit

final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

let mint = NSColor(srgbRed: 0.40, green: 0.94, blue: 0.75, alpha: 1)
final class Waveform: NSView {
    private var history = Array(repeating: CGFloat(0), count: 26)
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
            let rect = NSRect(x: CGFloat(index) * 4.3, y: (bounds.height - height) / 2, width: 2.7, height: height)
            mint.withAlphaComponent(0.4 + 0.6 * CGFloat(index) / CGFloat(history.count - 1)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.25, yRadius: 1.25).fill()
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let panel = StatusPanel(contentRect: NSRect(x: 0, y: 0, width: 214, height: 38),
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
surface.layer?.cornerRadius = 19
surface.layer?.backgroundColor = NSColor(srgbRed: 0.055, green: 0.080, blue: 0.087, alpha: 0.98).cgColor
surface.layer?.borderWidth = 1
surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.17).cgColor
surface.autoresizingMask = [.width, .height]
panel.contentView = surface

let icon = NSImageView(frame: NSRect(x: 13, y: 10, width: 18, height: 18))
surface.addSubview(icon)
let title = NSTextField(labelWithString: "")
title.font = .systemFont(ofSize: 13, weight: .medium)
title.textColor = .white
title.lineBreakMode = .byTruncatingTail
surface.addSubview(title)
let clock = NSTextField(labelWithString: "")
clock.frame = NSRect(x: 149, y: 10, width: 55, height: 17)
clock.alignment = .center
clock.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
clock.textColor = NSColor.white.withAlphaComponent(0.83)
surface.addSubview(clock)
let divider = NSBox(frame: NSRect(x: 147, y: 12, width: 1, height: 14))
divider.boxType = .separator
surface.addSubview(divider)
let wave = Waveform(frame: NSRect(x: 29, y: 6, width: 113, height: 26))
surface.addSubview(wave)

// Keep the capsule centred on the same screen throughout this dictation.
let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
var timer: Timer?
func show(_ status: String) {
    let recording = status == "录音中" || status == "录音中 · 再按结束"
    timer?.invalidate()
    wave.isHidden = !recording
    wave.reset()
    clock.isHidden = !recording
    divider.isHidden = !recording
    title.isHidden = recording
    var symbol = "info.circle.fill"
    var color = NSColor.systemOrange
    var message = status
    switch status {
    case "准备录音": symbol = "mic"; color = .lightGray
    case "录音中", "录音中 · 再按结束":
        symbol = "record.circle.fill"; color = mint
        let start = ProcessInfo.processInfo.systemUptime
        clock.stringValue = status == "录音中" ? "松开结束" : "再按结束"
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            let age = ProcessInfo.processInfo.systemUptime - start
            if age >= 1.5 {
                let sec = Int(age)
                clock.stringValue = String(format: "%02d:%02d", sec / 60, sec % 60)
            }
        }
    case "识别中": symbol = "text.bubble"; color = .systemCyan; message = "正在转写"
    case "润色中": symbol = "sparkles"; color = .systemCyan; message = "正在润色"
    case "已输入": symbol = "checkmark.circle.fill"; color = mint
    default: break
    }
    icon.frame = recording ? NSRect(x: 11, y: 13, width: 12, height: 12) : NSRect(x: 13, y: 10, width: 18, height: 18)
    icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    icon.contentTintColor = color
    title.stringValue = message
    let width: CGFloat = recording ? 214 : min(screenFrame?.width ?? 500, max(100, ceil(title.intrinsicContentSize.width) + 54))
    title.frame = NSRect(x: 37, y: 9, width: width - 47, height: 19)
    if let frame = screenFrame {
        panel.setFrame(NSRect(x: round(frame.midX - width / 2), y: frame.minY + 22, width: width, height: 38), display: true)
    } else {
        panel.setContentSize(NSSize(width: width, height: 38))
    }
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
