import Foundation
import MapKit

extension MKMapItem {
    /// Coordinate that works across iOS versions without triggering deprecated APIs.
    var halalCoordinate: CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return location.coordinate
        }
        return legacyPlacemarkCoordinateFallback()
    }

    /// Short address string that falls back gracefully on older iOS versions.
    var halalShortAddress: String? {
        if #available(iOS 26.0, *) {
            if let short = address?.shortAddress, !short.isEmpty {
                return short
            }
            return addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
        }
        return legacyPlacemarkTitleFallback()
    }

    /// Identifier that remains stable even when MapKit does not expose an official identifier.
    var halalPersistentIdentifier: String {
        if let raw = identifier?.rawValue, !raw.isEmpty {
            return raw
        }

        let coordinate = halalCoordinate
        let folder = (name ?? "place").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let sanitizedName = folder.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
        let latComponent = String(format: "%.5f", coordinate.latitude)
        let lonComponent = String(format: "%.5f", coordinate.longitude)
        return [sanitizedName.isEmpty ? "place" : sanitizedName, latComponent, lonComponent]
            .joined(separator: "-")
    }

    private func legacyPlacemarkCoordinateFallback() -> CLLocationCoordinate2D {
        guard let placemark = value(forKey: "placemark") as? NSObject else {
            return .init()
        }

        if let coordinate = placemark.value(forKey: "coordinate") as? CLLocationCoordinate2D {
            return coordinate
        }

        if let coordinateValue = placemark.value(forKey: "coordinate") as? NSValue {
            return coordinateValue.mkCoordinateValue
        }

        if let location = placemark.value(forKey: "location") as? CLLocation {
            return location.coordinate
        }

        return .init()
    }

    private func legacyPlacemarkTitleFallback() -> String? {
        guard let placemark = value(forKey: "placemark") as? NSObject else {
            return nil
        }

        if let title = placemark.value(forKey: "title") as? String, !title.isEmpty {
            return title
        }

        if let name = placemark.value(forKey: "name") as? String, !name.isEmpty {
            return name
        }

        let components = [
            placemark.value(forKey: "subThoroughfare") as? String,
            placemark.value(forKey: "thoroughfare") as? String,
            placemark.value(forKey: "locality") as? String
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
}
