import Combine
import CoreLocation
import MapKit
import SwiftUI
import UIKit

enum MapFilter: CaseIterable, Identifiable {
    case topRated
    case openNow
    case new

    var id: Self { self }

    var title: String {
        switch self {
        case .topRated: return "Top Rated"
        case .openNow: return "Open Now"
        case .new: return "New"
        }
    }
}

struct ContentView: View {
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
    )
    @State private var selectedFilter: MapFilter = .topRated
    @State private var selectedPlace: Place?
    @StateObject private var viewModel = MapScreenViewModel()
    @StateObject private var locationManager = LocationProvider()
    @StateObject private var appleHalalSearch = AppleHalalSearchService()
    @State private var bottomSheetState: BottomSheetState = .collapsed
    @State private var hasCenteredOnUser = false
    @State private var selectedApplePlace: ApplePlaceSelection?
    @State private var searchQuery = ""
    @FocusState private var searchFieldIsFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

    private var appleOverlayItems: [MKMapItem] {
        let supabaseLocations = viewModel.places.map {
            CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }

        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return appleHalalSearch.results.filter { item in
            guard let coordinate = mapItemCoordinate(item) else { return false }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

            let matchesExisting = supabaseLocations.contains { existing in
                existing.distance(from: location) < 80
            }

            if matchesExisting { return false }

            if !trimmed.isEmpty {
                let nameMatches = item.name?.localizedCaseInsensitiveContains(trimmed) ?? false
                return nameMatches
            }

            return true
        }
    }

    private var filteredPlaces: [Place] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.places }

        let matches = viewModel.searchResults
        if matches.isEmpty, viewModel.isSearching {
            return viewModel.places
        }
        return matches
    }

    private func mapItemCoordinate(_ mapItem: MKMapItem) -> CLLocationCoordinate2D? {
        let coordinate = mapItem.halalCoordinate
        if coordinate.latitude == 0 && coordinate.longitude == 0 {
            return nil
        }
        return coordinate
    }

    var body: some View {
        ZStack(alignment: .top) {
            HalalMapView(
                region: $mapRegion,
                places: filteredPlaces,
                appleMapItems: appleOverlayItems,
                onRegionChange: { region in
                    viewModel.regionDidChange(to: region, filter: selectedFilter)
                    appleHalalSearch.search(in: region)
                },
                onPlaceSelected: { place in
                    selectedPlace = place
                },
                onAppleItemSelected: { mapItem in
                    selectedApplePlace = ApplePlaceSelection(mapItem: mapItem)
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                topSegmentedControl
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)

            VStack {
                Spacer()
                if keyboardHeight == 0 {
                    searchAreaButton
                        .padding(.bottom, bottomOverlayPadding)
                }
            }

            VStack(spacing: 0) {
                Spacer()
                bottomSheet
            }
            .ignoresSafeArea(edges: .bottom)

            if viewModel.isLoading && viewModel.places.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(16)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .onAppear {
            viewModel.initialLoad(region: mapRegion, filter: selectedFilter)
            locationManager.requestAuthorizationIfNeeded()
            appleHalalSearch.search(in: mapRegion)
        }
        .onChange(of: selectedFilter) { oldValue, newValue in
            guard oldValue != newValue else { return }
            viewModel.filterChanged(to: newValue, region: mapRegion)
        }
        .onChange(of: searchFieldIsFocused) { _, isFocused in
            if isFocused && !isBottomSheetExpanded {
                expandBottomSheet()
            }
        }
        .onReceive(locationManager.$lastKnownLocation.compactMap { $0 }) { location in
            guard !hasCenteredOnUser else { return }
            let span = MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            let region = MKCoordinateRegion(center: location.coordinate, span: span)
            mapRegion = region
            viewModel.forceRefresh(region: region, filter: selectedFilter)
            hasCenteredOnUser = true
            appleHalalSearch.search(in: region)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let info = notification.userInfo,
                  let frameValue = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let overlap = max(0, frameValue.height - currentBottomSafeAreaInset())
            keyboardHeight = overlap
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onChange(of: searchQuery) { _, newValue in
            viewModel.search(query: newValue)
        }
        .alert("Unable to load places", isPresented: $viewModel.presentingError) {
            Button("OK", role: .cancel) {
                viewModel.presentingError = false
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unexpected error occurred.")
        }
        .sheet(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedApplePlace) { selection in
            if #available(iOS 18.0, *) {
                MapItemDetailCardView(mapItem: selection.mapItem, showsInlineMap: true) {
                    selectedApplePlace = nil
                }
                .presentationDetents([.medium, .large])
            } else {
                AppleFallbackDetailView(details: ApplePlaceDetails(mapItem: selection.mapItem))
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var topSegmentedControl: some View {
        Picker("Category", selection: $selectedFilter) {
            ForEach(MapFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search Halal Restaurants", text: $searchQuery)
                .focused($searchFieldIsFocused)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.search)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchAreaButton: some View {
        Button {
            viewModel.forceRefresh(region: mapRegion, filter: selectedFilter)
            appleHalalSearch.search(in: mapRegion)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
                Text("Search this area")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Color(.systemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .opacity(viewModel.isLoading ? 0.7 : 1)
        .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
    }

    private var locateMeButton: some View {
        Button {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestAuthorizationIfNeeded()
            case .authorizedWhenInUse, .authorizedAlways:
                if let location = locationManager.lastKnownLocation {
                    let targetRegion = MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                    mapRegion = targetRegion
                    viewModel.forceRefresh(region: targetRegion, filter: selectedFilter)
                    appleHalalSearch.search(in: targetRegion)
                } else {
                    locationManager.requestCurrentLocation()
                }
            case .denied, .restricted:
                viewModel.errorMessage = "Enable location access in Settings to jump to your position."
                viewModel.presentingError = true
            @unknown default:
                break
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.blue)
                .frame(width: 50, height: 50)
                .background(Color(.systemBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
        .accessibilityLabel("Center on your location")
    }

    private var isBottomSheetExpanded: Bool { bottomSheetState == .expanded }

    private var bottomOverlayPadding: CGFloat {
        bottomSheetState == .collapsed ? 150 : 320
    }

    private var locationButtonOpacity: Double {
        isBottomSheetExpanded ? 0 : 1
    }

    private var bottomSheet: some View {
        VStack(alignment: .leading, spacing: isBottomSheetExpanded ? 18 : 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.22))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleBottomSheet()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onEnded { value in
                            let threshold: CGFloat = 60
                            if value.translation.height > threshold {
                                collapseBottomSheet()
                            } else if value.translation.height < -threshold {
                                expandBottomSheet()
                            }
                        }
                )

            searchSection

            if isBottomSheetExpanded {
                recommendationsSection
            }
        }
        .padding(.horizontal, isBottomSheetExpanded ? 22 : 18)
        .padding(.top, isBottomSheetExpanded ? 20 : 14)
        .padding(.bottom, isBottomSheetExpanded ? 26 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: isBottomSheetExpanded ? 28 : 42, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        )
        .overlay(alignment: .topTrailing) {
            locateMeButton
                .padding(.trailing, isBottomSheetExpanded ? 22 : 18)
                .offset(y: isBottomSheetExpanded ? -6 : -22)
                .opacity(locationButtonOpacity)
                .allowsHitTesting(!isBottomSheetExpanded)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20 + (keyboardHeight > 0 ? keyboardHeight : 0))
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: bottomSheetState)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: keyboardHeight)
    }
}

private extension ContentView {
    var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBar
            if isBottomSheetExpanded && !viewModel.errorDescription.isEmpty {
                Text(viewModel.errorDescription)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    var recommendationsSection: some View {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let recommendationPlaces = Array(viewModel.places.prefix(20))
        let searchPlaces = viewModel.searchResults
        let appleMatches = trimmedQuery.isEmpty ? [] : appleOverlayItems

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if trimmedQuery.isEmpty {
                    recommendationsHeader
                    placeList(places: recommendationPlaces)
                    if let message = viewModel.subtitleMessage, recommendationPlaces.isEmpty {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    searchResultsHeader
                    if viewModel.isSearching && searchPlaces.isEmpty && appleMatches.isEmpty {
                        Text("Searching for \"\(trimmedQuery)\"…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if searchPlaces.isEmpty && appleMatches.isEmpty {
                        Text("No matches for \"\(trimmedQuery)\".")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        if !searchPlaces.isEmpty {
                            placeList(places: Array(searchPlaces.prefix(40)))
                        }
                        if !appleMatches.isEmpty {
                            appleResultsHeader
                            applePlaceList(items: Array(appleMatches.prefix(15)))
                        }
                    }

                    if !recommendationPlaces.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                        recommendationsHeader
                        placeList(places: Array(recommendationPlaces.prefix(10)))
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .frame(height: trimmedQuery.isEmpty ? 220 : 320)
    }

    private var recommendationsHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Recommendations near you")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            headerTrailingControl
        }
    }

    private var searchResultsHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Search results")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            if viewModel.isSearching {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
    }

    private var appleResultsHeader: some View {
        Text("Apple Maps results")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func placeList(places: [Place]) -> some View {
        ForEach(places, id: \.id) { place in
            Button {
                focus(on: place)
            } label: {
                PlaceRow(place: place)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func applePlaceList(items: [MKMapItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            Button {
                focus(on: item)
            } label: {
                ApplePlaceRow(mapItem: item)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var headerTrailingControl: some View {
        if viewModel.isLoading {
            ProgressView()
                .progressViewStyle(.circular)
        } else {
            Button("Refresh") {
                viewModel.forceRefresh(region: mapRegion, filter: selectedFilter)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func currentBottomSafeAreaInset() -> CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return 0
        }
        return window.safeAreaInsets.bottom
    }

    func toggleBottomSheet() {
        if isBottomSheetExpanded {
            collapseBottomSheet()
        } else {
            expandBottomSheet()
        }
    }

    func collapseBottomSheet() {
        searchFieldIsFocused = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            bottomSheetState = .collapsed
        }
    }

    func expandBottomSheet() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            bottomSheetState = .expanded
        }
    }

    func focus(on place: Place) {
        searchFieldIsFocused = false
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let targetRegion = adjustedRegion(centeredOn: place.coordinate, span: span)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            mapRegion = targetRegion
        }
        collapseBottomSheet()
        selectedPlace = place
    }

    func focus(on mapItem: MKMapItem) {
        searchFieldIsFocused = false
        let coordinate = mapItem.halalCoordinate
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return }
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let targetRegion = adjustedRegion(centeredOn: coordinate, span: span)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            mapRegion = targetRegion
        }
        collapseBottomSheet()
        selectedPlace = nil
        selectedApplePlace = ApplePlaceSelection(mapItem: mapItem)
    }

    private func adjustedRegion(centeredOn coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan) -> MKCoordinateRegion {
        var center = coordinate
        let verticalOffset = span.latitudeDelta * verticalOffsetMultiplier()
        center.latitude = clampedLatitude(center.latitude - verticalOffset, span: span)
        return MKCoordinateRegion(center: center, span: span)
    }

    private func verticalOffsetMultiplier() -> Double {
        if keyboardHeight > 0 {
            let screenHeight = max(currentScreenHeight(), 1)
            let ratio = min(1.0, Double(keyboardHeight) / screenHeight)
            return 0.28 + (0.32 * ratio)
        }
        return isBottomSheetExpanded ? 0.22 : 0.15
    }

    private func clampedLatitude(_ latitude: Double, span: MKCoordinateSpan) -> Double {
        let halfSpan = span.latitudeDelta / 2
        let minLatitude = max(-90.0 + halfSpan, -90.0)
        let maxLatitude = min(90.0 - halfSpan, 90.0)
        return min(maxLatitude, max(minLatitude, latitude))
    }

    private func currentScreenHeight() -> Double {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        if let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return Double(activeScene.screen.bounds.height)
        }

        if let anyScene = scenes.first {
            return Double(anyScene.screen.bounds.height)
        }

        return 812 // Sensible default for calculations when no screen is available
    }
}

private struct PlaceRow: View {
    let place: Place

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            let iconName = place.category == .restaurant ? "fork.knife.circle.fill" : "mappin.circle.fill"
            let iconColor: Color = place.category == .restaurant ? .orange : .yellow
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(place.name)
                    .font(.headline)
                if let address = place.address {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(place.halalStatus.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let rating = place.rating {
                    let count = place.ratingCount ?? 0
                    Text(String(format: "%.1f★ (%d)", rating, count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let source = place.source {
                    Text("Source: \(source.uppercased())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ApplePlaceRow: View {
    let mapItem: MKMapItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin.circle")
                .font(.title3)
                .foregroundStyle(Color.orange)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(mapItem.name ?? "Apple Maps Place")
                    .font(.headline)

                if let address = mapItem.halalShortAddress {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Apple Maps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PlaceDetailView: View {
    let place: Place

    @StateObject private var viewModel = PlaceDetailViewModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                halalSection
                Divider().opacity(0.4)
                appleSection
            }
            .padding(24)
        }
        .task(id: place.id) {
            await viewModel.load(place: place)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(displayName)
                .font(.title2)
                .fontWeight(.semibold)

            if let address = displayAddress, !address.isEmpty {
                Label(address, systemImage: "mappin.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !hasAppleDetails, let rating = place.rating {
                let count = place.ratingCount ?? 0
                Label(String(format: "%.1f rating (%d reviews)", rating, count), systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !hasAppleDetails, let source = place.source {
                Text("Source: \(source.uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var halalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(place.halalStatus.label, systemImage: "checkmark.seal")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Our halal classification comes from our own Supabase dataset.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var appleSection: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: 12) {
                Label("Loading Apple Maps details…", systemImage: "apple.logo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView()
            }
            .frame(maxWidth: .infinity)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label("Apple Maps unavailable", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("We never cache Apple Maps data. We'll retry the next time you open this place.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        case .loaded(let details):
            if #available(iOS 18.0, *) {
                applePlaceCard(details)
            } else {
                appleDetailsSection(details)
            }
        }
    }

    @ViewBuilder
    private func appleDetailsSection(_ details: ApplePlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Live from Apple Maps")
                        .font(.headline)
                    if let shortAddress = details.shortAddress {
                        Text(shortAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if let phone = details.phoneNumber {
                    let sanitized = viewModel.telephoneURLString(from: phone)
                    if let phoneURL = sanitized.isEmpty ? nil : URL(string: "tel://\(sanitized)") {
                        Button {
                            openURL(phoneURL)
                        } label: {
                            Label(phone, systemImage: "phone")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if let website = details.websiteURL {
                    Link(destination: website) {
                        Label("Website", systemImage: "safari")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let category = details.pointOfInterestCategory {
                    Label(category.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "tag")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if let appleID = details.applePlaceID {
                    Text("Place ID: \(appleID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                viewModel.openInMaps()
            } label: {
                Label("Open in Apple Maps", systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("Apple Maps details are loaded live at runtime to stay within Apple's terms of use. Only the identifier is cached.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var displayName: String {
        if case let .loaded(details) = viewModel.loadingState, !details.displayName.isEmpty {
            return details.displayName
        }
        return place.name
    }

    private var displayAddress: String? {
        if case let .loaded(details) = viewModel.loadingState {
            if let short = details.shortAddress, !short.isEmpty {
                return short
            }
            if let full = details.fullAddress, !full.isEmpty {
                return full
            }
        }
        return place.address
    }

    private var hasAppleDetails: Bool {
        if case .loaded = viewModel.loadingState { return true }
        return false
    }

    @ViewBuilder
    private func applePlaceCard(_ details: ApplePlaceDetails) -> some View {
        MapItemDetailCardView(mapItem: details.mapItem, showsInlineMap: false) {
            dismiss()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 520)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

private struct ApplePlaceSelection: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem
}

private struct AppleFallbackDetailView: View {
    let details: ApplePlaceDetails
    @Environment(\.openURL) private var openURL

    var body: some View {
        let name = details.displayName.isEmpty ? "Apple Maps Place" : details.displayName

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let address = details.fullAddress ?? details.shortAddress {
                        Text(address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let phone = details.phoneNumber,
                   let phoneURL = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Button {
                        openURL(phoneURL)
                    } label: {
                        Label(phone, systemImage: "phone")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let website = details.websiteURL {
                    Link(destination: website) {
                        Label("Website", systemImage: "safari")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Button {
                    details.mapItem.openInMaps()
                } label: {
                    Label("Open in Apple Maps", systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }
}

@MainActor
final class AppleHalalSearchService: ObservableObject {
    @Published private(set) var results: [MKMapItem] = []

    private var searchTask: Task<Void, Never>?
    private var lastRegion: MKCoordinateRegion?
    private let debounceNanoseconds: UInt64 = 500_000_000

    func search(in region: MKCoordinateRegion) {
        guard region.span.latitudeDelta > 0, region.span.longitudeDelta > 0 else { return }

        if let last = lastRegion, regionIsSimilar(lhs: last, rhs: region) {
            return
        }

        searchTask?.cancel()
        searchTask = Task<Void, Never> { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            if Task.isCancelled { return }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "halal restaurant"
            request.region = region
            request.resultTypes = [.pointOfInterest]
            if #available(iOS 13.0, *) {
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant])
            }

            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                await MainActor.run {
                    self.results = response.mapItems
                    self.lastRegion = region
                }
            } catch is CancellationError {
                // Ignore cancellations
            } catch {
#if DEBUG
                print("[AppleHalalSearchService] search failed: \(error)")
#endif
            }
        }
    }

    private func regionIsSimilar(lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        let latDiff = abs(lhs.center.latitude - rhs.center.latitude)
        let lonDiff = abs(lhs.center.longitude - rhs.center.longitude)
        let latSpanDiff = abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta)
        let lonSpanDiff = abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta)
        let threshold = 0.002
        return latDiff < threshold && lonDiff < threshold && latSpanDiff < threshold && lonSpanDiff < threshold
    }
}

@MainActor
final class PlaceDetailViewModel: ObservableObject {
    enum LoadingState {
        case idle
        case loading
        case loaded(ApplePlaceDetails)
        case failed(String)
    }

    @Published private(set) var loadingState: LoadingState = .idle

    private let service: ApplePlaceDetailService
    private var lastSuccessfulPlaceID: UUID?

    init(service: ApplePlaceDetailService? = nil) {
        if let service {
            self.service = service
        } else {
            self.service = ApplePlaceDetailService.shared
        }
    }

    func load(place: Place) async {
        if case .loaded = loadingState,
           lastSuccessfulPlaceID == place.id {
            return
        }

        loadingState = .loading
        do {
            let details = try await service.details(for: place)
            loadingState = .loaded(details)
            lastSuccessfulPlaceID = place.id
        } catch is CancellationError {
            loadingState = .idle
            lastSuccessfulPlaceID = nil
        } catch let serviceError as ApplePlaceDetailServiceError {
            loadingState = .failed(serviceError.errorDescription ?? "Apple Maps couldn't load right now.")
            lastSuccessfulPlaceID = nil
        } catch {
            loadingState = .failed(error.localizedDescription)
            lastSuccessfulPlaceID = nil
        }
    }

    func openInMaps() {
        guard case .loaded(let details) = loadingState else { return }
#if os(iOS)
        details.mapItem.openInMaps()
#endif
    }

    func telephoneURLString(from rawValue: String) -> String {
        var digits = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = Set("+0123456789")
        digits.removeAll { !allowed.contains($0) }
        if digits.first == "+" {
            let prefix = String(digits.prefix(1))
            let rest = String(digits.dropFirst().filter { $0.isNumber })
            return prefix + rest
        } else {
            return String(digits.filter { $0.isNumber })
        }
    }
}

private enum BottomSheetState {
    case collapsed
    case expanded
}

@MainActor
final class MapScreenViewModel: @MainActor ObservableObject {
    @Published private(set) var places: [Place] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var presentingError = false
    @Published private(set) var searchResults: [Place] = []
    @Published private(set) var isSearching = false

    var subtitleMessage: String? {
        guard !isLoading else { return "We're looking for new halal spots." }
        guard !places.isEmpty else { return "Pan the map, then tap \"Search this area\"." }
        return nil
    }

    var errorDescription: String {
        guard let message = errorMessage, !presentingError else { return "" }
        return message
    }

    private var fetchTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var manualSearchTask: Task<Void, Never>?
    private var globalIndexTask: Task<Void, Never>?
    private var lastRequestedRegion: MKCoordinateRegion?
    private var cache = PlaceCache()
    private var allPlaces: [Place] = []
    private var globalSearchIndex: [Place] = []
    private var currentFilter: MapFilter = .topRated

    func initialLoad(region: MKCoordinateRegion, filter: MapFilter) {
        currentFilter = filter
        guard allPlaces.isEmpty else {
            apply(filter: filter)
            return
        }
        prefetchGlobalSearchIndexIfNeeded()
        fetch(region: region, filter: filter, eager: true)
    }

    func filterChanged(to filter: MapFilter, region: MKCoordinateRegion) {
        currentFilter = filter
        if allPlaces.isEmpty {
            fetch(region: region, filter: filter, eager: true)
        } else {
            apply(filter: filter)
        }
    }

    func regionDidChange(to region: MKCoordinateRegion, filter: MapFilter) {
        currentFilter = filter
        fetch(region: region, filter: filter, eager: false)
    }

    func forceRefresh(region: MKCoordinateRegion, filter: MapFilter) {
        lastRequestedRegion = nil
        fetch(region: region, filter: filter, eager: true)
    }

    func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()

        manualSearchTask?.cancel()

        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        prefetchGlobalSearchIndexIfNeeded()

        let seededMatches = combinedMatches(for: trimmed)
        searchResults = PlaceOverrides.sorted(seededMatches)
        isSearching = true

        manualSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let exclusion = self.searchResults + self.allPlaces + self.globalSearchIndex
            let additionalManual = await ManualPlaceResolver.shared.searchMatches(for: trimmed, excluding: exclusion)
            guard !Task.isCancelled else { return }
            guard !additionalManual.isEmpty else { return }
            self.mergeIntoGlobalSearchIndex(additionalManual)
            let merged = self.deduplicate(self.searchResults + additionalManual)
            self.searchResults = PlaceOverrides.sorted(merged)
        }

        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                try Task.checkCancellation()
                let dtos = try await PlaceAPI.searchPlaces(matching: trimmed, limit: 60)
                try Task.checkCancellation()
                let remotePlaces = dtos.compactMap(Place.init(dto:))
                guard !Task.isCancelled else { return }
                if !remotePlaces.isEmpty {
                    self.mergeIntoGlobalSearchIndex(remotePlaces)
                    let merged = self.deduplicate(self.searchResults + remotePlaces)
                    self.searchResults = PlaceOverrides.sorted(merged)
                }
                self.isSearching = false
            } catch is CancellationError {
                self.isSearching = false
            } catch {
                self.isSearching = false
            }
        }
    }

    private func fetch(region: MKCoordinateRegion, filter: MapFilter, eager: Bool) {
        let cacheHit = cache.value(for: region)
        let cachedOverride = cacheHit.map { PlaceOverrides.apply(overridesTo: $0.places, in: region) }

        if let cachedPlaces = cachedOverride {
            allPlaces = cachedPlaces
            apply(filter: filter)
            if cacheHit?.isFresh == true && !eager {
                isLoading = false
                return
            }
        }

        if let last = lastRequestedRegion,
           regionIsSimilar(lhs: last, rhs: region),
           !(cacheHit == nil || cacheHit?.isFresh == false || eager) {
            return
        }

        fetchTask?.cancel()
        isLoading = true
        errorMessage = nil
        presentingError = false
        lastRequestedRegion = region

        fetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if !eager {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            do {
                let dtos = try await PlaceAPI.getPlaces(bbox: region.bbox)
                let results = dtos.compactMap(Place.init(dto:))
                let overridden = PlaceOverrides.apply(overridesTo: results, in: region)
                try Task.checkCancellation()
                self.allPlaces = overridden
                self.mergeIntoGlobalSearchIndex(overridden)
                self.apply(filter: self.currentFilter)
                self.isLoading = false
                self.cache.store(overridden, region: region)
            } catch is CancellationError {
                // Swallow cancellation; any inflight request will manage loading state.
            } catch {
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    return
                }
                self.errorMessage = Self.message(for: error)
                self.presentingError = true
                if self.places.isEmpty, let cachedPlaces = cachedOverride {
                    self.allPlaces = cachedPlaces
                    self.apply(filter: self.currentFilter)
                }
                self.isLoading = false
            }
        }
    }

    private func apply(filter: MapFilter) {
        let filtered: [Place]
        switch filter {
        case .topRated:
            filtered = allPlaces
        case .openNow:
            let candidates = allPlaces.filter { ($0.ratingCount ?? 0) >= 5 }
            filtered = candidates.isEmpty ? allPlaces : candidates
        case .new:
            let candidates = allPlaces.filter { ($0.ratingCount ?? 0) < 5 }
            if candidates.isEmpty {
                filtered = allPlaces
            } else {
                filtered = candidates.sorted { ($0.ratingCount ?? Int.max) < ($1.ratingCount ?? Int.max) }
            }
        }
        places = filtered
    }

    private func regionIsSimilar(lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        let latDiff = abs(lhs.center.latitude - rhs.center.latitude)
        let lonDiff = abs(lhs.center.longitude - rhs.center.longitude)
        let latSpanDiff = abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta)
        let lonSpanDiff = abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta)
        let threshold = 0.001
        return latDiff < threshold && lonDiff < threshold && latSpanDiff < threshold && lonSpanDiff < threshold
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? PlaceAPIError {
            switch apiError {
            case .invalidURL:
                return "The Supabase URL is misconfigured. Double-check the Info.plist entries."
            case .invalidResponse:
                return "Supabase returned an unexpected response."
            case let .server(statusCode, body):
                if statusCode == 401 || statusCode == 403 {
                    return "Supabase rejected the request. Make sure the anon key is correct and RLS allows access."
                }
                if let body, !body.isEmpty {
                    return "Supabase error (\(statusCode)): \(body)"
                }
                return "Supabase error (\(statusCode)). Try again later."
            }
        }
        if error is DecodingError {
            return "The place data was in an unexpected format."
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "The request timed out. Please try again."
            default:
                return urlError.localizedDescription
            }
        }
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return "We couldn't reach Supabase right now. Pull to refresh or try again in a moment."
    }

    deinit {
        fetchTask?.cancel()
        searchTask?.cancel()
        manualSearchTask?.cancel()
        globalIndexTask?.cancel()
    }
}

private extension MapScreenViewModel {
    func combinedMatches(for query: String) -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let local = matches(in: allPlaces, query: trimmed)
        let global = matches(in: globalSearchIndex, query: trimmed)
        return deduplicate(local + global)
    }

    func matches(in source: [Place], query: String) -> [Place] {
        source.filter { place in
            place.name.localizedCaseInsensitiveContains(query) ||
            (place.address?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    func prefetchGlobalSearchIndexIfNeeded() {
        guard globalSearchIndex.isEmpty, globalIndexTask == nil else { return }
        globalIndexTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let world = BBox(west: -179.9, south: -80.0, east: 179.9, north: 83.0)
                let dtos = try await PlaceAPI.getPlaces(bbox: world, limit: 750)
                let places = dtos.compactMap(Place.init(dto:))
                try Task.checkCancellation()
                self.mergeIntoGlobalSearchIndex(places)
            } catch is CancellationError {
#if DEBUG
                print("[MapScreenViewModel] Global search index prefetch cancelled")
#endif
            } catch {
#if DEBUG
                print("[MapScreenViewModel] Failed to prefetch global search index:", error)
#endif
            }
            self.globalIndexTask = nil
        }
    }

    func mergeIntoGlobalSearchIndex(_ newPlaces: [Place]) {
        guard !newPlaces.isEmpty else { return }
        let combined = deduplicate(globalSearchIndex + newPlaces)
        let sorted = PlaceOverrides.sorted(combined)
        let cap = 2000
        globalSearchIndex = sorted.count > cap ? Array(sorted.prefix(cap)) : sorted
    }

    func deduplicate(_ places: [Place]) -> [Place] {
        var seen = Set<String>()
        var result: [Place] = []
        for place in places {
            let latKey = String(format: "%.3f", place.coordinate.latitude)
            let lonKey = String(format: "%.3f", place.coordinate.longitude)
            let key = "\(PlaceOverrides.normalizedName(for: place.name)):\(latKey):\(lonKey)"
            if seen.insert(key).inserted {
                result.append(place)
            }
        }
        return result
    }
}

private struct PlaceCache {
    private struct Entry {
        let places: [Place]
        let timestamp: Date
    }

    private let ttl: TimeInterval
    private let staleCutoffMultiplier: Double = 3
    private var storage: [RegionCacheKey: Entry] = [:]

    init(ttl: TimeInterval = 600) {
        self.ttl = ttl
    }

    mutating func store(_ places: [Place], region: MKCoordinateRegion) {
        let key = RegionCacheKey(region: region)
        storage[key] = Entry(places: places, timestamp: Date())
    }

    mutating func value(for region: MKCoordinateRegion) -> (places: [Place], isFresh: Bool)? {
        let key = RegionCacheKey(region: region)
        guard let entry = storage[key] else { return nil }

        let age = Date().timeIntervalSince(entry.timestamp)
        if age > ttl * staleCutoffMultiplier {
            storage.removeValue(forKey: key)
            return nil
        }

        return (entry.places, age < ttl)
    }
}

private struct RegionCacheKey: Hashable {
    let latBucket: Int
    let lonBucket: Int
    let latSpanBucket: Int
    let lonSpanBucket: Int

    init(region: MKCoordinateRegion) {
        latBucket = Self.bucket(for: region.center.latitude)
        lonBucket = Self.bucket(for: region.center.longitude)
        latSpanBucket = Self.bucket(for: region.span.latitudeDelta)
        lonSpanBucket = Self.bucket(for: region.span.longitudeDelta)
    }

    private static func bucket(for value: Double) -> Int {
        Int((value * 100).rounded())
    }
}

#Preview {
    ContentView()
}
