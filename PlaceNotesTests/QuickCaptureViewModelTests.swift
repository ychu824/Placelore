import XCTest
import CoreLocation
import SwiftData
import UIKit
@testable import PlaceNotes

@MainActor
final class QuickCaptureViewModelTests: XCTestCase {

    @MainActor
    private final class StubOneShot: LocationOneShotProviding {
        var result: CLLocation?
        func fetchOnce(timeout: TimeInterval) async -> CLLocation? { result }
        func cancel() {}
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Place.self, Visit.self, JournalEntry.self, CustomCategory.self, RawLocationSample.self,
            configurations: config
        )
        return ModelContext(container)
    }

    func testInitialStateIsIdle() throws {
        let vm = QuickCaptureViewModel(oneShot: StubOneShot(), context: try makeContext())
        XCTAssertEqual(vm.state, .idle)
    }

    func testBeginCaptureMovesToAcquiringLocation() async throws {
        let stub = StubOneShot()
        stub.result = CLLocation(latitude: 37.78, longitude: -122.41)
        let vm = QuickCaptureViewModel(oneShot: stub, context: try makeContext())
        vm.beginCapture()
        XCTAssertEqual(vm.state, .acquiringLocation)
    }

    func testCancelCaptureReturnsToIdle() throws {
        let vm = QuickCaptureViewModel(oneShot: StubOneShot(), context: try makeContext())
        vm.beginCapture()
        vm.cancelCapture()
        XCTAssertEqual(vm.state, .idle)
    }

    func testBeginCaptureForKnownPlaceTransitionsToAcquiringLocation() throws {
        let context = try makeContext()
        let place = Place(name: "Cafe", latitude: 37.78, longitude: -122.41)
        let visit = Visit(arrivalDate: .now, departureDate: nil, place: place)
        context.insert(place)
        context.insert(visit)
        try context.save()

        let vm = QuickCaptureViewModel(oneShot: StubOneShot(), context: context)
        vm.beginCaptureForKnownPlace(place, visit: visit)

        XCTAssertEqual(vm.state, .acquiringLocation)
        XCTAssertTrue(vm.showCamera)
    }

    func testBeginCaptureForKnownPlaceGuardedWhileBusy() throws {
        let context = try makeContext()
        let place = Place(name: "Cafe", latitude: 0, longitude: 0)
        let visit = Visit(arrivalDate: .now, departureDate: nil, place: place)
        context.insert(place)
        context.insert(visit)
        try context.save()

        let vm = QuickCaptureViewModel(oneShot: StubOneShot(), context: context)
        vm.beginCapture()    // state -> .acquiringLocation
        let prior = vm.state
        vm.beginCaptureForKnownPlace(place, visit: visit)
        XCTAssertEqual(vm.state, prior, "Re-entry while busy should be a no-op")
    }

    func testCoarseFixFallsBackToManualPickWithApproximateCoordinate() async throws {
        let stub = StubOneShot()
        // Indoors-on-WiFi: a fix exists but is too coarse to attribute automatically.
        stub.result = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41),
            altitude: 0,
            horizontalAccuracy: 200,
            verticalAccuracy: -1,
            timestamp: Date()
        )
        let vm = QuickCaptureViewModel(oneShot: stub, context: try makeContext())
        vm.beginCapture()

        let tinyImage = UIImage(systemName: "photo")!
        vm.photoCaptured(image: tinyImage, exifLocation: nil)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if vm.state == .manualPickNeeded { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(vm.state, .manualPickNeeded)
        XCTAssertNotNil(vm.pendingApproximateCoordinate)
        XCTAssertEqual(vm.pendingApproximateCoordinate?.latitude ?? 0, 37.78, accuracy: 0.0001)
        XCTAssertNotNil(vm.pendingPhotoAssetId)
    }

    func testManualLocationSelectedLogsCaptureAtCoordinate() async throws {
        let context = try makeContext()
        // Pre-insert a place at the coordinate so PlaceResolver matches it within 50m and
        // never reaches the network (CLGeocoder / MKLocalSearch) — keeps the test offline.
        let place = Place(name: "Office", latitude: 37.78, longitude: -122.41)
        context.insert(place)
        try context.save()
        let vm = QuickCaptureViewModel(oneShot: StubOneShot(), context: context)

        vm.manualLocationSelected(
            coordinate: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.41),
            photoAssetId: "asset-coarse"
        )

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if case .done = vm.state { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        guard case .done = vm.state else {
            XCTFail("Expected .done state, got \(vm.state)")
            return
        }
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.photoAssetIdentifiers, ["asset-coarse"])
        XCTAssertEqual(entries.first?.place?.id, place.id)
    }

    func testCancelClearsApproximateCoordinate() throws {
        let vm = QuickCaptureViewModel(oneShot: StubOneShot(), context: try makeContext())
        vm.beginCapture()
        vm.cancelCapture()
        XCTAssertNil(vm.pendingApproximateCoordinate)
    }

    func testKnownPlaceCaptureCreatesJournalEntryLinkedToVisit() async throws {
        let context = try makeContext()
        let place = Place(name: "Cafe", latitude: 0, longitude: 0)
        let visit = Visit(arrivalDate: .now, departureDate: nil, place: place)
        context.insert(place)
        context.insert(visit)
        try context.save()

        let vm = QuickCaptureViewModel(oneShot: StubOneShot(), context: context)
        vm.beginCaptureForKnownPlace(place, visit: visit)

        let tinyImage = UIImage(systemName: "photo")!
        vm.photoCaptured(image: tinyImage, exifLocation: nil)

        // Drain the background Task — poll until state settles to .done.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if case .done = vm.state { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        guard case .done(let payload) = vm.state else {
            XCTFail("Expected .done state, got \(vm.state)")
            return
        }
        XCTAssertEqual(payload.kind, .merged)
        XCTAssertEqual(payload.visitID, visit.id)

        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.visit?.id, visit.id)
        XCTAssertEqual(entries.first?.place?.id, place.id)

        let visits = try context.fetch(FetchDescriptor<Visit>())
        XCTAssertEqual(visits.count, 1, "No new Visit should be created")
    }
}
