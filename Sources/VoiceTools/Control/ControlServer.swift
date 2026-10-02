import Foundation

/// The app's control socket, which `vp` talks to: `~/Library/Application Support/VoiceTools/control.sock`, readable
/// by this user only. One request per connection, as a JSON line: `{"cmd": "run", "args": {…}}`. The app answers
/// with JSON lines: any number of `{"type": "event", …}` (for `watch`, `listen`), then exactly one
/// `{"type": "result", "data": {…}}` or `{"type": "error", "code": …, "message": …, "hint": …}`.
enum ControlSocket {
    /// In Application Support, or a short per-user path in /tmp when that would exceed a socket path's 104 bytes.
    static var url: URL {
        let preferred = TrackStore.defaultURL.deletingLastPathComponent().appendingPathComponent("control.sock")
        return preferred.path.utf8.count < 100 ? preferred : URL(fileURLWithPath: "/tmp/voicepipes-\(getuid()).sock")
    }
}

/// Sends JSON lines back on one connection. Safe to call from any thread.
final class ControlReply: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var closed = false

    init(fd: Int32) { self.fd = fd }

    func event(_ data: [String: Any]) { send(["type": "event"].merging(data) { a, _ in a }) }

    func result(_ data: [String: Any] = [:]) {
        send(["type": "result", "data": data])
        close()
    }

    func error(_ code: String, _ message: String, hint: String? = nil) {
        var payload: [String: Any] = ["type": "error", "code": code, "message": message]
        if let hint { payload["hint"] = hint }
        send(payload)
        close()
    }

    /// False once the other end has gone (e.g. `vp watch` was interrupted).
    var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return !closed
    }

    private func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        let written = data.withUnsafeBytes { raw in Darwin.write(fd, raw.baseAddress, raw.count) }
        if written < 0 { closed = true; Darwin.close(fd) }
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        Darwin.close(fd)
    }
}

/// Listens on the control socket and hands each request to `handle` on the main actor.
final class ControlServer: @unchecked Sendable {
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "VoicePipes.control")
    private var source: DispatchSourceRead?
    private let handle: @MainActor (_ cmd: String, _ args: [String: Any], _ reply: ControlReply) -> Void

    init(handle: @escaping @MainActor (_ cmd: String, _ args: [String: Any], _ reply: ControlReply) -> Void) {
        self.handle = handle
    }

    func start() {
        // A client that hangs up early (vp's "is the app running?" probe does) must not kill the app with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        let path = ControlSocket.url.path
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return NSLog("VoicePipes: control socket failed: \(errno)") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return NSLog("VoicePipes: control socket path too long") }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, size) } }
        guard bound == 0, listen(listenFD, 16) == 0 else { return NSLog("VoicePipes: control socket bind/listen failed: \(errno)") }
        chmod(path, 0o600)
        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
        self.source = source
    }

    private func accept() {
        let fd = Darwin.accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        queue.async { [weak self] in self?.readRequest(fd) }
    }

    private func readRequest(_ fd: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !buffer.contains(0x0A) {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.count > 4_000_000 { break }
        }
        let reply = ControlReply(fd: fd)
        guard !buffer.isEmpty else { return reply.close() }  // a probe: connected and hung up
        let line = buffer.firstIndex(of: 0x0A).map { buffer[buffer.startIndex..<$0] } ?? buffer
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let cmd = object["cmd"] as? String else {
            return reply.error("bad_request", "Expected one JSON line: {\"cmd\": …, \"args\": {…}}")
        }
        let args = object["args"] as? [String: Any] ?? [:]
        let handle = self.handle
        Task { @MainActor in handle(cmd, args, reply) }
    }

    func stop() {
        source?.cancel()
        if listenFD >= 0 { Darwin.close(listenFD) }
        unlink(ControlSocket.url.path)
    }
}
