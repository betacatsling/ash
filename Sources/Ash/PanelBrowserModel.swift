import Darwin
import SwiftUI
import WebKit

@MainActor final class PanelTunnelRegistry {
    static let shared = PanelTunnelRegistry()
    private var processes: [UUID: Process] = [:]
    func add(_ process: Process, id: UUID) { processes[id] = process }
    func remove(_ id: UUID) { processes.removeValue(forKey: id) }
    func stopAll() {
        for process in processes.values where process.isRunning { process.terminate() }
        processes.removeAll()
    }
}

@MainActor final class PanelBrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var address = ""
    @Published var error: String?
    @Published var loading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var forwarded = false
    private var tunnel: Process?
    private var tunnelPort: Int?
    private var remoteURL: URL?
    private var generation = UUID()
    private var initialized = false
    private let tunnelID = UUID()
    override init() {
        let config = WKWebViewConfiguration()
        // Development previews do not share persistent cookies with other tabs.
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }
    deinit { if tunnel?.isRunning == true { tunnel?.terminate() } }
    func start(address: String, host: Host) async {
        guard !initialized else { return }
        initialized = true
        await navigate(address, host: host)
    }
    func stop() {
        generation = UUID()
        webView.stopLoading()
        if tunnel?.isRunning == true { tunnel?.terminate() }
        tunnel = nil
        tunnelPort = nil
        forwarded = false
        PanelTunnelRegistry.shared.remove(tunnelID)
    }
    func navigate(_ value: String, host: Host) async {
        stop()
        let token = generation
        loading = true
        error = nil
        do {
            let original = try PreviewAddress.url(value)
            address = original.absoluteString
            remoteURL = original
            var target = original
            if !host.isLocal, PreviewAddress.isLoopback(original) {
                guard validSSHAddress(host.address) else { throw AshError(message: "无效的 SSH 主机地址。") }
                let port = try Self.availablePort()
                let destination = ["::1", "[::1]"].contains(original.host ?? "") ? "[::1]" : "127.0.0.1"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments =
                    RuntimeClient.sshOptions + [
                        "-S", "none", "-o", "ControlMaster=no", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
                        "-N", "-T", "-L",
                        "127.0.0.1:\(port):\(destination):\(original.port ?? (original.scheme == "https" ? 443 : 80))",
                        host.address,
                    ]
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                process.environment = RuntimeClient.environment
                try process.run()
                tunnel = process
                PanelTunnelRegistry.shared.add(process, id: tunnelID)
                var ready = false
                for _ in 0..<150 {
                    try await Task.sleep(for: .milliseconds(100))
                    guard generation == token, !Task.isCancelled else { return }
                    guard process.isRunning else { throw AshError(message: "端口转发失败，请检查 SSH 连接和认证后重试。") }
                    if Self.portReady(port) {
                        ready = true
                        break
                    }
                }
                guard ready else { throw AshError(message: "连接远程端口超时，请检查主机后重试。") }
                tunnelPort = port
                forwarded = true
                var parts = URLComponents(url: original, resolvingAgainstBaseURL: false)!
                parts.host = "127.0.0.1"
                parts.port = port
                target = parts.url!
                process.terminationHandler = { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.error = "远程端口连接已断开，请重新连接。"
                        self.loading = false
                        self.forwarded = false
                    }
                }
            }
            guard generation == token, !Task.isCancelled else { return }
            webView.load(URLRequest(url: target, timeoutInterval: 30))
        } catch {
            guard generation == token else { return }
            stop()
            self.error = error.localizedDescription
            loading = false
        }
    }
    func reload(host: Host) async {
        if error != nil { await navigate(address, host: host) } else { webView.reload() }
    }
    private func update() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let url = webView.url {
            if let tunnelPort, url.port == tunnelPort, let remoteURL {
                var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
                parts?.host = remoteURL.host
                parts?.port = remoteURL.port
                address = parts?.url?.absoluteString ?? remoteURL.absoluteString
            } else {
                address = url.absoluteString
            }
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true
        error = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        update()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        self.error = error.localizedDescription
        loading = false
        update()
    }
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, ["http", "https", "about"].contains(url.scheme ?? "") else {
            decisionHandler(.cancel)
            return
        }
        if let tunnelPort, let remoteURL, PreviewAddress.isLoopback(url),
            url.port == remoteURL.port, url.port != tunnelPort
        {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            parts?.host = "127.0.0.1"
            parts?.port = tunnelPort
            if let mapped = parts?.url {
                var request = navigationAction.request
                request.url = mapped
                webView.load(request)
                decisionHandler(.cancel)
                return
            }
        }
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
    private static func availablePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AshError(message: "无法分配本地预览端口。") }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
        }
        guard bound == 0, named == 0 else { throw AshError(message: "无法分配本地预览端口。") }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
    private static func portReady(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
