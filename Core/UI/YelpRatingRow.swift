import Foundation
import SwiftUI
import UIKit

struct RatingDisplayModel: Equatable {
    let rating: Double
    let reviewCount: Int?
    let source: String?
    let sourceURL: URL?

    var formattedRating: String {
        String(format: "%.1f", rating)
    }

    var formattedReviewCount: String? {
        guard let reviewCount, reviewCount > 0 else { return nil }
        let label = reviewCount == 1 ? "review" : "reviews"
        return "\(reviewCount) \(label)"
    }

    var formattedReviewCountShort: String? {
        guard let reviewCount, reviewCount > 0 else { return nil }
        if reviewCount >= 1000 {
            return String(format: "%.1fk", Double(reviewCount) / 1000.0)
        }
        return "\(reviewCount)"
    }

    var isYelp: Bool {
        source?.lowercased().contains("yelp") == true
    }
}

struct YelpRatingRow: View {
    enum Style {
        case inline
        case prominent
    }

    let model: RatingDisplayModel
    var style: Style = .prominent

    var body: some View {
        let row = HStack(spacing: rowSpacing) {
            sourceLabelView
            HStack(spacing: 6) {
                if model.isYelp {
                    YelpReviewRibbon(rating: model.rating, style: style)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "star.fill")
                        .font(starFont)
                        .foregroundStyle(Color.yellow)
                        .symbolRenderingMode(.hierarchical)
                }
                Text(model.formattedRating)
                    .font(ratingFont)
                    .fontWeight(.semibold)
            }
        }
        .padding(contentPadding)
        .background(backgroundShape)
        .frame(maxWidth: .infinity, alignment: .leading)

        if let url = model.sourceURL {
            Link(destination: url) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    @ViewBuilder
    private var sourceLabelView: some View {
        Text(sourceLabelText)
            .font(sourceFont)
            .foregroundStyle(.secondary)
    }

    private var ratingFont: Font {
        switch style {
        case .inline: .subheadline
        case .prominent: .headline
        }
    }

    private var starFont: Font {
        switch style {
        case .inline: .caption.weight(.semibold)
        case .prominent: .subheadline.weight(.semibold)
        }
    }

    private var sourceFont: Font {
        switch style {
        case .inline: .footnote
        case .prominent: .subheadline.weight(.semibold)
        }
    }

    private var sourceLabelText: String {
        let trimmedSource = model.source?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (trimmedSource?.isEmpty == false) ? trimmedSource! : "Rating"
        if let count = model.formattedReviewCountShort {
            return "\(base) (\(count))"
        }
        return base
    }

    private var rowSpacing: CGFloat {
        switch style {
        case .inline: 6
        case .prominent: 10
        }
    }

    @ViewBuilder
    private var backgroundShape: some View {
        switch style {
        case .inline:
            EmptyView()
        case .prominent:
            Color.primary.opacity(0.05)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var contentPadding: EdgeInsets {
        switch style {
        case .inline:
            .init(top: 0, leading: 0, bottom: 0, trailing: 0)
        case .prominent:
            .init(top: 8, leading: 12, bottom: 8, trailing: 12)
        }
    }
}

struct YelpReviewRibbon: View {
    let rating: Double
    let style: YelpRatingRow.Style

    var body: some View {
        if let ribbonImage {
            Image(uiImage: ribbonImage)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(height: ribbonHeight)
        } else {
            Color.clear
                .frame(width: ribbonHeight * ribbonAspectRatio, height: ribbonHeight)
        }
    }

    private var ribbonHeight: CGFloat {
        switch style {
        case .inline: 18
        case .prominent: 22
        }
    }

    private func assetName(for rating: Double) -> String {
        let clamped = max(0, min(5, rating))
        let rounded = (clamped * 2).rounded() / 2
        switch rounded {
        case 0: return "YelpReviewRibbon_0"
        case 0.5: return "YelpReviewRibbon_0_5"
        case 1: return "YelpReviewRibbon_1"
        case 1.5: return "YelpReviewRibbon_1_5"
        case 2: return "YelpReviewRibbon_2"
        case 2.5: return "YelpReviewRibbon_2_5"
        case 3: return "YelpReviewRibbon_3"
        case 3.5: return "YelpReviewRibbon_3_5"
        case 4: return "YelpReviewRibbon_4"
        case 4.5: return "YelpReviewRibbon_4_5"
        default: return "YelpReviewRibbon_5"
        }
    }

    private var ribbonImage: UIImage? {
        UIImage(named: assetName(for: rating), in: .main, compatibleWith: nil)?
            .withRenderingMode(.alwaysOriginal)
    }

    private var ribbonAspectRatio: CGFloat { 108.0 / 20.0 }
}

struct YelpAttributionBadge: View {
    let label: String
    let url: URL?
    var style: YelpRatingRow.Style = .inline

    var body: some View {
        let content = HStack(spacing: 6) {
            YelpLogoMark(style: .badge)
            Text(label)
                .font(labelFont)
                .foregroundStyle(.secondary)
        }

        if let url {
            Link(destination: url) { content }
        } else {
            content
        }
    }

    private var labelFont: Font {
        switch style {
        case .inline: .caption
        case .prominent: .caption2.weight(.semibold)
        }
    }
}

struct YelpLogoMark: View {
    enum Style {
        case badge
        case overlay
    }

    var style: Style = .badge

    var body: some View {
        Group {
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else {
                Text("Yelp")
                    .font(fallbackFont)
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: logoSize.width, height: logoSize.height)
        .padding(.horizontal, logoPadding.width)
        .padding(.vertical, logoPadding.height)
        .background(logoBackground, in: Capsule())
        .overlay(Capsule().stroke(logoBorder, lineWidth: logoBorderWidth))
        .shadow(color: logoShadow, radius: logoShadowRadius, y: logoShadowYOffset)
        .accessibilityHidden(true)
    }

    private var logoSize: CGSize {
        switch style {
        case .badge: return CGSize(width: 32, height: 16)
        case .overlay: return CGSize(width: 40, height: 16)
        }
    }

    private var logoPadding: CGSize {
        switch style {
        case .badge: return CGSize(width: 6, height: 4)
        case .overlay: return CGSize(width: 8, height: 6)
        }
    }

    private var logoBackground: Color {
        switch style {
        case .badge: return yelpRed
        case .overlay: return Color.black.opacity(0.55)
        }
    }

    private var logoBorder: Color {
        switch style {
        case .badge: return Color.clear
        case .overlay: return Color.white.opacity(0.2)
        }
    }

    private var logoBorderWidth: CGFloat {
        switch style {
        case .badge: return 0
        case .overlay: return 0.5
        }
    }

    private var logoShadow: Color {
        switch style {
        case .badge: return Color.clear
        case .overlay: return Color.black.opacity(0.4)
        }
    }

    private var logoShadowRadius: CGFloat {
        switch style {
        case .badge: return 0
        case .overlay: return 4
        }
    }

    private var logoShadowYOffset: CGFloat {
        switch style {
        case .badge: return 0
        case .overlay: return 2
        }
    }

    private var logoImage: UIImage? {
        UIImage(named: "YelpLogoWhite", in: .main, compatibleWith: nil)?
            .withRenderingMode(.alwaysOriginal)
    }

    private var fallbackFont: Font {
        switch style {
        case .badge: return .caption2.weight(.bold)
        case .overlay: return .caption.weight(.semibold)
        }
    }

    private var fallbackColor: Color { Color.white }

    private var yelpRed: Color {
        Color(red: 0.83, green: 0.14, blue: 0.14)
    }
}
