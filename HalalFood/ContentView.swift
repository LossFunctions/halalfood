import SwiftUI

// MARK: - App Tabs
enum AppTab: String, CaseIterable, Identifiable {
    case places, topRated, newSpots, favorites
    var id: String { rawValue }

    var title: String {
        switch self {
        case .places: return "Map"
        case .topRated: return "Top Rated"
        case .newSpots: return "New Spots"
        case .favorites: return "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .places: return "map"
        case .topRated: return "star.fill"
        case .newSpots: return "sparkles"
        case .favorites: return "heart.fill"
        }
    }
}

struct ContentView: View {
    @State private var selected: AppTab = .places

    var body: some View {
        Group {
            switch selected {
            case .places: PlacesScreen()
            case .topRated: TopRatedScreen()
            case .newSpots: NewSpotsScreen()
            case .favorites: FavoritesScreen()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
        // Custom bottom bar inspired by best practices (simple, clear, neutral)
        .safeAreaInset(edge: .bottom) {
            CustomTabBar(selection: $selected)
                .shadow(color: Theme.Colors.shadow.opacity(0.06), radius: 8, y: -1)
        }
    }
}

// MARK: - Screens (stubs, style-focused)
private struct PlacesScreen: View {
    var body: some View {
        ScreenScaffold(title: "Places") {
            ExamplePlaceList()
        }
    }
}

private struct TopRatedScreen: View {
    var body: some View {
        ScreenScaffold(title: "Top Rated") {
            ExamplePlaceList(sortLabel: "Rating")
        }
    }
}

private struct NewSpotsScreen: View {
    var body: some View {
        ScreenScaffold(title: "New Spots") {
            ExamplePlaceList(sortLabel: "New")
        }
    }
}

private struct FavoritesScreen: View {
    var body: some View {
        ScreenScaffold(title: "Favorites") {
            ExamplePlaceList(filterLabel: "Saved")
        }
    }
}

// MARK: - Reusable screen wrapper
private struct ScreenScaffold<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded).bold())
                .foregroundStyle(Theme.Colors.text)
                .padding(.top, 8)

            content
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Example list and card (neutral styles)
private struct ExamplePlaceList: View {
    var sortLabel: String? = nil
    var filterLabel: String? = nil

    private let examples: [(name: String, halal: HalalStatus, rating: Double)] = [
        ("Saffron Grill", .full, 4.6),
        ("Mediterranean Bites", .partial, 4.1),
        ("Green Olive", .full, 4.8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sortLabel { Chip(text: sortLabel, systemImage: "arrow.up.arrow.down") }
            if let filterLabel { Chip(text: filterLabel, systemImage: "line.3.horizontal.decrease.circle") }
            ForEach(Array(examples.enumerated()), id: \.offset) { _, item in
                PlaceCard(name: item.name, status: item.halal, rating: item.rating)
            }
        }
    }
}

private struct Chip: View {
    let text: String
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface)
        .clipShape(Capsule())
        .foregroundStyle(Theme.Colors.textSecondary)
    }
}

private struct PlaceCard: View {
    let name: String
    let status: HalalStatus
    let rating: Double

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Colors.imagePlaceholder)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.text)
                HStack(spacing: 8) {
                    StatusBadge(status: status)
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(Theme.Colors.accent)
                        Text(String(format: "%.1f", rating)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Previews
#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
