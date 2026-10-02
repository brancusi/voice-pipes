import AppKit
import Foundation

/// Talks to the running app over its control socket, starting the app in the background when it isn't running.
enum AppClient {
    struct Failure: Error {
        let code: String
        let message: String
        let hint: String?
    }

    static var isRunning: Bool { connect() .map { close($0); return true } ?? false }

    /// Sends one request; `onEvent` gets each event line; returns the result data or throws the app's error.
    @discardableResult
    static func request(_ cmd: String, _ args: [String: Any] = [:], launch: Bool = true,
                        onEvent: ([String: Any]) -> Void = { _ in }) throws -> [String: Any] {
        var fd = connect()
        if fd == nil, launch {
            try launchApp()
            let deadline = Date().addingTimeInterval(20)
            while fd == nil, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
                fd = connect()
            }
        }
        guard let fd else {
            throw Failure(code: "app_not_running", message: "Voice Pipes isn't running.", hint: "open -a \"Voice Pipes\"")
        }
        defer { close(fd) }
        var line = try JSONSerialization.data(withJSONObject: ["cmd": cmd, "args": args])
        line.append(0x0A)
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            while let newline = buffer.firstIndex(of: 0x0A) {
                let data = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                switch object["type"] as? String {
                case "event": onEvent(object)
                case "error":
                    throw Failure(code: object["code"] as? String ?? "failed", message: object["message"] as? String ?? "Failed.",
                                  hint: object["hint"] as? String)
                default: return object["data"] as? [String: Any] ?? [:]
                }
            }
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { throw Failure(code: "app_closed", message: "Voice Pipes closed the connection.", hint: "vp status") }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }

    private static func connect() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(ControlSocket.url.path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes.prefix(raw.count - 1))
            raw[min(bytes.count, raw.count - 1)] = 0
        }
        let ok = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return nil }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    /// The .app this binary belongs to (resolving the `vp` symlink).
    static var bundleURL: URL? {
        // Not argv[0]: run from PATH that's a bare "vp".
        let exe = CLIInstaller.executable
        let candidate = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if candidate.pathExtension == "app" { return candidate }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.github.brancusi.voice-tools")
    }

    private static func launchApp() throws {
        guard let app = bundleURL else {
            throw Failure(code: "app_not_found", message: "Can't find Voice Pipes.app.", hint: "Install it from https://github.com/brancusi/voice-tools-releases/releases/latest/download/Voice-Pipes.dmg")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-a", app.path]  // in the background: no focus stolen
        try process.run()
        process.waitUntilExit()
    }
}
