//
//  HalalFoodApp.swift
//  HalalFood
//
//  Created by Umi Hussaini on 9/18/25.
//

import SwiftUI
import GoogleMaps

@main
struct HalalFoodApp: App {
    init() {
        // Fix ScrollView intercepting taps on buttons (e.g., PreviouslyTrendingCard toggle)
        UIScrollView.appearance().delaysContentTouches = false

        if let apiKey = Env.googleMapsAPIKey {
            GMSServices.provideAPIKey(apiKey)
        } else {
#if DEBUG
            print("[GoogleMaps] API key missing; map tiles may be restricted.")
#endif
        }
        Task {
            await YelpDiskCache.shared.runMaintenanceIfNeeded()
        }
#if DEBUG
        AppPerformanceTracker.shared.begin(.appLaunch, metadata: "App init")
#if canImport(MetricKit)
        PerformanceMetricObserver.shared.start()
#endif
#endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
