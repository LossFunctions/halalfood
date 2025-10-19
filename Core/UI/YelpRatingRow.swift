import SwiftUI

struct RatingDisplayModel: Equatable {
    let rating: Double
    let reviewCount: Int?
    let source: String?

    var formattedRating: String {
        String(format: "%.1f", rating)
    }

    var formattedReviewCount: String? {
        guard let reviewCount, reviewCount > 0 else { return nil }
        let label = reviewCount == 1 ? "review" : "reviews"
        return "\(reviewCount) \(label)"
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
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.yellow)
                .symbolRenderingMode(.hierarchical)

            Text(model.formattedRating)
                .font(ratingFont)
                .fontWeight(.semibold)

            if let reviewCount = model.formattedReviewCount {
                Text("• \(reviewCount)")
                    .font(reviewCountFont)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let source = model.source, !source.isEmpty {
                switch style {
                case .inline:
                    Text("via \(source)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .prominent:
                    Text("via \(source)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
        }
        .padding(contentPadding)
        .background(backgroundShape)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ratingFont: Font {
        switch style {
        case .inline: .subheadline
        case .prominent: .headline
        }
    }

    private var reviewCountFont: Font {
        switch style {
        case .inline: .footnote
        case .prominent: .subheadline
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
