import MapKit

nonisolated extension MKCoordinateRegion {
    var bbox: BBox {
        let halfLat = span.latitudeDelta / 2.0
        let halfLon = span.longitudeDelta / 2.0
        let west = center.longitude - halfLon
        let east = center.longitude + halfLon
        let south = center.latitude - halfLat
        let north = center.latitude + halfLat
        return BBox(west: west, south: south, east: east, north: north)
    }

    func isApproximatelyEqual(to other: MKCoordinateRegion) -> Bool {
        guard span.latitudeDelta > 0,
              span.longitudeDelta > 0,
              other.span.latitudeDelta > 0,
              other.span.longitudeDelta > 0 else {
            return false
        }

        let latDiff = abs(center.latitude - other.center.latitude)
        let lonDiff = abs(center.longitude - other.center.longitude)
        let latSpanDiff = abs(span.latitudeDelta - other.span.latitudeDelta)
        let lonSpanDiff = abs(span.longitudeDelta - other.span.longitudeDelta)

        let maxLatSpan = max(span.latitudeDelta, other.span.latitudeDelta)
        let maxLonSpan = max(span.longitudeDelta, other.span.longitudeDelta)

        let centerLatThreshold = max(0.005, maxLatSpan * 0.25)
        let centerLonThreshold = max(0.005, maxLonSpan * 0.25)
        let spanLatThreshold = max(0.0075, maxLatSpan * 0.35)
        let spanLonThreshold = max(0.0075, maxLonSpan * 0.35)

        return latDiff <= centerLatThreshold &&
            lonDiff <= centerLonThreshold &&
            latSpanDiff <= spanLatThreshold &&
            lonSpanDiff <= spanLonThreshold
    }
}
