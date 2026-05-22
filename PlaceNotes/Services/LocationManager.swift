import Foundation
import CoreLocation
import SwiftData
import os

private let logger = Logger(subsystem: "dev.placelore.app", category: "LocationManager")

// MARK: - Location Sample

/// A single GPS sample collected during a potential stay.
struct LocationSample {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let horizontalAccuracy: CLLocationAccuracy
    let speed: CLLocationSpeed
}

// MARK: - Stay Cluster

/// A cluster of location samples representing a detected stay.
struct StayCluster {
    let samples: [LocationSample]
    let center: CLLocationCoordinate2D
    let startDate: Date
    let medianAccuracy: Double
    let spreadMeters: Double

    /// Whether the cluster is too spread out to reliably resolve to a single place.
    var isAmbiguous: Bool { spreadMeters > 100 }
}

/// Plain-data representation of a location update queued for batch persistence.
private struct PendingRawSample {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double
    let speed: Double
    let altitude: Double?
    let verticalAccuracy: Double?
    let course: Double?
    let filterStatus: String
}

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let clManager = CLLocationManager()
    private var modelContext: ModelContext?

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentVisit: Visit?
    @Published var userLocation: CLLocationCoordinate2D?

    /// Last raw fix delivered by Core Location (coordinate, accuracy, timestamp).
    /// Used by photo capture as a fallback when a fresh one-shot fails.
    @Published var lastFix: CLLocation?

    var onVisitRecorded: ((Visit) -> Void)?

    // MARK: - Dwell detection

    /// Raw samples collected at the current candidate stay location.
    private var dwellSamples: [LocationSample] = []
    private var dwellStartDate: Date?
    private var lastRecordedDwellLocation: CLLocation?
    /// `dwellStartDate` value at the moment a visit was recorded for the current
    /// continuous dwell. Prevents repeated `recordDwellVisit` calls as new
    /// samples / timer ticks fire after the threshold first trips. Cleared
    /// whenever a fresh dwell begins (in `finalizeDwell`).
    private var recordedDwellStartDate: Date?
    private var dwellTimer: Timer?
    private let settings: AppSettings

    /// In-memory buffer of raw samples awaiting batch insert into SwiftData.
    /// Flushed when the buffer fills, on the dwell-timer tick, or on stop.
    /// Kept small so app termination loses at most a handful of samples.
    private var pendingRawSamples: [PendingRawSample] = []
    private let rawSampleBatchSize = 10

    /// CLVisit arrival/departure events seen during this tracking session,
    /// retained so a long gap in `didUpdateLocations` can be cross-checked
    /// against iOS-detected stays elsewhere.
    private var observedVisitEvents: [StayDetector.VisitEvent] = []

    /// Time gap between consecutive dwell samples beyond which we cross-check
    /// CLVisit events to decide whether the user left the dwell area.
    /// 10 min comfortably tolerates iOS auto-pause during a real stay.
    private let maxDwellGapSeconds: TimeInterval = 600

    /// Maximum age of CLVisit events kept in memory. Older events can't
    /// inform any current dwell decision.
    private let visitEventRetention: TimeInterval = 24 * 3600

    /// Distance (meters) the user must move before we consider them "left".
    private let dwellRadiusMeters: Double = 80

    /// Distance (meters) from a place at which an open visit is force-closed
    /// even if the dwell-finalize path missed the departure. Wider than the
    /// dwell radius so transient GPS jumps don't prematurely end a stay.
    private let orphanVisitCloseRadiusMeters: Double = 250

    /// Maximum horizontal accuracy (meters) to trust a fix for closing an
    /// orphan open visit. Looser than the dwell-collection filter so a fix
    /// that's clearly far away can still trigger a close.
    private let maxAccuracyForOrphanClose: CLLocationAccuracy = 100

    /// Maximum horizontal accuracy to accept a sample (meters).
    /// Samples noisier than this are dropped.
    private let maxAcceptableAccuracy: CLLocationAccuracy = 65

    /// Maximum speed (m/s) to accept a sample. ~3.6 km/h — faster means walking/driving, not staying.
    private let maxStationarySpeed: CLLocationSpeed = 2.0

    /// Minimum dwell time to create a place (seconds). Hard floor regardless of settings.
    private let minimumDwellSeconds: TimeInterval = 300 // 5 minutes

    /// Maximum accuracy to attempt venue labeling. Beyond this, fall back to address.
    private let maxAccuracyForVenueLabel: CLLocationAccuracy = StayDetector.maxAccuracyForVenueLabel

    /// Seconds the user must remain stationary to trigger a dwell visit.
    private var dwellThresholdSeconds: TimeInterval {
        max(minimumDwellSeconds, TimeInterval(settings.minStayMinutes * 60))
    }

    init(settings: AppSettings = .shared) {
        self.settings = settings
        super.init()
        clManager.delegate = self
        clManager.allowsBackgroundLocationUpdates = true
        clManager.pausesLocationUpdatesAutomatically = false
        clManager.activityType = .other
        clManager.desiredAccuracy = kCLLocationAccuracyBest
        clManager.distanceFilter = 5
        authorizationStatus = clManager.authorizationStatus
        logger.info("LocationManager initialized, auth status: \(self.authorizationStatus.rawValue), minStay: \(settings.minStayMinutes)min")
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        logger.info("ModelContext configured")
        cleanupStaleRawSamples(context: modelContext)
    }

    func requestAuthorization() {
        logger.info("Requesting always authorization")
        clManager.requestAlwaysAuthorization()
    }

    func startMonitoring() {
        logger.notice(">>> Starting all monitoring <<<")
        clManager.startMonitoringVisits()
        clManager.startMonitoringSignificantLocationChanges()
        clManager.startUpdatingLocation()
        startDwellTimer()
        logger.notice("Monitoring started: visits + significant changes + location updates + dwell timer")
    }

    func stopMonitoring() {
        logger.notice(">>> Stopping all monitoring <<<")
        clManager.stopMonitoringVisits()
        clManager.stopMonitoringSignificantLocationChanges()
        clManager.stopUpdatingLocation()
        dwellTimer?.invalidate()
        dwellTimer = nil
        flushRawSamples()
        finalizeDwell()
        observedVisitEvents.removeAll()
        logger.notice("All monitoring stopped")
    }

    private func recordVisitEvent(timestamp: Date, coordinate: CLLocationCoordinate2D) {
        let cutoff = Date().addingTimeInterval(-visitEventRetention)
        observedVisitEvents.removeAll { $0.timestamp < cutoff }
        observedVisitEvents.append(StayDetector.VisitEvent(timestamp: timestamp, coordinate: coordinate))
    }

    // MARK: - Dwell Timer

    private func startDwellTimer() {
        dwellTimer?.invalidate()
        dwellTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkDwellStatus()
        }
        logger.debug("Dwell timer started (30s interval)")
    }

    private func checkDwellStatus() {
        flushRawSamples()

        guard !dwellSamples.isEmpty,
              let start = dwellStartDate,
              let modelContext else {
            logger.debug("Dwell timer tick — no active dwell samples")
            return
        }

        let elapsed = Date().timeIntervalSince(start)
        let threshold = dwellThresholdSeconds
        if elapsed >= threshold {
            if let last = dwellSamples.last {
                let tailGap = Date().timeIntervalSince(last.timestamp)
                if tailGap > maxDwellGapSeconds,
                   StayDetector.didUserLeaveDuringGap(
                       visitEvents: observedVisitEvents,
                       from: last.timestamp,
                       to: Date(),
                       dwellCenter: weightedCenter(of: dwellSamples),
                       dwellRadiusMeters: dwellRadiusMeters
                   ) {
                    logger.notice("Dwell timer suppressed — \(Int(tailGap))s tail gap with CLVisit elsewhere; resetting")
                    finalizeDwell()
                    return
                }
            }
            if recordedDwellStartDate == start {
                logger.debug("Dwell timer tick — already recorded for this dwell, skipping")
                return
            }
            logger.notice("Dwell threshold reached via timer (\(Int(elapsed))s >= \(Int(threshold))s) — recording visit")
            let cluster = buildCluster(from: dwellSamples, startDate: start)
            recordDwellVisit(cluster: cluster, context: modelContext)
        } else {
            let remaining = Int(threshold - elapsed)
            logger.info("Dwell timer tick — \(remaining)s remaining, \(self.dwellSamples.count) samples collected")
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let old = authorizationStatus
        authorizationStatus = manager.authorizationStatus
        logger.notice("Authorization changed: \(old.rawValue) -> \(manager.authorizationStatus.rawValue)")

        switch manager.authorizationStatus {
        case .notDetermined:
            logger.warning("Authorization: not determined")
        case .restricted:
            logger.error("Authorization: restricted")
        case .denied:
            logger.error("Authorization: denied — location tracking will not work")
        case .authorizedWhenInUse:
            logger.notice("Authorization: when in use (consider requesting Always for background tracking)")
        case .authorizedAlways:
            logger.notice("Authorization: always — full background tracking enabled")
        @unknown default:
            logger.warning("Authorization: unknown value \(manager.authorizationStatus.rawValue)")
        }
    }

    func locationManager(_ manager: CLLocationManager, didVisit clVisit: CLVisit) {
        logger.notice("CLVisit received: (\(clVisit.coordinate.latitude), \(clVisit.coordinate.longitude))")
        logger.info("  arrival: \(clVisit.arrivalDate), departure: \(clVisit.departureDate == .distantFuture ? "still here" : "\(clVisit.departureDate)")")
        logger.info("  horizontalAccuracy: \(clVisit.horizontalAccuracy)m")

        recordVisitEvent(timestamp: clVisit.arrivalDate, coordinate: clVisit.coordinate)
        if clVisit.departureDate != .distantFuture {
            recordVisitEvent(timestamp: clVisit.departureDate, coordinate: clVisit.coordinate)
        }

        guard clVisit.arrivalDate != .distantPast else {
            logger.warning("CLVisit ignored — arrivalDate is distantPast (unknown arrival)")
            return
        }

        guard let modelContext else {
            logger.error("CLVisit ignored — modelContext is nil")
            return
        }

        let arrival = clVisit.arrivalDate
        let departure = clVisit.departureDate == .distantFuture ? nil : clVisit.departureDate

        if let dep = departure {
            let dwell = dep.timeIntervalSince(arrival)
            let threshold = dwellThresholdSeconds
            if dwell < threshold {
                logger.info("CLVisit ignored — dwell too short (\(Int(dwell))s < \(Int(threshold))s)")
                return
            }
        }

        // Determine confidence from CLVisit's accuracy
        let accuracy = clVisit.horizontalAccuracy
        let dwellSeconds = departure.map { $0.timeIntervalSince(arrival) }
        let confidence = computeConfidence(accuracy: accuracy, dwellSeconds: dwellSeconds, clusterSpread: nil)
        let useAddressFallback = accuracy > maxAccuracyForVenueLabel || confidence == .low

        Task { @MainActor in
            let (place, alternatives) = await PlaceResolver.findOrCreate(
                latitude: clVisit.coordinate.latitude,
                longitude: clVisit.coordinate.longitude,
                in: modelContext,
                addressOnly: useAddressFallback
            )

            if isDuplicate(place: place, arrival: arrival, context: modelContext) {
                logger.info("Skipping duplicate CLVisit for \(place.name)")
                return
            }

            let visit = Visit(arrivalDate: arrival, departureDate: departure, place: place)
            visit.alternativePlaces = alternatives
            visit.confidence = confidence
            visit.medianAccuracyMeters = accuracy
            modelContext.insert(visit)
            try? modelContext.save()

            closeOlderOpenVisits(
                excludingPlaceID: place.id,
                departureDate: arrival,
                context: modelContext
            )

            currentVisit = visit
            onVisitRecorded?(visit)
            logger.notice("Recorded CLVisit at \(place.name) (confidence: \(confidence.rawValue), accuracy: \(Int(accuracy))m)")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            logger.debug("didUpdateLocations called with empty array")
            return
        }

        logger.debug("Location update: (\(location.coordinate.latitude), \(location.coordinate.longitude)) accuracy: \(location.horizontalAccuracy)m speed: \(location.speed)m/s")

        guard let modelContext else {
            logger.error("Location update ignored — modelContext is nil")
            return
        }

        userLocation = location.coordinate
        lastFix = location

        closeStaleOpenVisits(currentLocation: location, context: modelContext)

        // Step 1: Filter noisy / stale samples
        let isAccurate = location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= maxAcceptableAccuracy
        let isStationary = location.speed < 0 || location.speed <= maxStationarySpeed // speed < 0 means unknown
        let isRecent = abs(location.timestamp.timeIntervalSinceNow) < 30 // not stale

        if !isAccurate {
            logger.debug("Sample dropped — accuracy \(location.horizontalAccuracy)m > \(self.maxAcceptableAccuracy)m threshold")
        }
        if !isStationary {
            logger.debug("Sample dropped — speed \(location.speed)m/s > \(self.maxStationarySpeed)m/s threshold")
        }

        let filterStatus: String
        if !isAccurate {
            filterStatus = "rejected-accuracy"
        } else if !isStationary {
            filterStatus = "rejected-speed"
        } else {
            filterStatus = "accepted"
        }

        pendingRawSamples.append(PendingRawSample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            altitude: location.altitude,
            verticalAccuracy: location.verticalAccuracy,
            course: location.course >= 0 ? location.course : nil,
            filterStatus: filterStatus
        ))
        if pendingRawSamples.count >= rawSampleBatchSize {
            flushRawSamples()
        }

        let sample = LocationSample(
            coordinate: location.coordinate,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed
        )

        if !dwellSamples.isEmpty {
            // Calculate distance from the centroid of existing samples for stability
            let currentCenter = weightedCenter(of: dwellSamples)
            let centerLocation = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
            let distance = location.distance(from: centerLocation)

            if distance < dwellRadiusMeters {
                if isAccurate && isStationary && isRecent {
                    if let last = dwellSamples.last,
                       sample.timestamp.timeIntervalSince(last.timestamp) > maxDwellGapSeconds,
                       StayDetector.didUserLeaveDuringGap(
                           visitEvents: observedVisitEvents,
                           from: last.timestamp,
                           to: sample.timestamp,
                           dwellCenter: currentCenter,
                           dwellRadiusMeters: dwellRadiusMeters
                       ) {
                        logger.notice("Dwell gap of \(Int(sample.timestamp.timeIntervalSince(last.timestamp)))s corroborated by CLVisit elsewhere — resetting")
                        finalizeDwell()
                        dwellSamples = [sample]
                        dwellStartDate = sample.timestamp
                        logger.info("New dwell started after gap reset at (\(location.coordinate.latitude), \(location.coordinate.longitude))")
                        return
                    }
                    dwellSamples.append(sample)
                    logger.debug("Sample collected (\(self.dwellSamples.count) total), \(Int(distance))m from center")
                }

                if let start = dwellStartDate,
                   Date().timeIntervalSince(start) >= dwellThresholdSeconds,
                   recordedDwellStartDate != start {
                    logger.notice("Dwell threshold met via location update — recording visit")
                    let cluster = buildCluster(from: dwellSamples, startDate: start)
                    recordDwellVisit(cluster: cluster, context: modelContext)
                }
            } else {
                logger.info("Moved outside dwell radius (\(Int(distance))m >= \(Int(self.dwellRadiusMeters))m) — resetting dwell")
                finalizeDwell()
                // Start new dwell only if this sample is good
                if isAccurate && isStationary && isRecent {
                    dwellSamples = [sample]
                    dwellStartDate = Date()
                    logger.info("New dwell started at (\(location.coordinate.latitude), \(location.coordinate.longitude))")
                }
            }
        } else {
            // No dwell in progress — start one if sample is good
            if isAccurate && isStationary && isRecent {
                dwellSamples = [sample]
                dwellStartDate = Date()
                logger.info("First location — dwell started at (\(location.coordinate.latitude), \(location.coordinate.longitude))")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("Location error: \(error.localizedDescription)")
        if let clError = error as? CLError {
            logger.error("CLError code: \(clError.code.rawValue)")
        }
    }

    // MARK: - Raw Sample Batching

    private func flushRawSamples() {
        guard !pendingRawSamples.isEmpty else { return }
        let batch = pendingRawSamples
        pendingRawSamples.removeAll(keepingCapacity: true)
        Task { @MainActor [weak self] in
            guard let ctx = self?.modelContext else { return }
            for sample in batch {
                ctx.insert(RawLocationSample(
                    latitude: sample.latitude,
                    longitude: sample.longitude,
                    timestamp: sample.timestamp,
                    horizontalAccuracy: sample.horizontalAccuracy,
                    speed: sample.speed,
                    altitude: sample.altitude,
                    verticalAccuracy: sample.verticalAccuracy,
                    course: sample.course,
                    filterStatus: sample.filterStatus
                ))
            }
            do {
                try ctx.save()
                logger.debug("Flushed \(batch.count) raw samples")
            } catch {
                logger.error("Failed to save raw sample batch: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Raw Sample Retention

    private func cleanupStaleRawSamples(context: ModelContext) {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -settings.rawLocationRetentionDays,
            to: Date()
        ) ?? Date()

        Task { @MainActor in
            let descriptor = FetchDescriptor<RawLocationSample>(
                predicate: #Predicate { $0.timestamp < cutoff }
            )
            let stale = (try? context.fetch(descriptor)) ?? []
            for sample in stale {
                context.delete(sample)
            }
            if !stale.isEmpty {
                try? context.save()
                logger.info("Deleted \(stale.count) raw samples older than \(self.settings.rawLocationRetentionDays) days")
            }
        }
    }

    // MARK: - Cluster Building (delegates to StayDetector)

    private func weightedCenter(of samples: [LocationSample]) -> CLLocationCoordinate2D {
        StayDetector.weightedCenter(of: samples)
    }

    private func buildCluster(from samples: [LocationSample], startDate: Date) -> StayCluster {
        let cluster = StayDetector.buildCluster(from: samples, startDate: startDate)
        logger.info("Cluster built: center=(\(cluster.center.latitude), \(cluster.center.longitude)), \(samples.count) samples, spread=\(Int(cluster.spreadMeters))m, medianAccuracy=\(Int(cluster.medianAccuracy))m")
        return cluster
    }

    private func computeConfidence(accuracy: Double, dwellSeconds: TimeInterval?, clusterSpread: Double?) -> PlaceConfidence {
        StayDetector.computeConfidence(accuracy: accuracy, dwellSeconds: dwellSeconds, clusterSpread: clusterSpread)
    }

    // MARK: - Dwell Visit Recording

    private func recordDwellVisit(cluster: StayCluster, context: ModelContext) {
        let clusterCenter = CLLocation(latitude: cluster.center.latitude, longitude: cluster.center.longitude)

        if let lastDwell = lastRecordedDwellLocation,
           clusterCenter.distance(from: lastDwell) < dwellRadiusMeters {
            logger.debug("Dwell already recorded at this location — skipping")
            return
        }

        // Don't create place if dwell is too short
        let elapsed = Date().timeIntervalSince(cluster.startDate)
        if elapsed < minimumDwellSeconds {
            logger.info("Dwell too short (\(Int(elapsed))s < \(Int(self.minimumDwellSeconds))s) — not recording")
            return
        }

        lastRecordedDwellLocation = clusterCenter
        recordedDwellStartDate = cluster.startDate

        let confidence = computeConfidence(
            accuracy: cluster.medianAccuracy,
            dwellSeconds: elapsed,
            clusterSpread: cluster.spreadMeters
        )
        let useAddressFallback = cluster.medianAccuracy > maxAccuracyForVenueLabel || cluster.isAmbiguous || confidence == .low

        logger.notice("Recording dwell visit: center=(\(cluster.center.latitude), \(cluster.center.longitude)), \(cluster.samples.count) samples, confidence=\(confidence.rawValue), addressOnly=\(useAddressFallback)")

        Task { @MainActor in
            let (place, alternatives) = await PlaceResolver.findOrCreate(
                latitude: cluster.center.latitude,
                longitude: cluster.center.longitude,
                in: context,
                addressOnly: useAddressFallback
            )

            if isDuplicate(place: place, arrival: cluster.startDate, context: context) {
                logger.info("Skipping duplicate dwell visit for \(place.name)")
                return
            }

            let visit = Visit(arrivalDate: cluster.startDate, departureDate: nil, place: place)
            visit.alternativePlaces = alternatives
            visit.confidence = confidence
            visit.medianAccuracyMeters = cluster.medianAccuracy
            context.insert(visit)
            try? context.save()

            closeOlderOpenVisits(
                excludingPlaceID: place.id,
                departureDate: cluster.startDate,
                context: context
            )

            currentVisit = visit
            onVisitRecorded?(visit)
            let stayMinutes = Int(elapsed / 60)
            logger.notice("VISIT RECORDED: \(place.name) (confidence: \(confidence.rawValue), accuracy: \(Int(cluster.medianAccuracy))m, spread: \(Int(cluster.spreadMeters))m, stayed \(stayMinutes) min)")
        }
    }

    /// Close any prior open visit whose place is different from the
    /// newly-recorded one and whose arrival predates it. Maintains the
    /// "user is at one place at a time" invariant when the regular
    /// dwell-finalize path missed a departure.
    @MainActor
    private func closeOlderOpenVisits(
        excludingPlaceID: UUID,
        departureDate: Date,
        context: ModelContext
    ) {
        let cutoff = departureDate
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> {
                $0.departureDate == nil && $0.arrivalDate < cutoff
            }
        )
        guard let openVisits = try? context.fetch(descriptor) else { return }

        var closedAny = false
        for visit in openVisits {
            guard let place = visit.place, place.id != excludingPlaceID else { continue }
            visit.departureDate = departureDate
            closedAny = true
            logger.notice("Closed prior open visit at \(place.name) — superseded by new visit at \(departureDate)")
        }
        if closedAny {
            try? context.save()
        }
    }

    /// Safety net: close any open visit whose place is now far from the user's
    /// current location. The dwell-finalize path can miss this when iOS pauses
    /// or throttles location updates during a long stay and the dwell buffer
    /// loses coherence by the time movement resumes.
    private func closeStaleOpenVisits(currentLocation: CLLocation, context: ModelContext) {
        let placeLat = currentLocation.coordinate.latitude
        let placeLon = currentLocation.coordinate.longitude
        let accuracy = currentLocation.horizontalAccuracy
        let departureDate = currentLocation.timestamp
        let closeRadius = orphanVisitCloseRadiusMeters
        let maxAccuracy = maxAccuracyForOrphanClose

        Task { @MainActor in
            let descriptor = FetchDescriptor<Visit>(
                predicate: #Predicate { $0.departureDate == nil }
            )
            guard let openVisits = try? context.fetch(descriptor), !openVisits.isEmpty else { return }

            var closedAny = false
            for visit in openVisits {
                guard let place = visit.place else { continue }
                let hasLeft = StayDetector.hasUserLeftPlace(
                    placeLatitude: place.latitude,
                    placeLongitude: place.longitude,
                    currentLatitude: placeLat,
                    currentLongitude: placeLon,
                    currentAccuracy: accuracy,
                    maxAcceptableAccuracy: maxAccuracy,
                    thresholdMeters: closeRadius
                )
                guard hasLeft, departureDate > visit.arrivalDate else { continue }
                visit.departureDate = departureDate
                closedAny = true
                let distance = CLLocation(latitude: place.latitude, longitude: place.longitude)
                    .distance(from: CLLocation(latitude: placeLat, longitude: placeLon))
                logger.notice("Closed stale open visit at \(place.name) — user is \(Int(distance))m away")
            }

            if closedAny {
                try? context.save()
            }
        }
    }

    private func finalizeDwell() {
        guard !dwellSamples.isEmpty,
              let modelContext else {
            dwellSamples = []
            dwellStartDate = nil
            recordedDwellStartDate = nil
            return
        }

        // Use cluster center for more accurate departure matching
        let center = weightedCenter(of: dwellSamples)
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)

        Task { @MainActor in
            let descriptor = FetchDescriptor<Visit>(
                predicate: #Predicate { $0.departureDate == nil },
                sortBy: [SortDescriptor(\.arrivalDate, order: .reverse)]
            )
            if let activeVisit = try? modelContext.fetch(descriptor).first,
               let place = activeVisit.place {
                let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                if centerLoc.distance(from: placeLocation) < dwellRadiusMeters {
                    activeVisit.departureDate = Date()
                    try? modelContext.save()
                    logger.notice("Finalized departure for \(place.name)")
                }
            }
        }

        dwellSamples = []
        dwellStartDate = nil
        lastRecordedDwellLocation = nil
        recordedDwellStartDate = nil
    }

    // MARK: - Duplicate Detection

    /// True if a visit already exists within the time window AND geographically
    /// close enough that the two are likely the same stay resolved to different
    /// POIs (e.g. centroid drift inside a mall picking a coffee shop vs the
    /// main entry). Checks ALL Places, not just `place.visits`, because the
    /// failure mode is precisely that the duplicate lands on a different
    /// `Place` row.
    @MainActor
    private func isDuplicate(place: Place, arrival: Date, context: ModelContext) -> Bool {
        let placeID = place.id
        let openDescriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> { $0.departureDate == nil }
        )
        if let openVisits = try? context.fetch(openDescriptor) {
            for visit in openVisits where visit.place?.id == placeID && visit.arrivalDate < arrival {
                logger.debug("Duplicate detected — open visit at \(place.name) since \(visit.arrivalDate)")
                return true
            }
        }

        let timeWindow: TimeInterval = 600
        let spatialThresholdMeters: Double = 150
        let windowStart = arrival.addingTimeInterval(-timeWindow)
        let windowEnd = arrival.addingTimeInterval(timeWindow)
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> {
                $0.arrivalDate >= windowStart && $0.arrivalDate <= windowEnd
            }
        )
        let candidates = (try? context.fetch(descriptor)) ?? []
        let newPlaceLoc = CLLocation(latitude: place.latitude, longitude: place.longitude)
        for visit in candidates {
            guard let other = visit.place else { continue }
            if other.id == place.id {
                logger.debug("Duplicate detected at same place \(place.name) near \(arrival)")
                return true
            }
            let otherLoc = CLLocation(latitude: other.latitude, longitude: other.longitude)
            if newPlaceLoc.distance(from: otherLoc) < spatialThresholdMeters {
                logger.debug("Duplicate detected — \(place.name) is \(Int(newPlaceLoc.distance(from: otherLoc)))m from existing visit at \(other.name)")
                return true
            }
        }
        return false
    }

}
