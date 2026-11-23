import AppKit

final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

let mint = NSColor(srgbRed: 0.52, green: 0.94, blue: 0.82, alpha: 1)
final class Waveform: NSView {
    private var history = Array(repeating: CGFloat(0), count: 9)
    func reset() {
        history = history.map { _ in 0 }
        needsDisplay = true
    }
    func sample(_ level: Int) {
        let target = CGFloat(level) / 100
        let previous = history.last ?? 0
        history.removeFirst()
        history.append(previous + (target - previous) * (target > previous ? 0.88 : 0.48))
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let midpoint = CGFloat(history.count - 1) / 2
        for (index, amplitude) in history.enumerated() {
            let distance = abs(CGFloat(index) - midpoint) / midpoint
            let envelope = 1 - 0.48 * distance
            let height = 3 + sqrt(amplitude) * (bounds.height - 4) * envelope
            let rect = NSRect(x: CGFloat(index) * 4.7, y: (bounds.height - height) / 2, width: 3, height: height)
            mint.withAlphaComponent(0.94 - distance * 0.22).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let panel = StatusPanel(contentRect: NSRect(x: 0, y: 0, width: 122, height: 44),
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
surface.layer?.backgroundColor = NSColor(srgbRed: 0.085, green: 0.105, blue: 0.122, alpha: 1).cgColor
surface.layer?.borderWidth = 1
surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
surface.autoresizingMask = [.width, .height]
panel.contentView = surface

let icon = NSImageView(frame: NSRect(x: 13, y: 10, width: 18, height: 18))
surface.addSubview(icon)
let title = NSTextField(labelWithString: "")
title.font = .systemFont(ofSize: 13, weight: .medium)
title.textColor = .white
title.lineBreakMode = .byTruncatingTail
surface.addSubview(title)
let tile = NSView(frame: NSRect(x: 7, y: 6, width: 53, height: 32))
tile.wantsLayer = true
tile.layer?.cornerRadius = 10
tile.layer?.backgroundColor = mint.withAlphaComponent(0.12).cgColor
surface.addSubview(tile)
let chip = NSView(frame: NSRect(x: 66, y: 10, width: 49, height: 24))
chip.wantsLayer = true
chip.layer?.cornerRadius = 8
chip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
surface.addSubview(chip)
let clock = NSTextField(labelWithString: "")
clock.frame = NSRect(x: 66, y: 14, width: 49, height: 16)
clock.alignment = .center
clock.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
clock.textColor = NSColor.white.withAlphaComponent(0.83)
surface.addSubview(clock)
let wave = Waveform(frame: NSRect(x: 13, y: 10, width: 42, height: 24))
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
    tile.isHidden = !recording
    chip.isHidden = !recording
    title.isHidden = recording
    icon.isHidden = recording
    var symbol = "info.circle.fill"
    var color = NSColor.systemOrange
    var message = status
    switch status {
    case "准备录音": symbol = "mic"; color = .lightGray
    case "录音中", "录音中 · 再按结束":
        let start = ProcessInfo.processInfo.systemUptime
        clock.stringValue = "00:00"
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            let age = ProcessInfo.processInfo.systemUptime - start
            let sec = Int(age)
            clock.stringValue = String(format: "%02d:%02d", sec / 60, sec % 60)
        }
    case "识别中": symbol = "text.bubble"; color = .systemCyan; message = "正在转写"
    case "润色中": symbol = "sparkles"; color = .systemCyan; message = "正在润色"
    case "已输入": symbol = "checkmark.circle.fill"; color = mint
    default: break
    }
    icon.frame = NSRect(x: 14, y: 13, width: 18, height: 18)
    icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    icon.contentTintColor = color
    title.stringValue = message
    let width: CGFloat = recording ? 122 : min(screenFrame?.width ?? 500, max(100, ceil(title.intrinsicContentSize.width) + 54))
    title.frame = NSRect(x: 40, y: 12, width: width - 50, height: 20)
    if let frame = screenFrame {
        panel.setFrame(NSRect(x: round(frame.midX - width / 2), y: frame.minY + 22, width: width, height: 44), display: true)
    } else {
        panel.setContentSize(NSSize(width: width, height: 44))
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
