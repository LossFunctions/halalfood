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

final class AppleMapItemAnnotation: NSObject, MKAnnotation {
    let mapItem: MKMapItem
    let identifier: String
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { mapItem.name }
    var subtitle: String? { mapItem.halalShortAddress }

    init(mapItem: MKMapItem) {
        self.mapItem = mapItem
        if let id = mapItem.identifier?.rawValue {
            self.identifier = id
        } else {
            let coord = mapItem.halalCoordinate
            self.identifier = "\(mapItem.name ?? "place")-\(coord.latitude)-\(coord.longitude)"
        }
        self.coordinate = mapItem.halalCoordinate
        super.init()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AppleMapItemAnnotation else { return false }
        return identifier == other.identifier
    }
}

final class HalalDotAnnotationView: MKAnnotationView {
    private let dotView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 10, height: 10)))

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dotView.frame = bounds
        dotView.layer.cornerRadius = bounds.width / 2
    }

    func apply(color: UIColor) {
        dotView.backgroundColor = color
    }

    private func configure() {
        frame = dotView.bounds
        backgroundColor = .clear
        dotView.layer.cornerRadius = dotView.bounds.width / 2
        dotView.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        dotView.layer.borderWidth = 1
        dotView.isUserInteractionEnabled = false
        dotView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(dotView)
        dotView.center = CGPoint(x: bounds.midX, y: bounds.midY)

        clusteringIdentifier = nil
        collisionMode = .circle
        displayPriority = .required
        canShowCallout = false
        centerOffset = .zero
        accessibilityLabel = "Halal place"
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        let target = selected ? CGAffineTransform(scaleX: 1.6, y: 1.6) : .identity
        if animated {
            UIView.animate(withDuration: 0.18) { [weak self] in
                self?.transform = target
            }
        } else {
            transform = target
        }
    }
}

struct HalalMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var places: [Place]
    var appleMapItems: [MKMapItem] = []
    var onRegionChange: ((MKCoordinateRegion) -> Void)?
    var onPlaceSelected: ((Place) -> Void)?
    var onAppleItemSelected: ((MKMapItem) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.reuseIdentifier)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.appleReuseIdentifier)
        mapView.register(HalalDotAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.dotReuseIdentifier)
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = false
        mapView.showsBuildings = true
        mapView.isPitchEnabled = true

        // Make the map look more vibrant and closer to the Apple Maps app
        if #available(iOS 15.0, *) {
            var config = MKStandardMapConfiguration(elevationStyle: .realistic)
            // Use default emphasis (more vibrant than muted)
            config.emphasisStyle = .default
            // Keep POIs hidden; your app overlays restaurants via your own logic
            config.pointOfInterestFilter = .excludingAll
            mapView.preferredConfiguration = config
        } else {
            mapView.mapType = .standard
            if #available(iOS 13.0, *) {
                mapView.pointOfInterestFilter = .excludingAll
            }
        }
        mapView.setRegion(region, animated: false)
        context.coordinator.configureDisplayMode(using: region)
        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.mapView = uiView

        let animated = context.transaction.animation != nil
        context.coordinator.applyRegionIfNeeded(region, to: uiView, animated: animated)
        context.coordinator.update(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let reuseIdentifier = "PlaceMarker"
        static let appleReuseIdentifier = "ApplePlaceMarker"
        static let dotReuseIdentifier = "PlaceDot"

        private let dotSpanThreshold: CLLocationDegrees = 0.09

        private var parent: HalalMapView
        private var currentAnnotations: [PlaceAnnotation] = []
        private var appleAnnotations: [AppleMapItemAnnotation] = []
        private var lastRenderedRegion: MKCoordinateRegion?
        private var usesDotAnnotations = true
        var isSettingRegion = false

        fileprivate weak var mapView: MKMapView?

        init(parent: HalalMapView) {
            self.parent = parent
        }

        func configureDisplayMode(using region: MKCoordinateRegion) {
            usesDotAnnotations = shouldUseDotAppearance(for: region)
        }

        func update(parent: HalalMapView) {
            self.parent = parent
            syncAnnotations(with: parent.places)
            syncAppleAnnotations(with: parent.appleMapItems)

            if let mapView, let region = mapView.safeRegion ?? lastRenderedRegion {
                updateAnnotationDisplayMode(for: mapView, region: region)
            }
        }

        func applyRegionIfNeeded(_ region: MKCoordinateRegion, to mapView: MKMapView, animated: Bool) {
            guard !isSettingRegion else { return }

            updateAnnotationDisplayMode(for: mapView, region: region)

            let tolerance: CLLocationDegrees = 7e-4

            if let safeRegion = mapView.safeRegion,
               safeRegion.isApproximatelyEqual(to: region, centerTolerance: tolerance, spanTolerance: tolerance) {
                lastRenderedRegion = safeRegion
                return
            }

            if let last = lastRenderedRegion,
               last.isApproximatelyEqual(to: region, centerTolerance: tolerance, spanTolerance: tolerance) {
                return
            }

            let comparisonRegion = mapView.safeRegion ?? lastRenderedRegion
            lastRenderedRegion = region

            let shouldAnimate = animated && !(comparisonRegion?.isApproximatelyEqual(to: region, centerTolerance: 0.02, spanTolerance: 0.02) ?? false)
            mapView.setRegion(region, animated: shouldAnimate)
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

            if !toRemove.isEmpty {
                mapView.removeAnnotations(toRemove)
            }
            if !toAdd.isEmpty {
                mapView.addAnnotations(toAdd)
            }

            currentAnnotations.removeAll { annotation in
                toRemove.contains(where: { $0.place.id == annotation.place.id })
            }
            currentAnnotations.append(contentsOf: toAdd)
        }

        private func syncAppleAnnotations(with items: [MKMapItem]) {
            guard let mapView else { return }

            let incoming = items.compactMap { item -> AppleMapItemAnnotation? in
                let annotation = AppleMapItemAnnotation(mapItem: item)
                let coord = annotation.coordinate
                if coord.latitude == 0 && coord.longitude == 0 {
                    return nil
                }
                return annotation
            }

            let existingSet = Set(appleAnnotations.map { $0.identifier })
            let incomingSet = Set(incoming.map { $0.identifier })

            let toRemove = appleAnnotations.filter { !incomingSet.contains($0.identifier) }
            let toAdd = incoming.filter { !existingSet.contains($0.identifier) }

            if !toRemove.isEmpty {
                mapView.removeAnnotations(toRemove)
            }
            if !toAdd.isEmpty {
                mapView.addAnnotations(toAdd)
            }

            appleAnnotations.removeAll { annotation in
                toRemove.contains(where: { $0.identifier == annotation.identifier })
            }
            appleAnnotations.append(contentsOf: toAdd)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard let parentMap = mapView.safeRegion else { return }

            updateAnnotationDisplayMode(for: mapView, region: parentMap)

            let previousRegion = lastRenderedRegion
            lastRenderedRegion = parentMap

            let shouldNotify = !(previousRegion?.isApproximatelyEqual(to: parentMap, centerTolerance: 5e-4, spanTolerance: 5e-4) ?? false)

            isSettingRegion = true
            let callback = parent.onRegionChange
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.region = parentMap
                self.isSettingRegion = false
                if shouldNotify {
                    callback?(parentMap)
                }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let placeAnnotation = annotation as? PlaceAnnotation {
                if usesDotAnnotations {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.dotReuseIdentifier, for: annotation) as! HalalDotAnnotationView
                    view.apply(color: .systemOrange)
                    return view
                } else {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.reuseIdentifier, for: annotation) as! MKMarkerAnnotationView
                    view.clusteringIdentifier = nil
                    view.collisionMode = .circle
                    view.displayPriority = .required
                    view.canShowCallout = true
                    view.markerTintColor = tintColor(for: placeAnnotation.place.category)
                    view.glyphImage = glyph(for: placeAnnotation.place.category)
                    view.titleVisibility = .visible
                    view.subtitleVisibility = .adaptive
                    return view
                }
            }

            if annotation is AppleMapItemAnnotation {
                if usesDotAnnotations {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.dotReuseIdentifier, for: annotation) as! HalalDotAnnotationView
                    view.apply(color: .systemOrange)
                    return view
                } else {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.appleReuseIdentifier, for: annotation) as! MKMarkerAnnotationView
                    view.clusteringIdentifier = nil
                    view.collisionMode = .circle
                    view.displayPriority = .required
                    view.canShowCallout = false
                    view.markerTintColor = .systemOrange
                    view.glyphImage = glyph(for: .restaurant)
                    view.subtitleVisibility = .hidden
                    return view
                }
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if usesDotAnnotations, view.annotation is PlaceAnnotation || view.annotation is AppleMapItemAnnotation {
                mapView.deselectAnnotation(view.annotation, animated: false)
                return
            }

            if let annotation = view.annotation as? PlaceAnnotation {
                parent.onPlaceSelected?(annotation.place)
            } else if let appleAnnotation = view.annotation as? AppleMapItemAnnotation {
                parent.onAppleItemSelected?(appleAnnotation.mapItem)
            }
        }

        private func updateAnnotationDisplayMode(for mapView: MKMapView, region: MKCoordinateRegion) {
            let shouldUseDots = shouldUseDotAppearance(for: region)
            guard shouldUseDots != usesDotAnnotations else { return }

            usesDotAnnotations = shouldUseDots
            let baseAnnotations: [MKAnnotation] = currentAnnotations.map { $0 } + appleAnnotations.map { $0 }
            guard !baseAnnotations.isEmpty else { return }

            mapView.removeAnnotations(baseAnnotations)
            mapView.addAnnotations(baseAnnotations)
        }

        private func shouldUseDotAppearance(for region: MKCoordinateRegion) -> Bool {
            max(region.span.latitudeDelta, region.span.longitudeDelta) >= dotSpanThreshold
        }

        private func tintColor(for category: PlaceCategory) -> UIColor {
            .systemOrange
        }

        private func glyph(for category: PlaceCategory) -> UIImage? {
            let configuration = UIImage.SymbolConfiguration(scale: .medium)
            return UIImage(systemName: "fork.knife", withConfiguration: configuration)
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

private extension MKCoordinateRegion {
    func isApproximatelyEqual(to other: MKCoordinateRegion,
                              centerTolerance: CLLocationDegrees = 5e-4,
                              spanTolerance: CLLocationDegrees = 5e-4) -> Bool {
        let centerClose = abs(center.latitude - other.center.latitude) <= centerTolerance &&
            abs(center.longitude - other.center.longitude) <= centerTolerance
        if !centerClose { return false }

        let spanClose = abs(span.latitudeDelta - other.span.latitudeDelta) <= spanTolerance &&
            abs(span.longitudeDelta - other.span.longitudeDelta) <= spanTolerance
        return spanClose
    }
}
