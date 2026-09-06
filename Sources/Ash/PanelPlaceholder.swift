import SwiftUI

struct PanelPlaceholder: View {
    let title: String
    let symbol: String
    let detail: String
    init(title: String, symbol: String, detail: String = "") {
        self.title = title
        self.symbol = symbol
        self.detail = detail
    }
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(.secondary).padding(.bottom, 4).accessibilityHidden(true)
            Text(title).font(.system(size: 14, weight: .medium))
            if !detail.isEmpty {
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    .multilineTextAlignment(.center).textSelection(.enabled)
            }
        }.frame(maxWidth: 280).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AshStyle.canvas)
    }
}
