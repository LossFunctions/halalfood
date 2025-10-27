import Foundation

enum PerformanceEvent: String {
    case appLaunch = "AppLaunch"
    case mapRegionChange = "MapRegionChange"
    case mapFetch = "MapFetch"
    case mapAnnotationSync = "MapAnnotationSync"
    case communityFetch = "CommunityFetch"
    case communityDisplay = "CommunityDisplay"
    case globalDatasetFetch = "GlobalDatasetFetch"
    case apiGetPlaces = "APIGetPlaces"
    case apiFetchAllPlaces = "APIFetchAllPlaces"
    case apiCommunityTopRated = "APICommunityTopRated"
    case imageLoad = "ImageLoad"
    case metricKit = "MetricKit"

    var signpostName: StaticString {
        switch self {
        case .appLaunch: return "AppLaunch"
        case .mapRegionChange: return "MapRegionChange"
        case .mapFetch: return "MapFetch"
        case .mapAnnotationSync: return "MapAnnotationSync"
        case .communityFetch: return "CommunityFetch"
        case .communityDisplay: return "CommunityDisplay"
        case .globalDatasetFetch: return "GlobalDatasetFetch"
        case .apiGetPlaces: return "APIGetPlaces"
        case .apiFetchAllPlaces: return "APIFetchAllPlaces"
        case .apiCommunityTopRated: return "APICommunityTopRated"
        case .imageLoad: return "ImageLoad"
        case .metricKit: return "MetricKit"
        }
    }
}

#if DEBUG
import os
import os.signpost

struct PerformanceSpan {
    fileprivate let event: PerformanceEvent
    fileprivate let start: DispatchTime
    fileprivate let signpostID: OSSignpostID
    fileprivate let log: OSLog
    fileprivate let initialMetadata: String?

    fileprivate init(event: PerformanceEvent, start: DispatchTime, signpostID: OSSignpostID, log: OSLog, metadata: String?) {
        self.event = event
        self.start = start
        self.signpostID = signpostID
        self.log = log
        self.initialMetadata = metadata
    }
}

enum PerformanceMetrics {
    private static let subsystem = "com.halalfood.app"
    private static let defaultLog = OSLog(subsystem: subsystem, category: "Performance")
    private static let logger = Logger(subsystem: subsystem, category: "Performance")

    @discardableResult
    static func begin(event: PerformanceEvent, metadata: String? = nil, log: OSLog? = nil) -> PerformanceSpan {
        let usedLog = log ?? defaultLog
        let signpostID = OSSignpostID(log: usedLog)
        let start = DispatchTime.now()
        if let metadata {
            os_signpost(.begin, log: usedLog, name: event.signpostName, signpostID: signpostID, "%{public}s", metadata)
            logger.log("▶︎ \(event.rawValue) start – \(metadata, privacy: .public)")
        } else {
            os_signpost(.begin, log: usedLog, name: event.signpostName, signpostID: signpostID)
            logger.log("▶︎ \(event.rawValue) start")
        }
        return PerformanceSpan(event: event, start: start, signpostID: signpostID, log: usedLog, metadata: metadata)
    }

    static func end(_ span: PerformanceSpan, metadata: String? = nil) {
        let elapsed = DispatchTime.now().uptimeNanoseconds - span.start.uptimeNanoseconds
        let milliseconds = Double(elapsed) / 1_000_000
        let formatted = String(format: "%.2f", milliseconds)
        let message = metadata ?? span.initialMetadata
        if let message {
            os_signpost(.end, log: span.log, name: span.event.signpostName, signpostID: span.signpostID, "%{public}s", message)
            logger.log("◼︎ \(span.event.rawValue) end \(formatted, privacy: .public) ms – \(message, privacy: .public)")
        } else {
            os_signpost(.end, log: span.log, name: span.event.signpostName, signpostID: span.signpostID)
            logger.log("◼︎ \(span.event.rawValue) end \(formatted, privacy: .public) ms")
        }
    }

    static func end(_ span: PerformanceSpan?, metadata: String? = nil) {
        guard let span else { return }
        end(span, metadata: metadata)
    }

    static func point(event: PerformanceEvent, metadata: String? = nil, log: OSLog? = nil) {
        let usedLog = log ?? defaultLog
        if let metadata {
            os_signpost(.event, log: usedLog, name: event.signpostName, "%{public}s", metadata)
            logger.log("● \(event.rawValue) – \(metadata, privacy: .public)")
        } else {
            os_signpost(.event, log: usedLog, name: event.signpostName)
            logger.log("● \(event.rawValue)")
        }
    }
}

final class AppPerformanceTracker {
    static let shared = AppPerformanceTracker()

    private var spans: [PerformanceEvent: PerformanceSpan] = [:]
    private let queue = DispatchQueue(label: "com.halalfood.performance.tracker")

    private init() {}

    func begin(_ event: PerformanceEvent, metadata: String? = nil) {
        let span = PerformanceMetrics.begin(event: event, metadata: metadata)
        queue.sync {
            spans[event] = span
        }
    }

    func end(_ event: PerformanceEvent, metadata: String? = nil) {
        let span = queue.sync { spans.removeValue(forKey: event) }
        PerformanceMetrics.end(span, metadata: metadata)
    }

    func cancel(_ event: PerformanceEvent, metadata: String? = nil) {
        let span = queue.sync { spans.removeValue(forKey: event) }
        if span != nil {
            let message = metadata ?? "Cancelled"
            PerformanceMetrics.point(event: event, metadata: message)
        }
    }
}

#if canImport(MetricKit)
import MetricKit

final class PerformanceMetricObserver: NSObject, MXMetricManagerSubscriber {
    static let shared = PerformanceMetricObserver()

    private let dateFormatter: ISO8601DateFormatter

    private override init() {
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func stop() {
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        payloads.forEach(logMetricPayload)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let window = payloadWindowDescription(payload.timeStampBegin, payload.timeStampEnd)
            PerformanceMetrics.point(event: .metricKit, metadata: "Diagnostics window \(window)")
            PerformanceMetrics.point(event: .metricKit, metadata: String(describing: payload))
        }
    }

    private func logMetricPayload(_ payload: MXMetricPayload) {
        let window = payloadWindowDescription(payload.timeStampBegin, payload.timeStampEnd)
        PerformanceMetrics.point(event: .metricKit, metadata: "Metrics window \(window)")
        PerformanceMetrics.point(event: .metricKit, metadata: String(describing: payload))
    }

    private func payloadWindowDescription(_ begin: Date, _ end: Date) -> String {
        let startString = dateFormatter.string(from: begin)
        let endString = dateFormatter.string(from: end)
        return "\(startString) – \(endString)"
    }
}
#endif

#else

struct PerformanceSpan {
    init() {}
}

enum PerformanceMetrics {
    static func begin(event: PerformanceEvent, metadata: String? = nil, log: Any? = nil) -> PerformanceSpan { PerformanceSpan() }
    static func end(_ span: PerformanceSpan, metadata: String? = nil) {}
    static func end(_ span: PerformanceSpan?, metadata: String? = nil) {}
    static func point(event: PerformanceEvent, metadata: String? = nil, log: Any? = nil) {}
}

final class AppPerformanceTracker {
    static let shared = AppPerformanceTracker()
    private init() {}
    func begin(_ event: PerformanceEvent, metadata: String? = nil) {}
    func end(_ event: PerformanceEvent, metadata: String? = nil) {}
    func cancel(_ event: PerformanceEvent, metadata: String? = nil) {}
}

#endif
