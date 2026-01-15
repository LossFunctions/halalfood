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

final class PlacePinAnnotation: NSObject, MKAnnotation {
    var pin: PlacePin
    dynamic var coordinate: CLLocationCoordinate2D

    init(pin: PlacePin) {
        self.pin = pin
        self.coordinate = pin.coordinate
        super.init()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PlacePinAnnotation else { return false }
        return pin.id == other.pin.id
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
        self.identifier = mapItem.halalPersistentIdentifier
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
    static let dotSpanThreshold: CLLocationDegrees = 0.1
    @Binding var region: MKCoordinateRegion
    @Binding var selectedPlace: Place?
    var pins: [PlacePin]
    var places: [Place]
    var appleMapItems: [MKMapItem] = []
    var onRegionChange: ((MKCoordinateRegion) -> Void)?
    var onPinSelected: ((PlacePin) -> Void)?
    var onPlaceSelected: ((Place) -> Void)?
    var onAppleItemSelected: ((MKMapItem) -> Void)?
    var onMapTap: (() -> Void)?

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
        mapView.setUserTrackingMode(.follow, animated: false)

        // Make the map look more vibrant and closer to the Apple Maps app
        if #available(iOS 15.0, *) {
            let config = MKStandardMapConfiguration(elevationStyle: .realistic)
            // Use default emphasis (more vibrant than muted)
            config.emphasisStyle = .default
            // Keep POIs hidden; your app overlays restaurants via your own logic
            config.pointOfInterestFilter = .excludingAll
            mapView.preferredConfiguration = config
        } else {
            mapView.mapType = .standard
            mapView.pointOfInterestFilter = .excludingAll
        }
        mapView.setRegion(region, animated: false)
        context.coordinator.configureDisplayMode(using: region, pinCount: pins.count)
        context.coordinator.mapView = mapView
        context.coordinator.addTapRecognizer(to: mapView)
        context.coordinator.syncSelection(in: mapView)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.mapView = uiView

        let animated = context.transaction.animation != nil
        context.coordinator.applyRegionIfNeeded(region, to: uiView, animated: animated)
        context.coordinator.update(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        static let reuseIdentifier = "PlaceMarker"
        static let appleReuseIdentifier = "ApplePlaceMarker"
        static let dotReuseIdentifier = "PlaceDot"

        private enum AnnotationMode {
            case pins
            case places
        }

        private let dotSpanThreshold = HalalMapView.dotSpanThreshold
        private let regionChangeDebounceNanoseconds: UInt64 = 200_000_000
        private let duplicateOffsetEnableSpan: CLLocationDegrees = 0.008
        private let duplicateOffsetDisableSpan: CLLocationDegrees = 0.01
        private let duplicateOffsetRadius: CGFloat = 22

        private var parent: HalalMapView
        private var placeAnnotationsByID: [UUID: PlaceAnnotation] = [:]
        private var pinAnnotationsByID: [UUID: PlacePinAnnotation] = [:]
        private var currentPlaceAnnotations: [PlaceAnnotation] = []
        private var currentPinAnnotations: [PlacePinAnnotation] = []
        private var appleAnnotations: [AppleMapItemAnnotation] = []
        private var lastRenderedRegion: MKCoordinateRegion?
        private var usesDotAnnotations = true
        private var annotationMode: AnnotationMode = .pins
        private var regionChangeTask: Task<Void, Never>?
        private var duplicateOffsetsEnabled = false
        private var duplicatePlaceGroups: [[UUID]] = []
        var isSettingRegion = false

        fileprivate weak var mapView: MKMapView?

        init(parent: HalalMapView) {
            self.parent = parent
        }

        func addTapRecognizer(to mapView: MKMapView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            mapView.addGestureRecognizer(tap)
        }

        func configureDisplayMode(using region: MKCoordinateRegion, pinCount: Int) {
            usesDotAnnotations = shouldUseDotAppearance(for: region, placeCount: pinCount)
            annotationMode = usesDotAnnotations ? .pins : .places
        }

        func update(parent: HalalMapView) {
            self.parent = parent
            syncPinAnnotations(with: parent.pins)
            syncPlaceAnnotations(with: parent.places)
            syncAppleAnnotations(with: parent.appleMapItems)

            if let mapView, let region = mapView.safeRegion ?? lastRenderedRegion {
                updateAnnotationDisplayMode(for: mapView, region: region, pinCount: parent.pins.count)
                syncSelection(in: mapView)
                applyDuplicateOffsetsIfNeeded(in: mapView, region: region)
            }
        }

        func applyRegionIfNeeded(_ region: MKCoordinateRegion, to mapView: MKMapView, animated: Bool) {
            guard !isSettingRegion else { return }

            updateAnnotationDisplayMode(for: mapView, region: region, pinCount: parent.pins.count)

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

        private func syncPlaceAnnotations(with places: [Place]) {
            let shouldRender = annotationMode == .places
            let mapView = shouldRender ? self.mapView : nil
#if DEBUG
            let span = PerformanceMetrics.begin(
                event: .mapAnnotationSync,
                metadata: "incoming=\(places.count)"
            )
            var addedCount = 0
            var removedCount = 0
            defer {
                let metadata = "rendered=\(placeAnnotationsByID.count) added=\(addedCount) removed=\(removedCount)"
                PerformanceMetrics.end(span, metadata: metadata)
            }
#endif

            let incomingIDs = Set(places.map { $0.id })

            var annotationsToRemove: [PlaceAnnotation] = []
            for id in placeAnnotationsByID.keys where !incomingIDs.contains(id) {
                if let annotation = placeAnnotationsByID[id] {
                    annotationsToRemove.append(annotation)
                }
            }
            if !annotationsToRemove.isEmpty {
                if let mapView {
                    mapView.removeAnnotations(annotationsToRemove)
                }
                for annotation in annotationsToRemove {
                    placeAnnotationsByID.removeValue(forKey: annotation.place.id)
                }
            }
#if DEBUG
            removedCount = annotationsToRemove.count
#endif

            var annotationsToAdd: [PlaceAnnotation] = []
            for place in places {
                if let annotation = placeAnnotationsByID[place.id] {
                    if annotation.coordinate.latitude != place.coordinate.latitude ||
                        annotation.coordinate.longitude != place.coordinate.longitude {
                        annotation.coordinate = place.coordinate
                    }
                    annotation.place = place
                } else {
                    let annotation = PlaceAnnotation(place: place)
                    placeAnnotationsByID[place.id] = annotation
                    annotationsToAdd.append(annotation)
                }
            }

            if let mapView, !annotationsToAdd.isEmpty {
                mapView.addAnnotations(annotationsToAdd)
            }
#if DEBUG
            addedCount = annotationsToAdd.count
#endif

            currentPlaceAnnotations = Array(placeAnnotationsByID.values)
            rebuildDuplicatePlaceGroups()
        }

        private func syncPinAnnotations(with pins: [PlacePin]) {
            let shouldRender = annotationMode == .pins
            let mapView = shouldRender ? self.mapView : nil

            let incomingIDs = Set(pins.map { $0.id })

            var annotationsToRemove: [PlacePinAnnotation] = []
            for id in pinAnnotationsByID.keys where !incomingIDs.contains(id) {
                if let annotation = pinAnnotationsByID[id] {
                    annotationsToRemove.append(annotation)
                }
            }
            if !annotationsToRemove.isEmpty {
                if let mapView {
                    mapView.removeAnnotations(annotationsToRemove)
                }
                for annotation in annotationsToRemove {
                    pinAnnotationsByID.removeValue(forKey: annotation.pin.id)
                }
            }

            var annotationsToAdd: [PlacePinAnnotation] = []
            for pin in pins {
                if let annotation = pinAnnotationsByID[pin.id] {
                    if annotation.coordinate.latitude != pin.coordinate.latitude ||
                        annotation.coordinate.longitude != pin.coordinate.longitude {
                        annotation.coordinate = pin.coordinate
                    }
                    annotation.pin = pin
                } else {
                    let annotation = PlacePinAnnotation(pin: pin)
                    pinAnnotationsByID[pin.id] = annotation
                    annotationsToAdd.append(annotation)
                }
            }

            if let mapView, !annotationsToAdd.isEmpty {
                mapView.addAnnotations(annotationsToAdd)
            }

            currentPinAnnotations = Array(pinAnnotationsByID.values)
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
#if DEBUG
            let centerLat = String(format: "%.4f", parentMap.center.latitude)
            let centerLon = String(format: "%.4f", parentMap.center.longitude)
            let spanLat = String(format: "%.4f", parentMap.span.latitudeDelta)
            let spanLon = String(format: "%.4f", parentMap.span.longitudeDelta)
            let metadata = "center=(\(centerLat),\(centerLon)) span=(\(spanLat)x\(spanLon)) animated=\(animated)"
            PerformanceMetrics.point(event: .mapRegionChange, metadata: metadata)
#endif
            updateAnnotationDisplayMode(for: mapView, region: parentMap, pinCount: parent.pins.count)
            applyDuplicateOffsetsIfNeeded(in: mapView, region: parentMap)

            let previousRegion = lastRenderedRegion
            lastRenderedRegion = parentMap

            let shouldNotify = !(previousRegion?.isApproximatelyEqual(to: parentMap, centerTolerance: 5e-4, spanTolerance: 5e-4) ?? false)

            let capturedRegion = parentMap
            isSettingRegion = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.parent.region = capturedRegion
                self.isSettingRegion = false
            }

            if shouldNotify {
                scheduleRegionChangeCallback(for: parentMap, callback: parent.onRegionChange)
            } else {
                regionChangeTask?.cancel()
                regionChangeTask = nil
            }
        }

        private func scheduleRegionChangeCallback(for region: MKCoordinateRegion, callback: ((MKCoordinateRegion) -> Void)?) {
            guard let callback else { return }
            regionChangeTask?.cancel()
            regionChangeTask = Task { [weak self] in
                do {
                    guard let self else { return }
                    try await Task.sleep(nanoseconds: self.regionChangeDebounceNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
#if DEBUG
                    PerformanceMetrics.point(event: .mapRegionChange, metadata: "Debounced callback fired")
#endif
                    callback(region)
                    self.regionChangeTask = nil
                }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let placeAnnotation = annotation as? PlaceAnnotation {
                if usesDotAnnotations {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.dotReuseIdentifier, for: annotation) as! HalalDotAnnotationView
                    view.clusteringIdentifier = nil
                    view.apply(color: tintColor(for: placeAnnotation.place.halalStatus))
                    return view
                } else {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.reuseIdentifier, for: annotation) as! MKMarkerAnnotationView
                    view.clusteringIdentifier = nil
                    view.collisionMode = .circle
                    view.displayPriority = .required
                    view.canShowCallout = true
                    view.markerTintColor = tintColor(for: placeAnnotation.place.halalStatus)
                    view.glyphImage = glyph(for: placeAnnotation.place.category)
                    view.titleVisibility = .visible
                    view.subtitleVisibility = .adaptive
                    return view
                }
            }

            if let pinAnnotation = annotation as? PlacePinAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.dotReuseIdentifier, for: annotation) as! HalalDotAnnotationView
                view.clusteringIdentifier = nil
                view.apply(color: tintColor(for: pinAnnotation.pin.halalStatus))
                return view
            }

            if annotation is AppleMapItemAnnotation {
                if usesDotAnnotations {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.dotReuseIdentifier, for: annotation) as! HalalDotAnnotationView
                    view.clusteringIdentifier = nil
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
            if let annotation = view.annotation as? PlacePinAnnotation {
                parent.onPinSelected?(annotation.pin)
                mapView.deselectAnnotation(view.annotation, animated: false)
                return
            }

            if usesDotAnnotations, view.annotation is PlaceAnnotation || view.annotation is AppleMapItemAnnotation {
                mapView.deselectAnnotation(view.annotation, animated: false)
                return
            }

            if let annotation = view.annotation as? PlaceAnnotation {
                parent.selectedPlace = annotation.place
                parent.onPlaceSelected?(annotation.place)
            } else if let appleAnnotation = view.annotation as? AppleMapItemAnnotation {
                parent.onAppleItemSelected?(appleAnnotation.mapItem)
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard let annotation = view.annotation as? PlaceAnnotation else { return }
            if parent.selectedPlace?.id == annotation.place.id {
                parent.selectedPlace = nil
            }
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            guard annotationMode == .places else { return }
            guard views.contains(where: { $0.annotation is PlaceAnnotation }) else { return }
            guard let region = mapView.safeRegion ?? lastRenderedRegion else { return }
            applyDuplicateOffsetsIfNeeded(in: mapView, region: region)
        }

        @objc private func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            guard let mapView else { return }
            let location = recognizer.location(in: mapView)
            if mapView.hitTest(location, with: nil) is MKAnnotationView {
                return
            }
            parent.onMapTap?()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if touch.view is MKAnnotationView { return false }
            if let superview = touch.view?.superview, superview is MKAnnotationView { return false }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        private func updateAnnotationDisplayMode(for mapView: MKMapView, region: MKCoordinateRegion, pinCount: Int) {
            let shouldUsePins = shouldUseDotAppearance(for: region, placeCount: pinCount)
            let nextMode: AnnotationMode = shouldUsePins ? .pins : .places
            guard nextMode != annotationMode else { return }

            annotationMode = nextMode
            usesDotAnnotations = shouldUsePins

            func toAnnotations<T: MKAnnotation>(_ annotations: [T]) -> [MKAnnotation] {
                annotations.map { $0 as MKAnnotation }
            }

            let previousAnnotations: [MKAnnotation]
            let nextAnnotations: [MKAnnotation]
            if nextMode == .pins {
                previousAnnotations = toAnnotations(currentPlaceAnnotations)
                nextAnnotations = toAnnotations(currentPinAnnotations)
            } else {
                previousAnnotations = toAnnotations(currentPinAnnotations)
                nextAnnotations = toAnnotations(currentPlaceAnnotations)
            }

            let appleAnnotationList: [MKAnnotation] = appleAnnotations.map { $0 as MKAnnotation }
            let toRemove = previousAnnotations + appleAnnotationList
            let toAdd = nextAnnotations + appleAnnotationList

            if !toRemove.isEmpty {
                mapView.removeAnnotations(toRemove)
            }
            if !toAdd.isEmpty {
                mapView.addAnnotations(toAdd)
            }
        }

        private func shouldUseDotAppearance(for region: MKCoordinateRegion, placeCount _: Int) -> Bool {
            max(region.span.latitudeDelta, region.span.longitudeDelta) >= dotSpanThreshold
        }

        fileprivate func syncSelection(in mapView: MKMapView) {
            guard annotationMode == .places else { return }

            let selectedAnnotations = mapView.selectedAnnotations.compactMap { $0 as? PlaceAnnotation }

            if let target = parent.selectedPlace {
                let alreadySelected = selectedAnnotations.contains { $0.place.id == target.id }
                if !alreadySelected,
                   let annotation = currentPlaceAnnotations.first(where: { $0.place.id == target.id }) {
                    mapView.selectAnnotation(annotation, animated: true)
                }
            } else if !selectedAnnotations.isEmpty {
                selectedAnnotations.forEach { mapView.deselectAnnotation($0, animated: true) }
            }
        }

        deinit {
            regionChangeTask?.cancel()
        }

        private func tintColor(for halalStatus: Place.HalalStatus) -> UIColor {
            if halalStatus == .only {
                return .systemGreen
            }
            return .systemOrange
        }

        private func glyph(for category: PlaceCategory) -> UIImage? {
            let configuration = UIImage.SymbolConfiguration(scale: .medium)
            return UIImage(systemName: "fork.knife", withConfiguration: configuration)
        }

        private struct CoordinateKey: Hashable {
            let latitude: Double
            let longitude: Double

            init(_ coordinate: CLLocationCoordinate2D) {
                let scale = 10_000.0
                latitude = (coordinate.latitude * scale).rounded() / scale
                longitude = (coordinate.longitude * scale).rounded() / scale
            }
        }

        private func rebuildDuplicatePlaceGroups() {
            var buckets: [CoordinateKey: [UUID]] = [:]
            for annotation in currentPlaceAnnotations {
                let key = CoordinateKey(annotation.coordinate)
                buckets[key, default: []].append(annotation.place.id)
            }
            duplicatePlaceGroups = buckets.values
                .filter { $0.count > 1 }
                .map { $0.sorted { $0.uuidString < $1.uuidString } }
        }

        private func applyDuplicateOffsetsIfNeeded(in mapView: MKMapView, region: MKCoordinateRegion) {
            guard annotationMode == .places, !usesDotAnnotations else {
                resetDuplicateOffsets(in: mapView)
                return
            }

            let span = max(region.span.latitudeDelta, region.span.longitudeDelta)
            let scale = duplicateOffsetScale(for: span)
            guard scale > 0 else {
                resetDuplicateOffsets(in: mapView)
                return
            }

            guard !duplicatePlaceGroups.isEmpty else {
                resetDuplicateOffsets(in: mapView)
                return
            }

            for group in duplicatePlaceGroups {
                let views: [MKAnnotationView] = group.compactMap { id in
                    guard let annotation = placeAnnotationsByID[id] else { return nil }
                    return mapView.view(for: annotation)
                }
                guard views.count == group.count else { continue }
                let maxViewWidth = views.map(\.frame.width).max() ?? 0
                let baseRadius = min(36, max(CGFloat(16), max(maxViewWidth * 0.35, duplicateOffsetRadius)))
                let radius = baseRadius * scale
                let offsets = radialOffsets(count: group.count, radius: radius)
                for (id, offset) in zip(group, offsets) {
                    guard let annotation = placeAnnotationsByID[id],
                          let view = mapView.view(for: annotation) else { continue }
                    view.centerOffset = offset
                }
            }
        }

        private func updateDuplicateOffsetsState(for span: CLLocationDegrees) {
            if duplicateOffsetsEnabled {
                if span > duplicateOffsetDisableSpan {
                    duplicateOffsetsEnabled = false
                }
            } else if span < duplicateOffsetEnableSpan {
                duplicateOffsetsEnabled = true
            }
        }

        private func duplicateOffsetScale(for span: CLLocationDegrees) -> CGFloat {
            updateDuplicateOffsetsState(for: span)
            guard duplicateOffsetsEnabled else { return 0 }
            let clamped = min(max(span, duplicateOffsetEnableSpan), duplicateOffsetDisableSpan)
            let t = (duplicateOffsetDisableSpan - clamped) / (duplicateOffsetDisableSpan - duplicateOffsetEnableSpan)
            let eased = t * t
            return CGFloat(max(0, min(1, eased)))
        }

        private func resetDuplicateOffsets(in mapView: MKMapView) {
            for annotation in currentPlaceAnnotations {
                guard let view = mapView.view(for: annotation) else { continue }
                if view.centerOffset != .zero {
                    view.centerOffset = .zero
                }
            }
        }

        private func radialOffsets(count: Int, radius: CGFloat) -> [CGPoint] {
            guard count > 0 else { return [] }
            if count == 2 {
                let angle = CGFloat.pi / 4
                return [
                    CGPoint(x: cos(angle) * radius, y: sin(angle) * radius),
                    CGPoint(x: cos(angle + CGFloat.pi) * radius, y: sin(angle + CGFloat.pi) * radius)
                ]
            }
            let total = CGFloat(count)
            return (0..<count).map { index in
                let angle = (2 * CGFloat.pi * CGFloat(index)) / total
                return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
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
