import MapKit

extension MKCoordinateRegion {
    var bbox: BBox {
        let halfLat = span.latitudeDelta / 2.0
        let halfLon = span.longitudeDelta / 2.0
        let west = center.longitude - halfLon
        let east = center.longitude + halfLon
        let south = center.latitude - halfLat
        let north = center.latitude + halfLat
        return BBox(west: west, south: south, east: east, north: north)
    }
}
