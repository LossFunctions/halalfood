import Foundation
import MapKit
import SwiftUI

final class PlaceAnnotation: NSObject, MKAnnotation {
    var place: Place
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { place.name }
    var subtitle: String? { place.address }

    init(place: Place) {
        self.place = place
        self.coordinate = place.coordinate
        super.init()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PlaceAnnotation else { return false }
        return place.id == other.place.id
    }
}

struct HalalMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var places: [Place]
    var onRegionChange: ((MKCoordinateRegion) -> Void)?
    var onPlaceSelected: ((Place) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.reuseIdentifier)
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.mapType = .mutedStandard
        mapView.isRotateEnabled = false
        mapView.setRegion(region, animated: false)
        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.mapView = uiView

        if !context.coordinator.isSettingRegion {
            uiView.setRegion(region, animated: true)
        }

        context.coordinator.update(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let reuseIdentifier = "PlaceMarker"

        private var parent: HalalMapView
        private var currentAnnotations: [PlaceAnnotation] = []
        var isSettingRegion = false

        fileprivate weak var mapView: MKMapView?

        init(parent: HalalMapView) {
            self.parent = parent
        }

        func update(parent: HalalMapView) {
            self.parent = parent
            syncAnnotations(with: parent.places)
        }

        private func syncAnnotations(with places: [Place]) {
            guard let mapView else { return }

            let incomingAnnotations = places.map { PlaceAnnotation(place: $0) }

            let existingSet = Set(currentAnnotations.map { $0.place.id })
            let incomingSet = Set(incomingAnnotations.map { $0.place.id })

            let toRemove = currentAnnotations.filter { !incomingSet.contains($0.place.id) }
            let toAdd = incomingAnnotations.filter { !existingSet.contains($0.place.id) }

            currentAnnotations.forEach { annotation in
                guard let updated = incomingAnnotations.first(where: { $0.place.id == annotation.place.id }) else { return }
                if annotation.coordinate.latitude != updated.coordinate.latitude || annotation.coordinate.longitude != updated.coordinate.longitude {
                    annotation.coordinate = updated.coordinate
                }
                annotation.place = updated.place
            }

            mapView.removeAnnotations(toRemove)
            mapView.addAnnotations(toAdd)

            currentAnnotations.removeAll { annotation in
                toRemove.contains(where: { $0.place.id == annotation.place.id })
            }
            currentAnnotations.append(contentsOf: toAdd)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard let parentMap = mapView.safeRegion else { return }
            isSettingRegion = true
            parent.region = parentMap
            isSettingRegion = false
            parent.onRegionChange?(parentMap)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let placeAnnotation = annotation as? PlaceAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.reuseIdentifier, for: annotation) as! MKMarkerAnnotationView
            view.clusteringIdentifier = "poi"
            view.canShowCallout = true
            view.markerTintColor = tintColor(for: placeAnnotation.place.category)
            view.glyphImage = glyph(for: placeAnnotation.place.category)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? PlaceAnnotation else { return }
            parent.onPlaceSelected?(annotation.place)
        }

        private func tintColor(for category: POICategory) -> UIColor {
            switch category {
            case .all: return .systemYellow
            case .restaurant: return .systemOrange
            case .mosque: return .systemGreen
            }
        }

        private func glyph(for category: POICategory) -> UIImage? {
            let configuration = UIImage.SymbolConfiguration(scale: .medium)
            switch category {
            case .all:
                return UIImage(systemName: "mappin", withConfiguration: configuration)
            case .restaurant:
                return UIImage(systemName: "fork.knife", withConfiguration: configuration)
            case .mosque:
                return UIImage(systemName: "moon.stars", withConfiguration: configuration)
            }
        }
    }
}

private extension MKMapView {
    var safeRegion: MKCoordinateRegion? {
        let currentRegion = region
        let span = currentRegion.span
        guard span.latitudeDelta > 0, span.longitudeDelta > 0 else { return nil }
        return currentRegion
    }
}
