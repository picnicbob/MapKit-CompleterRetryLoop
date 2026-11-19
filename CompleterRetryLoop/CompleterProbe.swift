import CoreLocation
import MapKit
import Observation

/// Owns an MKLocalSearchCompleter that's configured but never given a query, and counts how often it reports
/// failure, alongside an MKMapView that's shown for the app's whole life.
///
/// Expected: no searches, so no delegate calls. Observed: setting `regionPriority = .required` starts a search
/// anyway, which fails; without it the completer stays idle, so it's required for the loop. While the map view
/// isn't showing the user's location, the completer's one-time device location update succeeds while that search
/// is in flight, which schedules another, so MapKit retries about every 250 ms indefinitely. Within a minute the app hits MapKit's limit of 100 requests per 60 seconds, which throttles its
/// real searches too.
///
/// With `showsUserLocation` on, it fails once and doesn't retry, presumably because MapKit's shared location
/// manager then has a fresh location the completer uses directly, rather than asking for a one-time update.
/// Turning it on or off between runs, without relaunching, turns the loop off or on.
@Observable
final class CompleterProbe: NSObject {
    /// Shown at the top of the screen. Any MKMapView with a nonzero size, on screen or not, sets off the loop
    /// unless it shows the user's location.
    @ObservationIgnored let mapView = MKMapView()
    /// The map view's `showsUserLocation`. On, there's one failure and no retries; off, the completer loops.
    var showsUserLocation = false {
        didSet {
            mapView.showsUserLocation = showsUserLocation
            print("[Probe] showsUserLocation: \(showsUserLocation)")
        }
    }

    /// Sets the completer's `regionPriority = .required` when Start makes it, which starts a search though no
    /// query is ever set. Off, the completer keeps the default priority.
    var setsRequiredRegionPriority = true

    private(set) var completer: MKLocalSearchCompleter?
    private(set) var failureCount = 0
    private(set) var lastError: String?
    private(set) var startedAt: Date?

    /// The completer only locates the device, which is what keeps it retrying, with location access.
    @ObservationIgnored private var locationSession: CLServiceSession?

    func requestLocationAccess() {
        locationSession = CLServiceSession(authorization: .whenInUse)
    }

    func start() {
        failureCount = 0
        lastError = nil
        startedAt = .now

        let completer = MKLocalSearchCompleter()
        completer.delegate = self
        if setsRequiredRegionPriority {
            // Starts a search, though no queryFragment is ever set.
            completer.regionPriority = .required
        }
        self.completer = completer
        print("[Probe] started; regionPriority = .required: \(setsRequiredRegionPriority), showsUserLocation: \(showsUserLocation), queryFragment: \"\(completer.queryFragment)\", isSearching: \(completer.isSearching)")
    }

    func stop() {
        completer?.cancel()
        completer?.delegate = nil
        completer = nil
        print("[Probe] stopped after \(failureCount) failures")
    }
}

extension CompleterProbe: @MainActor MKLocalSearchCompleterDelegate {
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        guard completer === self.completer else { return }
        failureCount += 1
        let nsError = error as NSError
        lastError = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        let elapsed = startedAt.map { String(format: "%.2f", Date.now.timeIntervalSince($0)) } ?? "?"
        print("[Probe] failure #\(failureCount) at +\(elapsed)s, isSearching: \(completer.isSearching) — \(nsError)")
    }
}
