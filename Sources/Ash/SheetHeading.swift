import SwiftUI

struct SheetHeading: View {
    let title: String
    let subtitle: String
    let symbol: String
    init(title: String, subtitle: String = "", symbol: String) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 21, weight: .regular)).foregroundStyle(ashAccent)
                .frame(width: 44, height: 44)
                .background(AshStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AshStyle.line))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 22, weight: .medium)).tracking(-0.4)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
