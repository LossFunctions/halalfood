import Foundation
import GoogleMaps
import MapKit
import SwiftUI
import UIKit

final class MarkerPayload: NSObject {
    enum Kind {
        case place
        case pin
        case apple
    }

    let kind: Kind
    let place: Place?
    let pin: PlacePin?
    let mapItem: MKMapItem?

    init(place: Place) {
        kind = .place
        self.place = place
        pin = nil
        mapItem = nil
    }

    init(pin: PlacePin) {
        kind = .pin
        self.pin = pin
        place = nil
        mapItem = nil
    }

    init(mapItem: MKMapItem) {
        kind = .apple
        self.mapItem = mapItem
        place = nil
        pin = nil
    }
}

struct HalalMapView: UIViewRepresentable {
    static let dotSpanThreshold: CLLocationDegrees = 0.1
    private static let mapStyleJSON = """
    [
      { "featureType": "poi", "stylers": [ { "visibility": "off" } ] },
      { "featureType": "transit", "stylers": [ { "visibility": "off" } ] }
    ]
    """
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

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition(
            target: region.center,
            zoom: context.coordinator.zoomLevel(for: region)
        )
        let mapView = GMSMapView()
        mapView.camera = camera
        mapView.delegate = context.coordinator
        mapView.mapStyle = try? GMSMapStyle(jsonString: Self.mapStyleJSON)
        mapView.isMyLocationEnabled = true
        mapView.isBuildingsEnabled = true
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = true
        mapView.settings.myLocationButton = false
        mapView.settings.compassButton = false
        mapView.mapType = .normal
        context.coordinator.mapView = mapView
        context.coordinator.configureDisplayMode(using: region, pinCount: pins.count)
        context.coordinator.syncSelection(in: mapView)
        return mapView
    }

    func updateUIView(_ uiView: GMSMapView, context: Context) {
        context.coordinator.mapView = uiView
        let animated = context.transaction.animation != nil
        context.coordinator.applyRegionIfNeeded(region, to: uiView, animated: animated)
        context.coordinator.update(parent: self)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        private enum AnnotationMode {
            case pins
            case places
        }

        private let dotSpanThreshold = HalalMapView.dotSpanThreshold
        private let regionChangeDebounceNanoseconds: UInt64 = 200_000_000
        private let dotSize = CGSize(width: 10, height: 10)
        private let pinSize = CGSize(width: 41, height: 51)
        private let markerDiameter: CGFloat = 41
        private let labelPaddingX: CGFloat = 0
        private let labelSpacing: CGFloat = 0
        private let maxLabelWidth: CGFloat = 180
        private let greenPinAssetName = "GreenPin"
        private let orangePinAssetName = "OrangePin"

        private var parent: HalalMapView
        private var placeMarkersByID: [UUID: GMSMarker] = [:]
        private var pinMarkersByID: [UUID: GMSMarker] = [:]
        private var appleMarkersByID: [String: GMSMarker] = [:]
        private var lastRenderedRegion: MKCoordinateRegion?
        private var lastInterfaceStyle: UIUserInterfaceStyle?
        private var usesDotMarkers = true
        private var annotationMode: AnnotationMode = .pins
        private var regionChangeTask: Task<Void, Never>?
        private var dotIconCache: [String: UIImage] = [:]
        private var labelIconCache: [String: MarkerIcon] = [:]
        private var pinIconCache: [String: UIImage] = [:]
        var isSettingRegion = false

        fileprivate weak var mapView: GMSMapView?

        init(parent: HalalMapView) {
            self.parent = parent
        }

        func configureDisplayMode(using region: MKCoordinateRegion, pinCount: Int) {
            usesDotMarkers = shouldUseDotAppearance(for: region, placeCount: pinCount)
            annotationMode = usesDotMarkers ? .pins : .places
        }

        func update(parent: HalalMapView) {
            self.parent = parent
            syncPinMarkers(with: parent.pins)
            syncPlaceMarkers(with: parent.places)
            syncAppleMarkers(with: parent.appleMapItems)
            if let mapView {
                refreshMarkerStylesIfNeeded(for: mapView)
            }

            if let mapView, let region = currentRegion(for: mapView) ?? lastRenderedRegion {
                updateMarkerDisplayMode(for: mapView, region: region, pinCount: parent.pins.count)
                syncSelection(in: mapView)
            }
        }

        func applyRegionIfNeeded(_ region: MKCoordinateRegion, to mapView: GMSMapView, animated: Bool) {
            guard !isSettingRegion else { return }

            updateMarkerDisplayMode(for: mapView, region: region, pinCount: parent.pins.count)

            let tolerance: CLLocationDegrees = 7e-4
            if let last = lastRenderedRegion,
               last.isApproximatelyEqual(to: region, centerTolerance: tolerance, spanTolerance: tolerance) {
                return
            }

            let update = cameraUpdate(for: region, in: mapView)
            lastRenderedRegion = region

            if animated {
                mapView.animate(with: update)
            } else {
                mapView.moveCamera(update)
            }
        }

        func syncSelection(in mapView: GMSMapView) {
            guard annotationMode == .places else {
                if mapView.selectedMarker != nil {
                    mapView.selectedMarker = nil
                }
                return
            }

            if let target = parent.selectedPlace,
               let marker = placeMarkersByID[target.id] {
                if mapView.selectedMarker !== marker {
                    mapView.selectedMarker = marker
                }
            } else if mapView.selectedMarker != nil {
                mapView.selectedMarker = nil
            }
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            guard let region = currentRegion(for: mapView) else { return }

            updateMarkerDisplayMode(for: mapView, region: region, pinCount: parent.pins.count)

            let previousRegion = lastRenderedRegion
            lastRenderedRegion = region

            let shouldNotify = !(previousRegion?.isApproximatelyEqual(to: region,
                                                                      centerTolerance: 5e-4,
                                                                      spanTolerance: 5e-4) ?? false)

            let capturedRegion = region
            isSettingRegion = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.parent.region = capturedRegion
                self.isSettingRegion = false
            }

            if shouldNotify {
                scheduleRegionChangeCallback(for: region, callback: parent.onRegionChange)
            } else {
                regionChangeTask?.cancel()
                regionChangeTask = nil
            }
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let payload = marker.userData as? MarkerPayload else { return false }

            switch payload.kind {
            case .pin:
                if let pin = payload.pin {
                    parent.onPinSelected?(pin)
                }
                mapView.selectedMarker = nil
                return true
            case .place:
                if usesDotMarkers {
                    mapView.selectedMarker = nil
                    return true
                }
                if let place = payload.place {
                    parent.selectedPlace = place
                    parent.onPlaceSelected?(place)
                }
                return true
            case .apple:
                if usesDotMarkers {
                    mapView.selectedMarker = nil
                    return true
                }
                if let mapItem = payload.mapItem {
                    parent.onAppleItemSelected?(mapItem)
                }
                return true
            }
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.onMapTap?()
        }

        private func syncPlaceMarkers(with places: [Place]) {
            let incomingIDs = Set(places.map(\.id))

            for (id, marker) in placeMarkersByID where !incomingIDs.contains(id) {
                marker.map = nil
                placeMarkersByID.removeValue(forKey: id)
            }

            for place in places {
                if let marker = placeMarkersByID[place.id] {
                    update(marker: marker, with: place)
                } else {
                    let marker = makePlaceMarker(for: place)
                    placeMarkersByID[place.id] = marker
                    if annotationMode == .places {
                        marker.map = mapView
                    }
                }
            }
        }

        private func syncPinMarkers(with pins: [PlacePin]) {
            let incomingIDs = Set(pins.map(\.id))

            for (id, marker) in pinMarkersByID where !incomingIDs.contains(id) {
                marker.map = nil
                pinMarkersByID.removeValue(forKey: id)
            }

            for pin in pins {
                if let marker = pinMarkersByID[pin.id] {
                    update(marker: marker, with: pin)
                } else {
                    let marker = makePinMarker(for: pin)
                    pinMarkersByID[pin.id] = marker
                    if annotationMode == .pins {
                        marker.map = mapView
                    }
                }
            }
        }

        private func syncAppleMarkers(with items: [MKMapItem]) {
            let incomingItems = items.compactMap { item -> (String, MKMapItem, CLLocationCoordinate2D)? in
                let coordinate = item.halalCoordinate
                if coordinate.latitude == 0 && coordinate.longitude == 0 {
                    return nil
                }
                return (item.halalPersistentIdentifier, item, coordinate)
            }

            let incomingIDs = Set(incomingItems.map(\.0))
            for (id, marker) in appleMarkersByID where !incomingIDs.contains(id) {
                marker.map = nil
                appleMarkersByID.removeValue(forKey: id)
            }

            for (id, item, coordinate) in incomingItems {
                if let marker = appleMarkersByID[id] {
                    update(marker: marker, with: item)
                    marker.position = coordinate
                } else {
                    let marker = makeAppleMarker(for: item, coordinate: coordinate)
                    appleMarkersByID[id] = marker
                    marker.map = mapView
                }
            }
        }

        private func updateMarkerDisplayMode(for mapView: GMSMapView,
                                             region: MKCoordinateRegion,
                                             pinCount: Int) {
            let shouldUsePins = shouldUseDotAppearance(for: region, placeCount: pinCount)
            let nextMode: AnnotationMode = shouldUsePins ? .pins : .places
            let needsStyleRefresh = usesDotMarkers != shouldUsePins
            guard nextMode != annotationMode || needsStyleRefresh else { return }

            annotationMode = nextMode
            usesDotMarkers = shouldUsePins

            if nextMode == .pins {
                placeMarkersByID.values.forEach { $0.map = nil }
                pinMarkersByID.values.forEach { $0.map = mapView }
            } else {
                pinMarkersByID.values.forEach { $0.map = nil }
                placeMarkersByID.values.forEach { $0.map = mapView }
            }

            appleMarkersByID.values.forEach { $0.map = mapView }

            refreshMarkerStyles()
        }

        private func refreshMarkerStylesIfNeeded(for mapView: GMSMapView) {
            let style = mapView.traitCollection.userInterfaceStyle
            guard style != lastInterfaceStyle else { return }
            lastInterfaceStyle = style
            labelIconCache.removeAll()
            refreshMarkerStyles()
        }

        private func refreshMarkerStyles() {
            for marker in placeMarkersByID.values {
                guard let payload = marker.userData as? MarkerPayload,
                      let place = payload.place else { continue }
                applyPlaceMarkerStyle(marker, place: place)
            }
            for marker in pinMarkersByID.values {
                guard let payload = marker.userData as? MarkerPayload, let pin = payload.pin else { continue }
                applyPinMarkerStyle(marker, pin: pin)
            }
            for marker in appleMarkersByID.values {
                guard let payload = marker.userData as? MarkerPayload,
                      let mapItem = payload.mapItem else { continue }
                applyAppleMarkerStyle(marker, mapItem: mapItem)
            }
        }

        private func update(marker: GMSMarker, with place: Place) {
            marker.position = place.coordinate
            marker.title = place.name
            marker.snippet = place.address
            marker.userData = MarkerPayload(place: place)
            applyPlaceMarkerStyle(marker, place: place)
        }

        private func update(marker: GMSMarker, with pin: PlacePin) {
            marker.position = pin.coordinate
            marker.snippet = pin.address
            marker.userData = MarkerPayload(pin: pin)
            applyPinMarkerStyle(marker, pin: pin)
        }

        private func update(marker: GMSMarker, with mapItem: MKMapItem) {
            marker.title = mapItem.name
            marker.snippet = mapItem.halalShortAddress
            marker.userData = MarkerPayload(mapItem: mapItem)
            applyAppleMarkerStyle(marker, mapItem: mapItem)
        }

        private func makePlaceMarker(for place: Place) -> GMSMarker {
            let marker = GMSMarker(position: place.coordinate)
            marker.title = place.name
            marker.snippet = place.address
            marker.userData = MarkerPayload(place: place)
            applyPlaceMarkerStyle(marker, place: place)
            return marker
        }

        private func makePinMarker(for pin: PlacePin) -> GMSMarker {
            let marker = GMSMarker(position: pin.coordinate)
            marker.snippet = pin.address
            marker.userData = MarkerPayload(pin: pin)
            applyPinMarkerStyle(marker, pin: pin)
            return marker
        }

        private func makeAppleMarker(for mapItem: MKMapItem,
                                     coordinate: CLLocationCoordinate2D) -> GMSMarker {
            let marker = GMSMarker(position: coordinate)
            marker.title = mapItem.name
            marker.snippet = mapItem.halalShortAddress
            marker.userData = MarkerPayload(mapItem: mapItem)
            applyAppleMarkerStyle(marker, mapItem: mapItem)
            return marker
        }

        private func applyPlaceMarkerStyle(_ marker: GMSMarker, place: Place) {
            let traits = currentTraitCollection()
            let color = tintColor(for: place.halalStatus)
            if usesDotMarkers {
                let icon = dotIcon(for: place.halalStatus)
                marker.icon = icon.image
                marker.groundAnchor = icon.anchor
            } else {
                let icon = labeledMarkerIcon(title: place.name,
                                             halalStatus: place.halalStatus,
                                             pinColor: color,
                                             labelColor: labelTextColor(for: place.halalStatus, traitCollection: traits),
                                             traitCollection: traits)
                marker.icon = icon.image
                marker.groundAnchor = icon.anchor
            }
        }

        private func applyPinMarkerStyle(_ marker: GMSMarker, pin: PlacePin) {
            let icon = dotIcon(for: pin.halalStatus)
            marker.icon = icon.image
            marker.groundAnchor = icon.anchor
        }

        private func applyAppleMarkerStyle(_ marker: GMSMarker, mapItem: MKMapItem) {
            let traits = currentTraitCollection()
            let color = tintColor(for: .yes)
            if usesDotMarkers {
                let icon = dotIcon(for: .yes)
                marker.icon = icon.image
                marker.groundAnchor = icon.anchor
            } else {
                let icon = labeledMarkerIcon(title: mapItem.name,
                                             halalStatus: .yes,
                                             pinColor: color,
                                             labelColor: labelTextColor(for: .yes, traitCollection: traits),
                                             traitCollection: traits)
                marker.icon = icon.image
                marker.groundAnchor = icon.anchor
            }
        }

        private func tintColor(for halalStatus: Place.HalalStatus) -> UIColor {
            if halalStatus == .only {
                return UIColor(red: 0.212, green: 0.812, blue: 0.361, alpha: 1)
            }
            return UIColor(red: 0.961, green: 0.486, blue: 0.0, alpha: 1)
        }

        private func labelTextColor(for halalStatus: Place.HalalStatus,
                                    traitCollection: UITraitCollection) -> UIColor {
            let baseColor: UIColor
            if halalStatus == .only {
                baseColor = UIColor(red: 0.086, green: 0.427, blue: 0.188, alpha: 1)
            } else {
                baseColor = UIColor(red: 0.843, green: 0.349, blue: 0.0, alpha: 1)
            }
            guard traitCollection.userInterfaceStyle == .dark else { return baseColor }
            let pinColor = tintColor(for: halalStatus)
            return blendColor(baseColor, with: pinColor, fraction: 0.55)
        }

        private func shouldUseDotAppearance(for region: MKCoordinateRegion, placeCount _: Int) -> Bool {
            max(region.span.latitudeDelta, region.span.longitudeDelta) >= dotSpanThreshold
        }

        private func dotIcon(for halalStatus: Place.HalalStatus) -> MarkerIcon {
            let color = tintColor(for: halalStatus)
            let key = colorKey(for: color)
            if let cached = dotIconCache[key] {
                return MarkerIcon(image: cached, anchor: CGPoint(x: 0.5, y: 0.5))
            }

            let renderer = UIGraphicsImageRenderer(size: dotSize)
            let image = renderer.image { context in
                let rect = CGRect(origin: .zero, size: dotSize)
                let insetRect = rect.insetBy(dx: 0.5, dy: 0.5)
                context.cgContext.setFillColor(color.cgColor)
                context.cgContext.fillEllipse(in: insetRect)
                context.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.8).cgColor)
                context.cgContext.setLineWidth(1)
                context.cgContext.strokeEllipse(in: insetRect)
            }
            dotIconCache[key] = image
            return MarkerIcon(image: image, anchor: CGPoint(x: 0.5, y: 0.5))
        }

        private func labeledMarkerIcon(title: String?,
                                       halalStatus: Place.HalalStatus,
                                       pinColor: UIColor,
                                       labelColor: UIColor,
                                       traitCollection: UITraitCollection) -> MarkerIcon {
            let displayTitle = displayTitleText(title)
            let pinKey = pinImageKey(for: halalStatus, size: pinSize, color: pinColor)
            let styleKey = traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
            let key = [pinKey, colorKey(for: labelColor), displayTitle ?? "", styleKey]
                .joined(separator: "|")
            if let cached = labelIconCache[key] {
                return cached
            }

            let font = UIFont.systemFont(ofSize: 12, weight: .medium)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail
            let isDarkMode = traitCollection.userInterfaceStyle == .dark
            let haloFraction: CGFloat = isDarkMode ? 0.1 : 0.12
            let haloPointWidth = font.pointSize * haloFraction
            let haloInset = ceil(haloPointWidth)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: labelColor,
                .paragraphStyle: paragraphStyle
            ]

            let labelHeight = ceil(font.lineHeight) + haloInset * 2
            let labelWidth: CGFloat
            if let displayTitle {
                let constraint = CGSize(width: maxLabelWidth, height: labelHeight)
                let size = (displayTitle as NSString).boundingRect(
                    with: constraint,
                    options: [.usesFontLeading, .usesLineFragmentOrigin],
                    attributes: attributes,
                    context: nil
                ).size
                labelWidth = min(maxLabelWidth, ceil(size.width)) + (labelPaddingX * 2) + (haloInset * 2)
            } else {
                labelWidth = 0
            }

            let pinImage = pinImage(for: halalStatus, size: pinSize)
            let resolvedPinSize = pinImage?.size ?? CGSize(width: markerDiameter, height: markerDiameter)
            let totalWidth = resolvedPinSize.width + (displayTitle == nil ? 0 : (labelSpacing + labelWidth))
            let totalHeight = max(resolvedPinSize.height, labelHeight)
            let anchorY = pinImage == nil ? 0.5 : (resolvedPinSize.height / totalHeight)
            let anchor = CGPoint(x: (resolvedPinSize.width / 2) / totalWidth, y: anchorY)

            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(
                size: CGSize(width: totalWidth, height: totalHeight),
                format: format
            )
            let image = renderer.image { context in
                let centerY = totalHeight / 2
                let pinRect = CGRect(
                    x: 0,
                    y: centerY - resolvedPinSize.height / 2,
                    width: resolvedPinSize.width,
                    height: resolvedPinSize.height
                )

                if let pinImage {
                    pinImage.draw(in: pinRect)
                } else {
                    context.cgContext.setShadow(
                        offset: CGSize(width: 0, height: 1),
                        blur: 1.5,
                        color: UIColor.black.withAlphaComponent(0.2).cgColor
                    )
                    context.cgContext.setFillColor(pinColor.cgColor)
                    context.cgContext.fillEllipse(in: pinRect)
                    context.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
                    context.cgContext.setLineWidth(1.5)
                    context.cgContext.strokeEllipse(in: pinRect.insetBy(dx: 0.75, dy: 0.75))
                    context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

                    if let glyph = glyphImage() {
                        let glyphSize = CGSize(width: 12, height: 12)
                        let glyphOrigin = CGPoint(
                            x: pinRect.midX - glyphSize.width / 2,
                            y: pinRect.midY - glyphSize.height / 2
                        )
                        glyph.draw(in: CGRect(origin: glyphOrigin, size: glyphSize))
                    }
                }

                guard let displayTitle else { return }
                let labelX = pinRect.maxX + labelSpacing
                let labelRect = CGRect(
                    x: labelX,
                    y: centerY - labelHeight / 2,
                    width: labelWidth,
                    height: labelHeight
                )
                let textRect = labelRect.insetBy(dx: labelPaddingX + haloInset, dy: haloInset)
                let baselineOffset = max(0, (textRect.height - font.lineHeight) / 2)
                let drawRect = CGRect(
                    x: textRect.minX,
                    y: textRect.minY + baselineOffset - 0.5,
                    width: textRect.width,
                    height: font.lineHeight
                )

                context.cgContext.setLineJoin(.round)
                context.cgContext.setLineCap(.round)
                let strokeWidth = haloFraction * 100
                let haloAlpha: CGFloat = isDarkMode ? 0.75 : 0.9
                let haloColor = UIColor(red: 1, green: 0.996, blue: 0.988, alpha: haloAlpha)
                let strokeAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: haloColor,
                    .strokeColor: haloColor,
                    .strokeWidth: strokeWidth
                ]
                (displayTitle as NSString).draw(in: drawRect, withAttributes: strokeAttributes)
                (displayTitle as NSString).draw(in: drawRect, withAttributes: attributes)
            }

            let icon = MarkerIcon(image: image, anchor: anchor)
            labelIconCache[key] = icon
            return icon
        }

        private func glyphImage() -> UIImage? {
            let configuration = UIImage.SymbolConfiguration(scale: .medium)
            return UIImage(systemName: "fork.knife", withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
        }

        private func displayTitleText(_ raw: String?) -> String? {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        private func pinImage(for halalStatus: Place.HalalStatus, size: CGSize) -> UIImage? {
            guard let assetName = pinAssetName(for: halalStatus),
                  let baseImage = UIImage(named: assetName) else { return nil }
            let key = "\(assetName)-\(Int(size.width))x\(Int(size.height))"
            if let cached = pinIconCache[key] {
                return cached
            }
            let scaled = scaledImage(baseImage, to: size)
            pinIconCache[key] = scaled
            return scaled
        }

        private func pinAssetName(for halalStatus: Place.HalalStatus) -> String? {
            switch halalStatus {
            case .only:
                return greenPinAssetName
            default:
                return orangePinAssetName
            }
        }

        private func pinImageKey(for halalStatus: Place.HalalStatus,
                                 size: CGSize,
                                 color: UIColor) -> String {
            let sizeKey = "\(Int(size.width))x\(Int(size.height))"
            if let assetName = pinAssetName(for: halalStatus) {
                return "\(assetName)-\(sizeKey)"
            }
            return "fallback-\(colorKey(for: color))-\(sizeKey)"
        }

        private func blendColor(_ color: UIColor, with other: UIColor, fraction: CGFloat) -> UIColor {
            let clamped = min(max(fraction, 0), 1)
            var r1: CGFloat = 0
            var g1: CGFloat = 0
            var b1: CGFloat = 0
            var a1: CGFloat = 0
            var r2: CGFloat = 0
            var g2: CGFloat = 0
            var b2: CGFloat = 0
            var a2: CGFloat = 0
            color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(
                red: r1 + (r2 - r1) * clamped,
                green: g1 + (g2 - g1) * clamped,
                blue: b1 + (b2 - b1) * clamped,
                alpha: a1 + (a2 - a1) * clamped
            )
        }

        private func currentTraitCollection() -> UITraitCollection {
            mapView?.traitCollection ?? UIScreen.main.traitCollection
        }

        private func scaledImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
            let sourceSize = image.size
            let scale = min(targetSize.width / sourceSize.width,
                            targetSize.height / sourceSize.height)
            let scaledSize = CGSize(width: sourceSize.width * scale,
                                    height: sourceSize.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: scaledSize))
            }
        }

        private func colorKey(for color: UIColor) -> String {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return String(format: "%.3f-%.3f-%.3f-%.3f", red, green, blue, alpha)
        }

        private func currentRegion(for mapView: GMSMapView) -> MKCoordinateRegion? {
            let visibleRegion = mapView.projection.visibleRegion()
            return region(from: visibleRegion)
        }

        private func region(from visibleRegion: GMSVisibleRegion) -> MKCoordinateRegion? {
            let latitudes = [
                visibleRegion.nearLeft.latitude,
                visibleRegion.nearRight.latitude,
                visibleRegion.farLeft.latitude,
                visibleRegion.farRight.latitude
            ]
            let longitudes = [
                visibleRegion.nearLeft.longitude,
                visibleRegion.nearRight.longitude,
                visibleRegion.farLeft.longitude,
                visibleRegion.farRight.longitude
            ]

            guard let minLat = latitudes.min(),
                  let maxLat = latitudes.max(),
                  let minLon = longitudes.min(),
                  let maxLon = longitudes.max() else { return nil }

            let span = MKCoordinateSpan(latitudeDelta: maxLat - minLat, longitudeDelta: maxLon - minLon)
            guard span.latitudeDelta > 0, span.longitudeDelta > 0 else { return nil }

            let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                                longitude: (minLon + maxLon) / 2)
            return MKCoordinateRegion(center: center, span: span)
        }

        private func cameraUpdate(for region: MKCoordinateRegion, in mapView: GMSMapView) -> GMSCameraUpdate {
            let bounds = coordinateBounds(for: region)
            if mapView.bounds.width > 0, mapView.bounds.height > 0 {
                return GMSCameraUpdate.fit(bounds, withPadding: 0)
            }
            let zoom = zoomLevel(for: region)
            return GMSCameraUpdate.setCamera(GMSCameraPosition(target: region.center, zoom: zoom))
        }

        private func coordinateBounds(for region: MKCoordinateRegion) -> GMSCoordinateBounds {
            let halfLat = region.span.latitudeDelta / 2
            let halfLon = region.span.longitudeDelta / 2
            let northEast = CLLocationCoordinate2D(latitude: region.center.latitude + halfLat,
                                                   longitude: region.center.longitude + halfLon)
            let southWest = CLLocationCoordinate2D(latitude: region.center.latitude - halfLat,
                                                   longitude: region.center.longitude - halfLon)
            return GMSCoordinateBounds(coordinate: northEast, coordinate: southWest)
        }

        func zoomLevel(for region: MKCoordinateRegion) -> Float {
            let span = max(region.span.longitudeDelta, 0.0001)
            let width = max(UIScreen.main.bounds.width * UIScreen.main.scale, 1)
            let zoom = log2(360 * Double(width) / 256 / span)
            return Float(max(2, min(20, zoom)))
        }

        private func scheduleRegionChangeCallback(for region: MKCoordinateRegion,
                                                  callback: ((MKCoordinateRegion) -> Void)?) {
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
                    callback(region)
                    self.regionChangeTask = nil
                }
            }
        }

        private struct MarkerIcon {
            let image: UIImage
            let anchor: CGPoint
        }

        deinit {
            regionChangeTask?.cancel()
        }
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
