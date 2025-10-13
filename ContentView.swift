import Combine
import CoreLocation
import MapKit
import SwiftUI
import UIKit

enum MapFilter: CaseIterable, Identifiable {
    case all
    case fullyHalal
    case partialHalal

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .fullyHalal: return "Fully Halal"
        case .partialHalal: return "Partial Halal"
        }
    }
}

private enum FavoritesSortOption: String, CaseIterable, Identifiable {
    case recentlySaved
    case alphabetical
    case rating

    var id: Self { self }

    var title: String {
        switch self {
        case .recentlySaved: return "Recent"
        case .alphabetical: return "A–Z"
        case .rating: return "Rating"
        }
    }
}

private enum TopRatedSortOption: String, CaseIterable, Identifiable {
    case rating
    case alphabetical

    var id: Self { self }

    var title: String {
        switch self {
        case .rating: return "Rating"
        case .alphabetical: return "A–Z"
        }
    }
}

private enum TopRatedRegion: String, CaseIterable, Identifiable {
    case all
    case manhattan
    case brooklyn
    case queens
    case bronx
    case statenIsland
    case longIsland

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All Locations"
        case .manhattan: return "Manhattan"
        case .brooklyn: return "Brooklyn"
        case .queens: return "Queens"
        case .bronx: return "Bronx"
        case .statenIsland: return "Staten Island"
        case .longIsland: return "Long Island"
        }
    }
}

struct ContentView: View {
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
    )
    @State private var selectedFilter: MapFilter = .all
    @State private var bottomTab: BottomTab = .places
    @State private var selectedPlace: Place?
    @StateObject private var viewModel = MapScreenViewModel()
    @StateObject private var locationManager = LocationProvider()
    @StateObject private var appleHalalSearch = AppleHalalSearchService()
    @StateObject private var favoritesStore = FavoritesStore()
    @State private var favoritesSort: FavoritesSortOption = .recentlySaved
    @State private var topRatedSort: TopRatedSortOption = .rating
    @State private var topRatedRegion: TopRatedRegion = .all
    @State private var hasCenteredOnUser = false
    @State private var selectedApplePlace: ApplePlaceSelection?
    @State private var searchQuery = ""
    @State private var isSearchOverlayPresented = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var previousMapRegion: MKCoordinateRegion?

    private var appleOverlayItems: [MKMapItem] {
        guard selectedFilter == .all else { return [] }

        let supabaseLocations = viewModel.places.map {
            CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }

        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = PlaceOverrides.normalizedName(for: trimmedQuery)

        var filtered: [MKMapItem] = []
        for item in appleHalalSearch.results {
            guard let coordinate = mapItemCoordinate(item) else { continue }

            // Enforce NYC + Long Island scope for Apple items
            guard RegionGate.allows(mapItem: item) else { continue }

            // Exclude known closed venues by name
            if let name = item.name, PlaceOverrides.isMarkedClosed(name: name) { continue }

            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let matchesExisting = supabaseLocations.contains { existing in
                existing.distance(from: location) < 80
            }

            if matchesExisting { continue }
            if matchesAppleQuery(item: item, normalizedQuery: normalizedQuery) {
                filtered.append(item)
            }
        }

        return filtered
    }

    private var filteredPlaces: [Place] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.places.filteredByCurrentGeoScope() }

        let matches = viewModel.searchResults.filteredByCurrentGeoScope()
        if matches.isEmpty, viewModel.isSearching {
            return viewModel.places.filteredByCurrentGeoScope()
        }
        return matches
    }

    private var favoritesDisplay: [FavoritePlaceSnapshot] {
        let base = favoritesStore.favorites
        switch favoritesSort {
        case .recentlySaved:
            return base.sorted { lhs, rhs in
                if lhs.savedAt != rhs.savedAt {
                    return lhs.savedAt > rhs.savedAt
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .alphabetical:
            return base.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .rating:
            return base.sorted { lhs, rhs in
                switch (lhs.rating, rhs.rating) {
                case let (l?, r?) where l != r:
                    return l > r
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    let lhsCount = lhs.ratingCount ?? 0
                    let rhsCount = rhs.ratingCount ?? 0
                    if lhsCount != rhsCount { return lhsCount > rhsCount }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        }
    }

    private var topRatedDisplay: [Place] {
        let base = viewModel.topRatedPlaces(limit: 50, minimumReviews: 10)
        let filtered = base.filter { matchesTopRatedRegion($0, region: topRatedRegion) }
        switch topRatedSort {
        case .rating:
            return filtered
        case .alphabetical:
            return filtered.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var mapPlaces: [Place] {
        switch bottomTab {
        case .favorites:
            return favoritesDisplay.map { resolvedPlace(for: $0) }
        case .topRated:
            return topRatedDisplay
        default:
            return filteredPlaces
        }
    }

    private var mapAppleItems: [MKMapItem] {
        switch bottomTab {
        case .favorites, .topRated:
            return []
        default:
            return appleOverlayItems
        }
    }

    private func matchesTopRatedRegion(_ place: Place, region: TopRatedRegion) -> Bool {
        let coord = place.coordinate
        let addr = address(of: place)

        let inManhattan = isWithin(coord, lat: 40.70...40.88, lon: (-74.03)...(-73.91)) || addr.contains("manhattan") || addr.contains("new york, ny")
        let inBrooklyn = isWithin(coord, lat: 40.55...40.73, lon: (-74.05)...(-73.83)) || addr.contains("brooklyn")
        let inQueens = isWithin(coord, lat: 40.54...40.81, lon: (-73.96)...(-73.70)) || addr.contains("queens")
        let inBronx = isWithin(coord, lat: 40.79...40.93, lon: (-73.93)...(-73.76)) || addr.contains("bronx")
        let inStaten = isWithin(coord, lat: 40.48...40.65, lon: (-74.27)...(-74.05)) || addr.contains("staten island")
        let inLongIslandBox = isWithin(coord, lat: 40.55...41.20, lon: (-73.95)...(-71.75))

        switch region {
        case .all:
            return true
        case .manhattan:
            return inManhattan && !(inBrooklyn || inQueens || inBronx || inStaten)
        case .brooklyn:
            return inBrooklyn && !(inManhattan || inQueens || inBronx || inStaten)
        case .queens:
            return inQueens && !(inManhattan || inBrooklyn || inBronx || inStaten)
        case .bronx:
            return inBronx && !(inManhattan || inBrooklyn || inQueens || inStaten)
        case .statenIsland:
            return inStaten && !(inManhattan || inBrooklyn || inQueens || inBronx)
        case .longIsland:
            if inLongIslandBox {
                return !(inBrooklyn || inQueens || inManhattan)
            }
            let keywords = ["long island", "nassau", "suffolk"]
            return keywords.contains { addr.contains($0) } && !addr.contains("long island city")
        }
    }

    private func isWithin(_ coordinate: CLLocationCoordinate2D, lat: ClosedRange<Double>, lon: ClosedRange<Double>) -> Bool {
        lat.contains(coordinate.latitude) && lon.contains(coordinate.longitude)
    }

    private func address(of place: Place) -> String {
        place.address?.lowercased() ?? ""
    }

    private func matchesAppleQuery(item: MKMapItem, normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }

        if let name = item.name {
            let normalizedName = PlaceOverrides.normalizedName(for: name)
            if normalizedName.contains(normalizedQuery) { return true }
        }

        if let shortAddress = item.halalShortAddress, !shortAddress.isEmpty {
            let normalizedAddress = PlaceOverrides.normalizedName(for: shortAddress)
            if normalizedAddress.contains(normalizedQuery) { return true }
        }

        return false
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
                selectedPlace: $selectedPlace,
                places: mapPlaces,
                appleMapItems: mapAppleItems,
                onRegionChange: { region in
                    // Enforce search/data fetch region to NYC + Long Island
                    let effective = RegionGate.enforcedRegion(for: region)
                    viewModel.regionDidChange(to: effective, filter: selectedFilter)
                    appleHalalSearch.search(in: effective)
                },
                onPlaceSelected: { place in
                    selectedPlace = place
                },
                onAppleItemSelected: { mapItem in
                    selectedApplePlace = ApplePlaceSelection(mapItem: mapItem)
                },
                onMapTap: {
                    guard bottomTab == .favorites else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        bottomTab = .places
                    }
                }
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                searchBar
                topSegmentedControl
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)

            if viewModel.isLoading && viewModel.places.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(16)
                    .background(.thinMaterial, in: Capsule())
            }

            if bottomTab == .topRated {
                TopRatedScreen(
                    places: topRatedDisplay,
                    sortOption: topRatedSort,
                    region: topRatedRegion,
                    topInset: currentTopSafeAreaInset(),
                    bottomInset: currentBottomSafeAreaInset(),
                    onSelect: { place in
                        focus(on: place)
                    },
                    onSortChange: { topRatedSort = $0 },
                    onRegionChange: { topRatedRegion = $0 }
                )
                .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topTrailing) {
            if bottomTab != .topRated {
                locateMeButton
                    .padding(.top, locateButtonTopPadding)
                    .padding(.trailing, 16)
            }
        }
        .overlay(alignment: .bottom) {
            bottomOverlay
        }
        .onAppear {
            let effective = RegionGate.enforcedRegion(for: mapRegion)
            viewModel.initialLoad(region: effective, filter: selectedFilter)
            locationManager.requestAuthorizationIfNeeded()
            appleHalalSearch.search(in: effective)
        }
        .onChange(of: selectedFilter) { oldValue, newValue in
            guard oldValue != newValue else { return }
            viewModel.filterChanged(to: newValue, region: mapRegion)
        }
        .onChange(of: selectedPlace) { oldValue, newValue in
            guard newValue == nil, oldValue != nil else { return }
            restoreSearchStateAfterDismiss()
        }
        .onChange(of: selectedApplePlace) { oldValue, newValue in
            // Auto-ingest disabled: selecting an Apple result should not persist or mark halal.
            _ = newValue?.mapItem
            if newValue == nil, oldValue != nil {
                restoreSearchStateAfterDismiss()
            }
        }
        .onReceive(locationManager.$lastKnownLocation.compactMap { $0 }) { location in
            guard !hasCenteredOnUser else { return }
            let span = MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            let region = MKCoordinateRegion(center: location.coordinate, span: span)
            // Keep the camera focused tightly on the user's actual location
            mapRegion = region
            // But fetch/search using the enforced NYC/LI scope
            let effective = RegionGate.enforcedRegion(for: region)
            viewModel.forceRefresh(region: effective, filter: selectedFilter)
            hasCenteredOnUser = true
            appleHalalSearch.search(in: effective)
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
                .environmentObject(favoritesStore)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedApplePlace) { selection in
            AppleMapItemSheet(selection: selection) {
                selectedApplePlace = nil
            }
            .presentationDetents([.medium, .large])
        }
        .overlay {
            if isSearchOverlayPresented {
                SearchOverlayView(
                    isPresented: $isSearchOverlayPresented,
                    query: $searchQuery,
                    isSearching: viewModel.isSearching,
                    supabaseResults: viewModel.searchResults.filteredByCurrentGeoScope(),
                    appleResults: appleOverlayItems,
                    subtitle: viewModel.subtitleMessage,
                    topSafeAreaInset: currentTopSafeAreaInset(),
                    onSelectPlace: { place in
                        focus(on: place)
                        isSearchOverlayPresented = false
                    },
                    onSelectApplePlace: { mapItem in
                        focus(on: mapItem)
                        isSearchOverlayPresented = false
                    },
                    onClear: {
                        searchQuery = ""
                    }
                )
                .ignoresSafeArea()
                .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .onChange(of: bottomTab) { tab in
            switch tab {
            case .favorites:
                selectedApplePlace = nil
                if let selected = selectedPlace,
                   !favoritesStore.contains(id: selected.id) {
                    selectedPlace = nil
                }
            case .topRated:
                selectedApplePlace = nil
                if let selected = selectedPlace,
                   !topRatedDisplay.contains(where: { $0.id == selected.id }) {
                    selectedPlace = nil
                }
            default:
                break
            }
        }
        .onChange(of: topRatedSort) { _, _ in
            if bottomTab == .topRated,
               let selected = selectedPlace,
               !topRatedDisplay.contains(where: { $0.id == selected.id }) {
                selectedPlace = nil
            }
        }
        .onChange(of: topRatedRegion) { _, _ in
            if bottomTab == .topRated,
               let selected = selectedPlace,
               !topRatedDisplay.contains(where: { $0.id == selected.id }) {
                selectedPlace = nil
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSearchOverlayPresented)
    }

    private var topSegmentedControl: some View {
        Picker("Category", selection: $selectedFilter) {
            ForEach(MapFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private enum BottomTab: CaseIterable, Identifiable {
        case places
        case topRated
        case newSpots
        case favorites

        var id: Self { self }

        var title: String {
            switch self {
            case .places: return "Places"
            case .topRated: return "Top Rated"
            case .newSpots: return "New Spots"
            case .favorites: return "Favorites"
            }
        }

        var systemImage: String {
            switch self {
            case .places: return "map"
            case .topRated: return "star.fill"
            case .newSpots: return "mappin.and.ellipse" // distinct; suggests new pins/places
            case .favorites: return "heart.fill"
            }
        }
    }

    private var bottomTabBar: some View {
        // Off‑white bar; keep original height but visually center content by nudging it down.
        let barHeight = max(52, currentScreenHeight() / 20)
        let safe = currentBottomSafeAreaInset()
        let contentOffset = CGFloat(min(12, max(4, safe * 0.22)))
        return VStack(spacing: 0) {
            Divider().background(Color.black.opacity(0.06))
            HStack(spacing: 0) {
                ForEach(BottomTab.allCases) { tab in
                    Button {
                        bottomTab = tab
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 20, weight: .semibold))
                            Text(tab.title)
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: contentOffset) // nudge content lower without changing bar height
                        .foregroundStyle(bottomTab == tab ? Color.accentColor : Color.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: barHeight)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var bottomOverlay: some View {
        let showFavorites = bottomTab == .favorites
        return VStack(spacing: showFavorites ? 16 : 0) {
            if showFavorites {
                FavoritesPanel(
                    favorites: favoritesDisplay,
                    sortOption: favoritesSort,
                    onSelect: { snapshot in
                        focus(on: resolvedPlace(for: snapshot))
                    },
                    onSortChange: { favoritesSort = $0 }
                )
                .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, 16)
            }
            bottomTabBar
        }
        .padding(.bottom, bottomOverlayPadding)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut(duration: 0.2), value: bottomTab)
    }

    private var bottomOverlayPadding: CGFloat {
        0 // flush with bottom; bar manages its own safe area
    }

    // No chip-style labels anymore; the bar uses icons + labels above.

    private var searchBar: some View {
        Button {
            isSearchOverlayPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(searchQuery.isEmpty ? "Search Halal Restaurants" : searchQuery)
                    .font(.body)
                    .foregroundStyle(searchQuery.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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
                    // Keep the camera tight on the user's location
                    mapRegion = targetRegion
                    // Fetch/search within enforced NYC/LI scope
                    let effective = RegionGate.enforcedRegion(for: targetRegion)
                    viewModel.forceRefresh(region: effective, filter: selectedFilter)
                    appleHalalSearch.search(in: effective)
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

    private var locateButtonTopPadding: CGFloat {
        let safeTop = currentTopSafeAreaInset()
        let safeBottom = currentBottomSafeAreaInset()
        let screenHeight = currentScreenHeight()
        let desiredGap: Double = 200
        let keyboardOffset = keyboardHeight > 0 ? Double(keyboardHeight) : 0
        let calculated = screenHeight - (Double(safeBottom) + desiredGap + keyboardOffset)
        return CGFloat(max(Double(safeTop) + 24, calculated))
    }

}

private extension ContentView {
    private func currentBottomSafeAreaInset() -> CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return 0
        }
        return window.safeAreaInsets.bottom
    }

    private func currentTopSafeAreaInset() -> CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return 0
        }
        return window.safeAreaInsets.top
    }

    func restoreSearchStateAfterDismiss() {
        previousMapRegion = nil
        if !searchQuery.isEmpty {
            searchQuery = ""
        }
    }

    func focus(on place: Place) {
        if previousMapRegion == nil {
            previousMapRegion = mapRegion
        }
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let targetRegion = adjustedRegion(centeredOn: place.coordinate, span: span)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            mapRegion = targetRegion
        }
        selectedPlace = place
        isSearchOverlayPresented = false
    }

    func focus(on mapItem: MKMapItem) {
        let coordinate = mapItem.halalCoordinate
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return }
        if previousMapRegion == nil {
            previousMapRegion = mapRegion
        }
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let targetRegion = adjustedRegion(centeredOn: coordinate, span: span)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            mapRegion = targetRegion
        }
        selectedPlace = nil
        selectedApplePlace = ApplePlaceSelection(mapItem: mapItem)
        isSearchOverlayPresented = false
    }

    func resolvedPlace(for snapshot: FavoritePlaceSnapshot) -> Place {
        if let existing = viewModel.places.first(where: { $0.id == snapshot.id }) {
            return existing
        }
        if let searchMatch = viewModel.searchResults.first(where: { $0.id == snapshot.id }) {
            return searchMatch
        }
        return snapshot.toPlace()
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
        return 0.15
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

private struct SearchOverlayView: View {
    @Binding var isPresented: Bool
    @Binding var query: String
    let isSearching: Bool
    let supabaseResults: [Place]
    let appleResults: [MKMapItem]
    let subtitle: String?
    let topSafeAreaInset: CGFloat
    let onSelectPlace: (Place) -> Void
    let onSelectApplePlace: (MKMapItem) -> Void
    let onClear: () -> Void

    @FocusState private var searchFieldIsFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: topSafeAreaInset + 12)
            header
            Divider()
            content
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
        .onAppear {
            searchFieldIsFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                query = ""
                onClear()
                isPresented = false
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Halal Restaurants", text: $query)
                    .focused($searchFieldIsFocused)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        query = ""
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("Search halal restaurants near you")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let message = subtitle, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !supabaseResults.isEmpty {
                        Text("Halal Food matches")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(supabaseResults, id: \.id) { place in
                            Button {
                                onSelectPlace(place)
                            } label: {
                                PlaceRow(place: place)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !appleResults.isEmpty {
                        if !supabaseResults.isEmpty {
                            Divider()
                        }
                        Text("Apple Maps results")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(appleResults.enumerated()), id: \.offset) { _, item in
                            Button {
                                onSelectApplePlace(item)
                            } label: {
                                ApplePlaceRow(mapItem: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if supabaseResults.isEmpty && appleResults.isEmpty {
                        if isSearching {
                            HStack {
                                ProgressView()
                                Text("Searching…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No matches for \"\(trimmedQuery)\".")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct PlaceRow: View {
    let place: Place

    private let detailColor = Color.primary.opacity(0.75)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            let iconName = place.category == .restaurant ? "fork.knife.circle.fill" : "mappin.circle.fill"
            let iconColor: Color = {
                switch place.halalStatus {
                case .only:
                    return .green
                case .yes:
                    return .orange
                case .unknown:
                    return .gray
                case .no:
                    return .red
                }
            }()
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
                        .foregroundStyle(detailColor)
                }
                Text(place.halalStatus.label.localizedCapitalized)
                    .font(.caption)
                    .foregroundStyle(detailColor)
                if let rating = place.rating {
                    let count = place.ratingCount ?? 0
                    let ratingLabel = count == 1 ? "rating" : "ratings"
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", rating))
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("(\(count) \(ratingLabel))")
                        if let source = place.source, !source.isEmpty {
                            Text("- \(readableSource(source))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(detailColor)
                } else if let source = place.source, !source.isEmpty {
                    Text(readableSource(source))
                        .font(.caption2)
                        .foregroundStyle(detailColor)
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

private func readableSource(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "_", with: " ")
        .split(separator: " ")
        .map { component -> String in
            let lower = component.lowercased()
            switch lower {
            case "yelp": return "Yelp"
            case "apple": return "Apple"
            case "manual": return "Manual"
            default: return lower.capitalized
            }
        }
        .joined(separator: " ")
}

private struct ApplePlaceRow: View {
    let mapItem: MKMapItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin.circle")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
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

private struct TopRatedScreen: View {
    let places: [Place]
    let sortOption: TopRatedSortOption
    let region: TopRatedRegion
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onSelect: (Place) -> Void
    let onSortChange: (TopRatedSortOption) -> Void
    let onRegionChange: (TopRatedRegion) -> Void

    private let detailColor = Color.primary.opacity(0.65)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Rated")
                        .font(.title3.weight(.semibold))
                    if !places.isEmpty {
                        Text("\(places.count) places")
                            .font(.caption)
                            .foregroundStyle(detailColor)
                    }
                }

                Spacer()

                Menu {
                    ForEach(TopRatedRegion.allCases) { option in
                        Button(option.title) {
                            onRegionChange(option)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("By Location")
                        if region != .all {
                            Text(region.title)
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(TopRatedSortOption.allCases) { option in
                    sortButton(for: option)
                }
                Spacer(minLength: 0)
            }

            if places.isEmpty {
                Text("No matches yet. Try a different location.")
                    .font(.footnote)
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(places) { place in
                            Button {
                                onSelect(place)
                            } label: {
                                TopRatedRow(place: place)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(.top, topInset + 24)
        .padding(.horizontal, 20)
        .padding(.bottom, bottomInset + 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }

    private func sortButton(for option: TopRatedSortOption) -> some View {
        let isSelected = option == sortOption
        return Button {
            onSortChange(option)
        } label: {
            Text(option.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : detailColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct TopRatedRow: View {
    let place: Place

    private let detailColor = Color.primary.opacity(0.75)

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "star.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(place.name)
                    .font(.headline)

                if let address = place.address, !address.isEmpty {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(detailColor)
                }

                Text(place.halalStatus.label.localizedCapitalized)
                    .font(.caption)
                    .foregroundStyle(detailColor)
            }

            Spacer(minLength: 8)

            if let rating = place.rating {
                ratingBadge(rating: rating, count: place.ratingCount)
            }

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func ratingBadge(rating: Double, count: Int?) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(String(format: "%.1f", rating))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(countText(count))
                .font(.caption2)
                .foregroundStyle(detailColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func countText(_ count: Int?) -> String {
        guard let count else { return "No reviews" }
        return count == 1 ? "1 review" : "\(count) reviews"
    }
}


private struct ZoomableAsyncImage<Placeholder: View, Failure: View>: View {
    let url: URL
    let resetID: UUID
    let placeholder: Placeholder
    let failure: Failure

    init(url: URL, resetID: UUID, @ViewBuilder placeholder: () -> Placeholder, @ViewBuilder failure: () -> Failure) {
        self.url = url
        self.resetID = resetID
        self.placeholder = placeholder()
        self.failure = failure()
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                placeholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .success(let image):
                ZoomableScrollView(resetID: resetID) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }
            case .failure:
                failure
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            @unknown default:
                failure
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let resetID: UUID
    let content: Content

    init(resetID: UUID, @ViewBuilder content: () -> Content) {
        self.resetID = resetID
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content, resetID: resetID)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let hostedView = context.coordinator.hostingController.view!
        hostedView.backgroundColor = .clear
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.frame = scrollView.bounds
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(hostedView)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
        if context.coordinator.lastResetID != resetID {
            scrollView.setZoomScale(1, animated: false)
            scrollView.contentOffset = .zero
            context.coordinator.lastResetID = resetID
        }
        context.coordinator.centerContent(scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>
        var lastResetID: UUID

        init(content: Content, resetID: UUID) {
            hostingController = UIHostingController(rootView: content)
            hostingController.view.backgroundColor = .clear
            lastResetID = resetID
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(scrollView)
        }

        func centerContent(_ scrollView: UIScrollView) {
            guard let view = hostingController.view else { return }
            let boundsSize = scrollView.bounds.size
            let contentSize = scrollView.contentSize

            let horizontalInset = max(0, (boundsSize.width - contentSize.width) / 2)
            let verticalInset = max(0, (boundsSize.height - contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
        }
    }
}

private struct FavoritesPanel: View {
    let favorites: [FavoritePlaceSnapshot]
    let sortOption: FavoritesSortOption
    let onSelect: (FavoritePlaceSnapshot) -> Void
    let onSortChange: (FavoritesSortOption) -> Void

    private let detailColor = Color.primary.opacity(0.65)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Favorites")
                    .font(.headline)
                if !favorites.isEmpty {
                    Text("\(favorites.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(detailColor)
                }
                Spacer()
            }

            if !favorites.isEmpty {
                HStack(spacing: 8) {
                    ForEach(FavoritesSortOption.allCases) { option in
                        sortButton(for: option)
                    }
                }
            }

            if favorites.isEmpty {
                Text("Tap the heart on a place to keep it handy here.")
                    .font(.footnote)
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(favorites) { snapshot in
                            Button {
                                onSelect(snapshot)
                            } label: {
                                FavoriteRow(snapshot: snapshot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
    }

    private func sortButton(for option: FavoritesSortOption) -> some View {
        let isSelected = option == sortOption
        return Button {
            onSortChange(option)
        } label: {
            Text(option.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : detailColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct FavoriteRow: View {
    let snapshot: FavoritePlaceSnapshot

    private let detailColor = Color.primary.opacity(0.75)

    private var iconName: String {
        snapshot.category == .restaurant ? "fork.knife.circle.fill" : "mappin.circle.fill"
    }

    private var iconColor: Color {
        switch snapshot.halalStatus {
        case .only:
            return .green
        case .yes:
            return .orange
        case .unknown:
            return .gray
        case .no:
            return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.name)
                    .font(.headline)

                if let address = snapshot.address, !address.isEmpty {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(detailColor)
                }

                Text(snapshot.halalStatus.label.localizedCapitalized)
                    .font(.caption)
                    .foregroundStyle(detailColor)

                if let rating = snapshot.rating {
                    let count = snapshot.ratingCount ?? 0
                    let ratingLabel = count == 1 ? "rating" : "ratings"
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", rating))
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("(\(count) \(ratingLabel))")
                        if let source = snapshot.source, !source.isEmpty {
                            Text("- \(readableSource(source))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(detailColor)
                } else if let source = snapshot.source, !source.isEmpty {
                    Text(readableSource(source))
                        .font(.caption2)
                        .foregroundStyle(detailColor)
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

struct PlaceDetailView: View {
    let place: Place

    @StateObject private var viewModel = PlaceDetailViewModel()
    @State private var expandedPhotoSelection: PhotoSelection?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var favoritesStore: FavoritesStore

    private var isFavorite: Bool {
        favoritesStore.isFavorite(place)
    }

    var body: some View {
        GeometryReader { proxy in
            let loadedDetails = appleLoadedDetails

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        if !viewModel.photos.isEmpty {
                            PhotoCarouselView(photos: viewModel.photos) { index, _ in
                                expandedPhotoSelection = PhotoSelection(index: index)
                            }
                        }
                        halalSection
                        Divider().opacity(0.4)
                        appleStatusSection
                    }
                    .padding(24)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .opacity(loadedDetails == nil ? 1 : 0)
                .allowsHitTesting(loadedDetails == nil)
                .overlay(alignment: .top) {
                    if let details = loadedDetails {
                        appleLoadedSection(details, availableHeight: proxy.size.height)
                    }
                }
            }
        }
        .fullScreenCover(item: $expandedPhotoSelection) { selection in
            FullscreenPhotoView(
                photos: viewModel.photos,
                initialIndex: selection.index
            ) {
                expandedPhotoSelection = nil
            }
        }
        .task(id: place.id) {
            await viewModel.load(place: place)
            await viewModel.loadPhotos(for: place)
            refreshFavoriteSnapshot()
        }
        .onReceive(viewModel.$loadingState) { _ in
            refreshFavoriteSnapshot()
        }
        .onReceive(viewModel.$photos) { photos in
            if let selection = expandedPhotoSelection,
               !photos.indices.contains(selection.index) {
                expandedPhotoSelection = nil
            }
        }
        .onChange(of: expandedPhotoSelection) { newValue in
            if let selection = newValue,
               !viewModel.photos.indices.contains(selection.index) {
                expandedPhotoSelection = nil
            }
        }
    }

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.red : Color.white)
                .padding(6)
                .background(Color(.systemGray), in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 4.5, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private func toggleFavorite() {
        let appleID = appleLoadedDetails?.applePlaceID ?? place.applePlaceID
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            favoritesStore.toggleFavorite(
                for: place,
                name: displayName,
                address: displayAddress,
                rating: place.rating,
                ratingCount: place.ratingCount,
                source: place.source,
                applePlaceID: appleID
            )
        }
    }

    private func refreshFavoriteSnapshot() {
        guard favoritesStore.contains(id: place.id) else { return }
        let appleID = appleLoadedDetails?.applePlaceID ?? place.applePlaceID
        favoritesStore.updateFavoriteIfNeeded(
            for: place,
            name: displayName,
            address: displayAddress,
            rating: place.rating,
            ratingCount: place.ratingCount,
            source: place.source,
            applePlaceID: appleID
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                Spacer()
                if !hasAppleDetails {
                    favoriteButton
                }
            }

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

    @ViewBuilder
    private var halalSection: some View {
        if place.source?.lowercased() == "apple" {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(place.halalStatus.label, systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Our halal classification comes from our own Supabase dataset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var appleStatusSection: some View {
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
        case .loaded:
            EmptyView()
        }
    }

    @ViewBuilder
    private func appleDetailsSection(_ details: ApplePlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
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

                Spacer()

                favoriteButton
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

    @ViewBuilder
    private func appleLoadedSection(_ details: ApplePlaceDetails, availableHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            if !viewModel.photos.isEmpty {
                PhotoCarouselView(photos: viewModel.photos) { index, _ in
                    expandedPhotoSelection = PhotoSelection(index: index)
                }
            }
            if #available(iOS 18.0, *) {
                applePlaceCard(details)
            } else {
                appleDetailsSection(details)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(minHeight: availableHeight, alignment: .top)
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
        .shadow(color: .black.opacity(0.08), radius: 11, y: 6)
        .overlay(alignment: .topTrailing) {
            favoriteButton
                .padding(.trailing, 15.5)
                .padding(.top, 58)
        }
    }
}

extension PlaceDetailView {
    private var appleLoadedDetails: ApplePlaceDetails? {
        if case let .loaded(details) = viewModel.loadingState {
            return details
        }
        return nil
    }
}

private struct PhotoSelection: Identifiable, Equatable {
    let id = UUID()
    let index: Int
}

private struct FullscreenPhotoView: View {
    let photos: [PlacePhoto]
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var dragOffset: CGFloat = 0

    init(photos: [PlacePhoto], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.photos = photos
        self.onDismiss = onDismiss
        let clamped = photos.indices.contains(initialIndex) ? initialIndex : 0
        _currentIndex = State(initialValue: clamped)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            Group {
                if photos.isEmpty {
                    emptyPlaceholder
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { pair in
                            let index = pair.offset
                            let photo = pair.element
                            Group {
                                if let url = URL(string: photo.imageUrl) {
                                    ZoomableAsyncImage(url: url, resetID: photo.id) {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .tint(.white)
                                    } failure: {
                                        tilePlaceholder
                                    }
                                } else {
                                    tilePlaceholder
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }
            }
            .offset(y: dragOffset)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
            }
            .padding()
            .accessibilityLabel("Close photo")
            .offset(y: dragOffset)
        }
        .overlay(alignment: .bottomTrailing) {
            if !photos.isEmpty {
                Text("Photos: Yelp")
                    .font(.caption2)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
                    .offset(y: dragOffset)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Expanded restaurant photo")
        .accessibilityAddTraits(.isModal)
        .gesture(dismissDragGesture)
        .onChange(of: photos.count) { _ in
            clampIndexIfNeeded()
        }
        .onAppear {
            clampIndexIfNeeded()
        }
    }

    private var backgroundOpacity: Double {
        let progress = min(max(dragOffset / 400, 0), 1)
        return Double(1 - (progress * 0.6))
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = max(value.translation.height, 0)
            }
            .onEnded { value in
                let translation = value.translation.height
                let predicted = value.predictedEndTranslation.height
                let threshold: CGFloat = 160
                if max(translation, predicted) > threshold {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func clampIndexIfNeeded() {
        if let last = photos.indices.last {
            currentIndex = min(currentIndex, last)
        } else {
            currentIndex = 0
            onDismiss()
        }
    }

    private var tilePlaceholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 64))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.7))
            Text("Photo unavailable")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}


private struct PhotoCarouselView: View {
    let photos: [PlacePhoto]
    let onPhotoSelected: (Int, PlacePhoto) -> Void

    @State private var selectedIndex = 0

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { pair in
                let index = pair.offset
                let photo = pair.element
                ZStack {
                    if let url = URL(string: photo.imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ZStack { Color.secondary.opacity(0.1); ProgressView() }
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Color.secondary.opacity(0.1)
                            @unknown default:
                                Color.secondary.opacity(0.1)
                            }
                        }
                    } else {
                        Color.secondary.opacity(0.1)
                    }
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .tag(index)
                .onTapGesture {
                    onPhotoSelected(index, photo)
                }
                .accessibilityAddTraits(.isButton)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: photos) { newValue in
            if let lastIndex = newValue.indices.last {
                selectedIndex = min(selectedIndex, lastIndex)
            } else {
                selectedIndex = 0
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("Photos: Yelp")
                .font(.caption2)
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
        }
        .onAppear {
            if let lastIndex = photos.indices.last {
                selectedIndex = min(selectedIndex, lastIndex)
            } else {
                selectedIndex = 0
            }
        }
    }
}

private struct AppleMapItemSheet: View {
    let selection: ApplePlaceSelection
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                MapItemDetailCardView(mapItem: selection.mapItem, showsInlineMap: true, onFinished: onDismiss)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                AppleFallbackDetailView(details: ApplePlaceDetails(mapItem: selection.mapItem))
            }
        }
    }
}

private struct ApplePlaceSelection: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem
}

extension ApplePlaceSelection: Equatable {
    static func == (lhs: ApplePlaceSelection, rhs: ApplePlaceSelection) -> Bool {
        lhs.id == rhs.id
    }
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
            // Enforce NYC + Long Island region if limiting is enabled
            request.region = RegionGate.enforcedRegion(for: region)
            request.resultTypes = [.pointOfInterest]
            if #available(iOS 13.0, *) {
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant])
            }

            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                await MainActor.run {
                    // Post-filter just in case MapKit returns items outside the requested region
                    self.results = response.mapItems.filter { item in
                        guard RegionGate.allows(mapItem: item) else { return false }
                        if let name = item.name, PlaceOverrides.isMarkedClosed(name: name) { return false }
                        return true
                    }
                    self.lastRegion = RegionGate.enforcedRegion(for: region)
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
    @Published var photos: [PlacePhoto] = []

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

    func loadPhotos(for place: Place) async {
        do {
            var comps = URLComponents(url: Env.url, resolvingAgainstBaseURL: false)!
            var p = comps.path
            if !p.hasSuffix("/") { p.append("/") }
            p.append("rest/v1/place_photo")
            comps.path = p
            comps.queryItems = [
                URLQueryItem(name: "place_id", value: "eq.\(place.id.uuidString)"),
                URLQueryItem(name: "src", value: "eq.yelp"),
                URLQueryItem(name: "order", value: "priority.asc"),
                URLQueryItem(name: "limit", value: "12")
            ]
            guard let url = comps.url else { return }
            var req = URLRequest(url: url)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let key = Env.anonKey
            req.setValue(key, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("public", forHTTPHeaderField: "Accept-Profile")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var rows = try decoder.decode([PlacePhoto].self, from: data)
            if rows.isEmpty {
                if let yelpPlaceID = try await findNearbyYelpPlaceID(around: place.coordinate, hintName: place.name) {
                    rows = try await fetchPhotos(for: yelpPlaceID)
                }
            }
            self.photos = rows
        } catch {
            // ignore
        }
    }

    private func fetchPhotos(for placeID: UUID) async throws -> [PlacePhoto] {
        var comps = URLComponents(url: Env.url, resolvingAgainstBaseURL: false)!
        var p = comps.path
        if !p.hasSuffix("/") { p.append("/") }
        p.append("rest/v1/place_photo")
        comps.path = p
        comps.queryItems = [
            URLQueryItem(name: "place_id", value: "eq.\(placeID.uuidString)"),
            URLQueryItem(name: "src", value: "eq.yelp"),
            URLQueryItem(name: "order", value: "priority.asc"),
            URLQueryItem(name: "limit", value: "12")
        ]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = Env.anonKey
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("public", forHTTPHeaderField: "Accept-Profile")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([PlacePhoto].self, from: data)
    }

    private struct YelpPlaceRow: Decodable { let id: UUID; let lat: Double; let lon: Double; let name: String }

    private func findNearbyYelpPlaceID(around coordinate: CLLocationCoordinate2D, hintName: String) async throws -> UUID? {
        var comps = URLComponents(url: Env.url, resolvingAgainstBaseURL: false)!
        var p = comps.path
        if !p.hasSuffix("/") { p.append("/") }
        p.append("rest/v1/place")
        comps.path = p
        let delta = 0.003 // ~300m
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,lat,lon,name,source"),
            URLQueryItem(name: "source", value: "eq.yelp"),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "lat", value: String(format: "gt.%.6f", coordinate.latitude - delta)),
            URLQueryItem(name: "lat", value: String(format: "lt.%.6f", coordinate.latitude + delta)),
            URLQueryItem(name: "lon", value: String(format: "gt.%.6f", coordinate.longitude - delta)),
            URLQueryItem(name: "lon", value: String(format: "lt.%.6f", coordinate.longitude + delta)),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = Env.anonKey
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("public", forHTTPHeaderField: "Accept-Profile")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let decoder = JSONDecoder()
        let rows = try decoder.decode([YelpPlaceRow].self, from: data)
        guard !rows.isEmpty else { return nil }
        // Pick nearest by simple euclidean distance in degrees
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let best = rows.min(by: { lhs, rhs in
            let dl = CLLocation(latitude: lhs.lat, longitude: lhs.lon).distance(from: target)
            let dr = CLLocation(latitude: rhs.lat, longitude: rhs.lon).distance(from: target)
            return dl < dr
        })
        return best?.id
    }
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
        guard !places.isEmpty else { return "Pan the map to explore more halal spots." }
        return nil
    }

    var errorDescription: String {
        guard let message = errorMessage, !presentingError else { return "" }
        return message
    }

    private var fetchTask: Task<Void, Never>?
    private var manualSearchTask: Task<Void, Never>?
    private var globalDatasetTask: Task<Void, Never>?
    private var remoteSearchTask: Task<Void, Never>?
    private var appleFallbackTask: Task<Void, Never>?
    private var lastRequestedRegion: MKCoordinateRegion?
    private var cache = PlaceCache()
    private var allPlaces: [Place] = []
    private var globalDataset: [Place] = []
    private var lastSearchQuery: String?
    private var currentFilter: MapFilter = .all
    private var appleIngestTasks: [String: Task<Void, Never>] = [:]
    private var ingestedApplePlaceIDs: Set<String> = []

    func initialLoad(region: MKCoordinateRegion, filter: MapFilter) {
        currentFilter = filter
        guard allPlaces.isEmpty else {
            apply(filter: filter)
            return
        }
        ensureGlobalDataset()
        fetch(region: RegionGate.enforcedRegion(for: region), filter: filter, eager: true)
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
        fetch(region: RegionGate.enforcedRegion(for: region), filter: filter, eager: false)
    }

    func forceRefresh(region: MKCoordinateRegion, filter: MapFilter) {
        lastRequestedRegion = nil
        fetch(region: RegionGate.enforcedRegion(for: region), filter: filter, eager: true)
    }

    func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        remoteSearchTask?.cancel()
        remoteSearchTask = nil
        manualSearchTask?.cancel()
        manualSearchTask = nil
        appleFallbackTask?.cancel()
        appleFallbackTask = nil

        lastSearchQuery = trimmed

        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            updateSearchActivityIndicator()
            return
        }

        ensureGlobalDataset()

        let seededMatches = combinedMatches(for: trimmed)
        searchResults = PlaceOverrides.sorted(seededMatches)
        isSearching = true

        remoteSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.remoteSearchTask = nil
                self.updateSearchActivityIndicator()
                self.triggerAppleFallbackIfNecessary(for: trimmed)
            }

            do {
                let dtos = try await PlaceAPI.searchPlaces(matching: trimmed, limit: 80)
                guard !Task.isCancelled else { return }
                let remotePlaces = dtos.compactMap(Place.init(dto:)).filteredByCurrentGeoScope()
                guard !remotePlaces.isEmpty else { return }

                let referenceCoordinate = remotePlaces.first?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                let region = MKCoordinateRegion(center: referenceCoordinate, span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0))
                let cleaned = PlaceOverrides.apply(overridesTo: remotePlaces, in: region).filteredByCurrentGeoScope()
                self.mergeIntoGlobalDataset(cleaned)
                let merged = self.deduplicate(self.searchResults + cleaned)
                self.searchResults = PlaceOverrides.sorted(merged)
            } catch is CancellationError {
                // Ignore cancellations
            } catch {
#if DEBUG
                print("[MapScreenViewModel] Remote search failed for query \(trimmed):", error)
#endif
            }
        }

        manualSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.manualSearchTask = nil
                self.updateSearchActivityIndicator()
            }
            let exclusion = self.searchResults + self.allPlaces + self.globalDataset
            let additionalManual = await ManualPlaceResolver.shared.searchMatches(for: trimmed, excluding: exclusion).filteredByCurrentGeoScope()
            guard !Task.isCancelled else { return }
            guard !additionalManual.isEmpty else { return }
            self.mergeIntoGlobalDataset(additionalManual)
            let merged = self.deduplicate(self.searchResults + additionalManual)
            self.searchResults = PlaceOverrides.sorted(merged.filteredByCurrentGeoScope())
        }
    }

    private func fetch(region: MKCoordinateRegion, filter: MapFilter, eager: Bool) {
        let cacheHit = cache.value(for: region)
        let cachedOverride = cacheHit.map { PlaceOverrides.apply(overridesTo: $0.places, in: region) }

        if let cachedPlaces = cachedOverride {
            // Show cached results immediately for snappy UI, but do not return early here.
            // We still evaluate whether to fetch fresh data based on region changes below.
            allPlaces = cachedPlaces
            apply(filter: filter)
            // Intentionally not returning on fresh cache; fetching decision happens below.
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
                let dtos = try await Task.detached(priority: .userInitiated) {
                    try await PlaceAPI.getPlaces(bbox: region.bbox)
                }.value
                // Convert and enforce NYC + Long Island scope
                let results = dtos.compactMap(Place.init(dto:)).filteredByCurrentGeoScope()
                let overridden = PlaceOverrides.apply(overridesTo: results, in: region)
                let cleaned = overridden.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                // Only surface verified halal places by default
                let halalOnly = cleaned.filter { $0.halalStatus == .yes || $0.halalStatus == .only }

                // Bring in manual outliers (e.g., venues not tagged halal in OSM/Apple)
                // so they always appear on the map within the current region.
                let manual = await ManualPlaceResolver.shared.manualPlaces(in: RegionGate.enforcedRegion(for: region), excluding: halalOnly).filteredByCurrentGeoScope()

                try Task.checkCancellation()
                let combined = self.deduplicate(halalOnly + manual).filteredByCurrentGeoScope()
                self.allPlaces = PlaceOverrides.sorted(combined)
                self.mergeIntoGlobalDataset(combined)
                self.apply(filter: self.currentFilter)
                self.isLoading = false
                self.cache.store(combined, region: region)
            } catch is CancellationError {
                // Swallow cancellation; any inflight request will manage loading state.
            } catch {
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    return
                }
                self.errorMessage = Self.message(for: error)
                self.presentingError = true
                if self.places.isEmpty, let cachedPlaces = cachedOverride {
                    self.allPlaces = cachedPlaces.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    self.apply(filter: self.currentFilter)
                }
                self.isLoading = false
            }
        }
    }

    private func apply(filter: MapFilter) {
        let filtered: [Place]
        switch filter {
        case .all:
            filtered = allPlaces
        case .fullyHalal:
            filtered = allPlaces.filter { $0.halalStatus == .only }
        case .partialHalal:
            filtered = allPlaces.filter { $0.halalStatus == .yes }
        }
        places = filtered
    }

    func topRatedPlaces(limit: Int = 50, minimumReviews: Int = 10) -> [Place] {
        let candidates = allPlaces.filter { place in
            guard let rating = place.rating, rating > 0 else { return false }
            return (place.ratingCount ?? 0) >= minimumReviews
        }

        let sorted = candidates.sorted { lhs, rhs in
            switch (lhs.rating, rhs.rating) {
            case let (l?, r?) where l != r:
                return l > r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                let lhsCount = lhs.ratingCount ?? 0
                let rhsCount = rhs.ratingCount ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

        if sorted.count <= limit { return sorted }
        return Array(sorted.prefix(limit))
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
        manualSearchTask?.cancel()
        globalDatasetTask?.cancel()
        remoteSearchTask?.cancel()
        appleFallbackTask?.cancel()
        appleIngestTasks.values.forEach { $0.cancel() }
    }
}

private extension MapScreenViewModel {
    static let appleFallbackRegion: MKCoordinateRegion = {
        let center = CLLocationCoordinate2D(latitude: 40.789142, longitude: -73.13496)
        let span = MKCoordinateSpan(latitudeDelta: 3.5, longitudeDelta: 3.8)
        return MKCoordinateRegion(center: center, span: span)
    }()

    func ingestApplePlaceIfNeeded(_ mapItem: MKMapItem) {
        // Guard against obvious non‑halal chains being marked as halal.
        guard Self.shouldIngestApplePlace(mapItem) else { return }
        // Persist Apple-provided halal venues as fully halal by default.
        guard let payload = ApplePlaceUpsertPayload(mapItem: mapItem, halalStatus: .only, confidence: 0.3) else { return }
        let identifier = payload.applePlaceID
        guard !ingestedApplePlaceIDs.contains(identifier) else { return }
        ingestedApplePlaceIDs.insert(identifier)

        if let existing = appleIngestTasks[identifier] {
            existing.cancel()
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.appleIngestTasks.removeValue(forKey: identifier)
            }

            do {
                let dto = try await PlaceAPI.upsertApplePlace(payload)
                guard !Task.isCancelled else { return }
                guard let place = Place(dto: dto) else { return }
                // Only surface places that came back as halal after the upsert.
                if place.halalStatus == .yes || place.halalStatus == .only {
                    self.mergeIntoGlobalDataset([place])
                    self.insertOrUpdatePlace(place)
                    self.refreshSearchResultsIfNeeded(with: place)
                }
            } catch is CancellationError {
                self.ingestedApplePlaceIDs.remove(identifier)
            } catch {
#if DEBUG
                print("[MapScreenViewModel] Failed to upsert Apple-sourced place:", error)
#endif
                self.ingestedApplePlaceIDs.remove(identifier)
            }
        }

        appleIngestTasks[identifier] = task
    }

    func triggerAppleFallbackIfNecessary(for query: String) {
        guard appleFallbackTask == nil else { return }
        guard searchResults.isEmpty else { return }
        guard !query.isEmpty else { return }

        appleFallbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.appleFallbackTask = nil
                self.updateSearchActivityIndicator()
            }

            self.isSearching = true

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.pointOfInterest]
            request.region = Self.appleFallbackRegion

            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                let items = response.mapItems
                guard !items.isEmpty else { return }

                var fallbackPlaces: [Place] = []
                for item in items {
                    if let place = makePlace(from: item, halalStatus: .only, confidence: 0.4) {
                        fallbackPlaces.append(place)
                    }
                    self.ingestApplePlaceIfNeeded(item)
                }

                guard !fallbackPlaces.isEmpty else { return }
                self.mergeIntoGlobalDataset(fallbackPlaces)
                for place in fallbackPlaces {
                    self.insertOrUpdatePlace(place)
                }
                let merged = self.deduplicate(self.searchResults + fallbackPlaces)
                self.searchResults = PlaceOverrides.sorted(merged)
            } catch is CancellationError {
                // Ignore cancellation
            } catch {
#if DEBUG
                print("[MapScreenViewModel] Apple fallback search failed for query \(query):", error)
#endif
            }
        }
    }

    private static let nonHalalChainBlocklist: Set<String> = {
        let names = [
            "Subway", "Taco Bell", "McDonald's", "Burger King", "Wendy's",
            "KFC", "Chipotle", "Domino's", "Pizza Hut", "Papa John's",
            "Five Guys", "White Castle", "Panera Bread", "Starbucks",
            "Dunkin'", "Chick-fil-A", "Popeyes", "Arby's", "Jack in the Box",
            "Sonic Drive-In", "Little Caesars", "Carl's Jr", "Hardee's"
        ]
        return Set(names.map { PlaceOverrides.normalizedName(for: $0) })
    }()

    private static func shouldIngestApplePlace(_ mapItem: MKMapItem) -> Bool {
        let name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = PlaceOverrides.normalizedName(for: name)
        if normalized.isEmpty { return false }
        if nonHalalChainBlocklist.contains(normalized) { return false }
        return true
    }

    func combinedMatches(for query: String) -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let local = matches(in: allPlaces, query: trimmed)
        let global = matches(in: globalDataset, query: trimmed)
        return deduplicate(local + global)
    }

    func matches(in source: [Place], query: String) -> [Place] {
        let normalizedQuery = PlaceOverrides.normalizedName(for: query)
        guard !normalizedQuery.isEmpty else { return [] }

        return source.filter { place in
            let normalizedName = PlaceOverrides.normalizedName(for: place.name)
            if normalizedName.contains(normalizedQuery) { return true }

            if let address = place.address {
                let normalizedAddress = PlaceOverrides.normalizedName(for: address)
                if normalizedAddress.contains(normalizedQuery) { return true }
            }

            return false
        }
    }

    func ensureGlobalDataset() {
        guard globalDataset.isEmpty, globalDatasetTask == nil else { return }
        globalDatasetTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let dtos = try await Task.detached(priority: .utility) {
                    try await PlaceAPI.fetchAllPlaces(limit: 3500)
                }.value
                let places = dtos
                    .compactMap(Place.init(dto:))
                    .filteredByCurrentGeoScope()
                    .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                try Task.checkCancellation()
                self.mergeIntoGlobalDataset(places)
                if let query = self.lastSearchQuery, !query.isEmpty {
                    let seeded = self.combinedMatches(for: query).filteredByCurrentGeoScope()
                    self.searchResults = PlaceOverrides.sorted(seeded)
                }
            } catch is CancellationError {
#if DEBUG
                print("[MapScreenViewModel] Global dataset fetch cancelled")
#endif
            } catch {
#if DEBUG
                print("[MapScreenViewModel] Failed to load global dataset:", error)
#endif
            }
            self.globalDatasetTask = nil
            self.updateSearchActivityIndicator()
        }
    }

    func mergeIntoGlobalDataset(_ newPlaces: [Place]) {
        guard !newPlaces.isEmpty else { return }
        let filtered = newPlaces.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !filtered.isEmpty else { return }
        let combined = deduplicate(globalDataset + filtered)
        let sorted = PlaceOverrides.sorted(combined)
        globalDataset = sorted
    }

    func deduplicate(_ places: [Place]) -> [Place] {
        PlaceOverrides.deduplicate(places)
    }

    func insertOrUpdatePlace(_ place: Place) {
        var updated = allPlaces
        if let existingIndex = updated.firstIndex(where: { $0.id == place.id }) {
            updated[existingIndex] = place
        } else {
            updated.append(place)
        }
        let deduped = deduplicate(updated)
        allPlaces = PlaceOverrides.sorted(deduped)
        apply(filter: currentFilter)
    }

    func refreshSearchResultsIfNeeded(with place: Place) {
        guard let query = lastSearchQuery, !query.isEmpty else { return }
        guard !matches(in: [place], query: query).isEmpty else { return }
        let deduped = deduplicate(searchResults + [place])
        searchResults = PlaceOverrides.sorted(deduped)
    }

    func updateSearchActivityIndicator() {
        let active = (remoteSearchTask != nil) || (manualSearchTask != nil) || (globalDatasetTask != nil) || (appleFallbackTask != nil)
        if active, let query = lastSearchQuery, !query.isEmpty {
            isSearching = true
        } else if !active {
            isSearching = false
        }
    }

    func makePlace(from mapItem: MKMapItem,
                   halalStatus: Place.HalalStatus,
                   confidence: Double?) -> Place? {
        let coordinate = mapItem.halalCoordinate
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }

        let trimmedName = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedName.isEmpty else { return nil }

        return Place(
            name: trimmedName,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: .restaurant,
            address: mapItem.halalShortAddress,
            halalStatus: halalStatus,
            rating: nil,
            ratingCount: nil,
            confidence: confidence,
            source: "apple",
            applePlaceID: mapItem.identifier?.rawValue
        )
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
