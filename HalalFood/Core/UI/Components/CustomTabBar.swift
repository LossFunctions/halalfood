import SwiftUI
import UIKit

struct CustomTabBar: View {
    @Binding var selection: AppTab
    private var barHeight: CGFloat { max(44, UIScreen.main.bounds.height / 20) }

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Theme.Colors.outline)
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    Button(action: { selection = tab }) {
                        VStack(spacing: 6) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 20, weight: .semibold))
                            Text(tab.title)
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selection == tab ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .background(Theme.Colors.surface)
            .frame(height: barHeight) // ~1/20 of screen height
        }
        .background(Theme.Colors.surface)
        .frame(maxWidth: .infinity)
    }
}
