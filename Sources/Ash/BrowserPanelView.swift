import Darwin
import SwiftUI
import WebKit

struct BrowserPanelView: View {
    @ObservedObject var model: PanelBrowserModel
    let address: String
    let host: Host
    @State private var editingAddress = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    model.webView.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }.disabled(!model.canGoBack).help("后退").accessibilityLabel("后退")
                Button {
                    model.webView.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }.disabled(!model.canGoForward).help("前进").accessibilityLabel("前进")
                Button {
                    Task { await model.reload(host: host) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("刷新网页").accessibilityLabel("刷新网页")
                TextField("端口号或网址", text: $editingAddress).textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced)).padding(8).ashField()
                    .accessibilityLabel("端口号或网址")
                    .onSubmit { Task { await model.navigate(editingAddress, host: host) } }
                Button {
                    if let url = model.webView.url { NSWorkspace.shared.open(url) }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .disabled(model.webView.url == nil).help("在浏览器中打开").accessibilityLabel("在浏览器中打开")
            }.buttonStyle(AshIconButtonStyle()).padding(8).background(AshStyle.chrome)
            if model.forwarded {
                Label("已连接 \(host.name) · SSH 端口转发", systemImage: "link").font(.system(size: 10)).foregroundStyle(
                    .secondary
                ).padding(.bottom, 8)
            }
            Divider()
            if let error = model.error {
                VStack(spacing: 0) {
                    PanelPlaceholder(title: "无法打开预览", symbol: "network.slash", detail: error)
                    Button("重试") { Task { await model.navigate(editingAddress, host: host) } }.padding(.bottom, 24)
                }
            } else {
                BrowserSurface(model: model).overlay(alignment: .top) {
                    if model.loading { ProgressView().progressViewStyle(.linear).frame(height: 2) }
                }
            }
        }.onAppear {
            editingAddress = model.address.isEmpty ? address : model.address
            Task { await model.start(address: address, host: host) }
        }
        .onChange(of: model.address) { _, value in editingAddress = value }
    }
}
struct BrowserSurface: NSViewRepresentable {
    let model: PanelBrowserModel
    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
