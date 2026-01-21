//
//  HalalFoodApp.swift
//  HalalFood
//
//  Created by Umi Hussaini on 9/18/25.
//

import SwiftUI

@main
struct HalalFoodApp: App {
    init() {
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
