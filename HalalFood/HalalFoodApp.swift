//
//  HalalFoodApp.swift
//  HalalFood
//
//  Created by Umi Hussaini on 9/18/25.
//

import SwiftUI
import UIKit

@main
struct HalalFoodApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

// MARK: - Root View with custom bottom bar (kept in this file so it always compiles in the app target)

private enum AppTab: String, CaseIterable, Identifiable {
    case places, topRated, newSpots, favorites
    var id: String { rawValue }
    var title: String {
        switch self {
        case .places: return "Places"
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

private struct AppRootView: View {
    @State private var selected: AppTab = .places

    var body: some View {
        Group {
            switch selected {
            case .places:
                ScreenScaffold(title: "Places") { ExamplePlaceList() }
            case .topRated:
                ScreenScaffold(title: "Top Rated") { ExamplePlaceList(sortLabel: "Rating") }
            case .newSpots:
                ScreenScaffold(title: "New Spots") { ExamplePlaceList(sortLabel: "New") }
            case .favorites:
                ScreenScaffold(title: "Favorites") { ExamplePlaceList(filterLabel: "Saved") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HFTheme.Colors.background.ignoresSafeArea())
        // Off‑white bottom bar ~1/20 of screen height
        .safeAreaInset(edge: .bottom) {
            HFCustomTabBar(selection: $selected)
                .shadow(color: .black.opacity(0.06), radius: 8, y: -1)
        }
    }
}

// MARK: - Components & Theme (inline for reliability)

private struct HFCustomTabBar: View {
    @Binding var selection: AppTab
    private var barHeight: CGFloat { max(44, UIScreen.main.bounds.height / 20) }

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(.black.opacity(0.06))
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
                        .foregroundStyle(selection == tab ? HFTheme.Colors.accent : HFTheme.Colors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .background(HFTheme.Colors.surface)
            .frame(height: barHeight)
        }
        .background(HFTheme.Colors.surface)
        .frame(maxWidth: .infinity)
    }
}

private enum HFTheme {
    enum Colors {
        static let accent = Color.teal // change to brand accent if needed
        static let background = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let text = Color.primary
        static let textSecondary = Color.secondary
        static let imagePlaceholder = Color.gray.opacity(0.3)

        // Reserved for halal status indicators only (not navigation)
        static let halalFull = Color(red: 0.18, green: 0.49, blue: 0.20)   // green
        static let halalPartial = Color(red: 0.90, green: 0.49, blue: 0.13) // orange
    }
}

private enum HFHalalStatus { case full, partial }

private struct HFStatusBadge: View {
    let status: HFHalalStatus
    var body: some View {
        let (label, fg, bg) = switch status {
        case .full: ("HALAL", HFTheme.Colors.halalFull, HFTheme.Colors.halalFull.opacity(0.12))
        case .partial: ("PARTIAL", HFTheme.Colors.halalPartial, HFTheme.Colors.halalPartial.opacity(0.12))
        }
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .overlay(Capsule().stroke(fg.opacity(0.4), lineWidth: 1))
            .clipShape(Capsule())
    }
}

private struct ScreenScaffold<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded).bold())
                .foregroundStyle(HFTheme.Colors.text)
                .padding(.top, 8)
            content
        }
        .padding(.horizontal, 20)
    }
}

private struct ExamplePlaceList: View {
    var sortLabel: String? = nil
    var filterLabel: String? = nil

    private let examples: [(name: String, halal: HFHalalStatus, rating: Double)] = [
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
        .background(HFTheme.Colors.surface)
        .clipShape(Capsule())
        .foregroundStyle(HFTheme.Colors.textSecondary)
    }
}

private struct PlaceCard: View {
    let name: String
    let status: HFHalalStatus
    let rating: Double

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(HFTheme.Colors.imagePlaceholder)
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "photo").font(.title3).foregroundStyle(.white.opacity(0.7)))

            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(HFTheme.Colors.text)
                HStack(spacing: 8) {
                    HFStatusBadge(status: status)
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(HFTheme.Colors.accent)
                        Text(String(format: "%.1f", rating)).foregroundStyle(HFTheme.Colors.textSecondary)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            Spacer()
        }
        .padding(12)
        .background(HFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
