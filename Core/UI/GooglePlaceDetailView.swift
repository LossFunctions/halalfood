import SwiftUI

struct GooglePlaceDetailView: View {
    let place: Place
    let googleData: GooglePlaceData?
    let googleErrorMessage: String?

    private static let iconColor = Color(red: 0x1f/255, green: 0x1f/255, blue: 0x1f/255)

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            detailsSection

            if let url = directionsURL {
                Button {
                    openURL(url)
                } label: {
                    Label(directionsLabel, systemImage: "arrow.triangle.turn.up.right.diamond")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if googleData == nil, googleErrorMessage != nil {
                Text("Google details unavailable right now.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

#if DEBUG
            if let message = googleErrorMessage, googleData == nil {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
#endif

            googleAttribution
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 6)
    }

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(icon: "clock") {
                hoursDetail
            }

            Divider().opacity(0.4)

            infoRow(icon: "phone") {
                phoneDetail
            }

            Divider().opacity(0.4)

            infoRow(icon: "safari") {
                websiteDetail
            }

            Divider().opacity(0.4)

            infoRow(icon: "mappin.circle") {
                addressDetail
            }
        }
    }

    private var resolvedAddress: String? {
        let formatted = googleData?
            .formattedAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let formatted, !formatted.isEmpty { return formatted }
        let stored = place.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        let display = place.displayLocation?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let display, !display.isEmpty { return display }
        return nil
    }

    private var websiteURL: URL? {
        guard let raw = googleData?.websiteURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    private var directionsLabel: String {
        if googleData?.mapsURL != nil || place.googleMapsURL != nil {
            return "Open in Google Maps"
        }
        return "Search in Google Maps"
    }

    private var directionsURL: URL? {
        if let mapsURL = googleData?.mapsURL ?? place.googleMapsURL,
           let url = URL(string: mapsURL) {
            return url
        }

        let query = [place.name, resolvedAddress]
            .compactMap { $0 }
            .joined(separator: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !query.isEmpty {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.google.com"
            components.path = "/maps/search/"
            components.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "query", value: query)
            ]
            return components.url
        }

        return nil
    }

    private var googleAttribution: some View {
        HStack(spacing: 8) {
            Image("GoogleMapsLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 16)
                .accessibilityHidden(true)

            Text("Google Maps")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hasOpeningHours(_ hours: GoogleOpeningHours) -> Bool {
        if let descriptions = hours.weekdayDescriptions, !descriptions.isEmpty {
            return true
        }
        return hours.openNow != nil
    }

    private func phoneURL(from rawValue: String) -> URL? {
        var digits = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = Set("+0123456789")
        digits.removeAll { !allowed.contains($0) }
        if digits.isEmpty { return nil }
        if digits.first == "+" {
            let prefix = String(digits.prefix(1))
            let rest = String(digits.dropFirst().filter { $0.isNumber })
            digits = prefix + rest
        } else {
            digits = String(digits.filter { $0.isNumber })
        }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel://\(digits)")
    }

    @ViewBuilder
    private func infoRow(
        icon: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Self.iconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var hoursDetail: some View {
        if let hours = googleData?.openingHours, hasOpeningHours(hours) {
            VStack(alignment: .leading, spacing: 4) {
                if let openNow = hours.openNow {
                    Text(openNow ? "Open now" : "Closed now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(openNow ? Color.green : Color.secondary)
                }

                if let descriptions = hours.weekdayDescriptions, !descriptions.isEmpty {
                    let todayIndex = currentDayIndex
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(descriptions.indices, id: \.self) { index in
                            let isToday = index == todayIndex
                            Text(formatHoursLine(descriptions[index]))
                                .font(.subheadline)
                                .fontWeight(isToday ? .bold : .regular)
                                .foregroundStyle(Color.primary)
                        }
                    }
                }
            }
        } else {
            Text("Hours unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Index of today in Google's weekday descriptions (0=Monday … 6=Sunday).
    private var currentDayIndex: Int {
        // Calendar weekday: 1=Sun, 2=Mon, …, 7=Sat
        // Google weekdayDescriptions order: Mon, Tue, Wed, Thu, Fri, Sat, Sun
        let calendarWeekday = Calendar.current.component(.weekday, from: Date())
        return calendarWeekday == 1 ? 6 : calendarWeekday - 2
    }

    /// Removes redundant `:00` from times and ensures both times show AM/PM.
    /// "Monday: 10:00 AM – 9:00 PM" → "Monday: 10 AM – 9 PM"
    /// "Saturday: 12:00 – 4:00 PM"  → "Saturday: 12 PM – 4 PM"
    /// Preserves non-zero minutes like "11:30 AM".
    private func formatHoursLine(_ line: String) -> String {
        var result = line.replacingOccurrences(of: ":00", with: "")

        // Google omits AM/PM on the opening time when both times share the
        // same period (e.g. "12 – 10 PM"). Detect this and copy the period
        // from the closing time so it reads "12 PM – 10 PM".
        for sep in ["–", "—", "-"] where result.contains(sep) {
            let parts = result.components(separatedBy: sep)
            guard parts.count == 2 else { break }
            let left = parts[0]
            let right = parts[1]
            let leftUpper = left.uppercased()
            if !leftUpper.contains("AM") && !leftUpper.contains("PM") {
                let rightUpper = right.uppercased()
                let period = rightUpper.contains("PM") ? "PM" : (rightUpper.contains("AM") ? "AM" : nil)
                if let period {
                    result = left.trimmingCharacters(in: .whitespaces)
                        + " " + period + " " + sep + right
                }
            }
            break
        }

        return result
    }

    @ViewBuilder
    private var phoneDetail: some View {
        if let phone = googleData?.phoneNumber,
           let phoneURL = phoneURL(from: phone) {
            Button {
                openURL(phoneURL)
            } label: {
                Text(phone)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
        } else {
            Text("Not listed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var websiteDetail: some View {
        if let website = websiteURL {
            Link(destination: website) {
                Text(websiteLabel(for: website))
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
            }
        } else {
            Text("Not listed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var addressDetail: some View {
        if let address = resolvedAddress {
            Text(address)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
        } else {
            Text("Address unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func websiteLabel(for url: URL) -> String {
        if let host = url.host?.lowercased(), !host.isEmpty {
            let trimmed = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return trimmed
        }
        let raw = url.absoluteString
        if raw.isEmpty { return "Website" }
        return raw
    }
}
