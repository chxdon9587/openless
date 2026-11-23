import AppKit
import AVFoundation
import Darwin

// A private stream ties recording to the Studio session. EOF stops capture if Studio exits.
let args = Array(CommandLine.arguments.dropFirst())
if args.count == 1 && args[0] == "--check" {
    print(Bundle.main.bundleIdentifier ?? "unknown")
    exit(0)
}
guard args.count == 2 else { exit(2) }
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let bytes = Array(args[0].utf8CString)
guard fd >= 0, bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { exit(2) }
withUnsafeMutableBytes(of: &addr.sun_path) { ptr in bytes.withUnsafeBytes { ptr.copyBytes(from: $0) } }
let size = socklen_t(MemoryLayout<sockaddr_un>.size)
let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
}
guard connected == 0 else { exit(2) }
signal(SIGPIPE, SIG_IGN)
let channel = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
func status(_ line: String) { try? channel.write(contentsOf: Data((line + "\n").utf8)) }
let target = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
    status("permission")
    let done = DispatchSemaphore(value: 0)
    AVCaptureDevice.requestAccess(for: .audio) { _ in done.signal() }
    done.wait()
}
guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
    status("denied"); exit(1)
}
var input = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
guard poll(&input, 1, 0) == 0 else { status("released"); exit(0) }
do {
    let recorder = try AVAudioRecorder(url: URL(fileURLWithPath: args[1]), settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
    recorder.isMeteringEnabled = true
    guard recorder.record() else { status("unavailable"); exit(1) }
    status("ready " + String(target))
    // A release or a disconnected Studio socket wakes poll immediately.
    while poll(&input, 1, 50) == 0 {
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let level = max(0, min(1, (db + 55) / 49))
        status("level " + String(Int(level * 100)))
    }
    recorder.stop()
    status("done")
} catch { status("unavailable") }
