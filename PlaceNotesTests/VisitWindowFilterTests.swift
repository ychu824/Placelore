import XCTest
import SwiftData
import CoreLocation
@testable import PlaceNotes

@MainActor
final class VisitWindowFilterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let cal = Calendar(identifier: .gregorian)

    override func setUp() async throws {
        let schema = Schema([Place.self, Visit.self, RawLocationSample.self, JournalEntry.self, CustomCategory.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    private func makePlace(lat: Double = 37.78, lon: Double = -122.41) -> Place {
        let p = Place(name: "P", latitude: lat, longitude: lon)
        context.insert(p)
        return p
    }

    private func makeVisit(_ place: Place, arrive: Date, depart: Date?) -> Visit {
        let v = Visit(arrivalDate: arrive, departureDate: depart, place: place)
        context.insert(v)
        return v
    }

    private func dayOffset(_ days: Int) -> Date {
        cal.date(byAdding: .day, value: days, to: Date())!
    }

    func testVisitsInWindowIncludesBoundary() {
        let now = Date()
        let p = makePlace()
        _ = makeVisit(p, arrive: cal.date(byAdding: .day, value: -15, to: now)!, depart: cal.date(byAdding: .day, value: -15, to: now)!)
        _ = makeVisit(p, arrive: cal.date(byAdding: .day, value: -5, to: now)!, depart: cal.date(byAdding: .day, value: -5, to: now)!)
        _ = makeVisit(p, arrive: cal.date(byAdding: .day, value: -30, to: now)!, depart: cal.date(byAdding: .day, value: -30, to: now)!)

        let window = TimeWindow(endDate: now, lengthDays: 15, firstVisitDate: cal.date(byAdding: .day, value: -60, to: now)!)
        let all = try! context.fetch(FetchDescriptor<Visit>())
        let filtered = VisitWindowFilter.visits(in: window, from: all)
        XCTAssertEqual(filtered.count, 2)
    }

    func testVisitsInWindowExcludesPastEnd() {
        let p = makePlace()
        let now = Date()
        let inside = cal.date(byAdding: .second, value: -1, to: now)!
        let after = cal.date(byAdding: .second, value: 1, to: now)!
        _ = makeVisit(p, arrive: inside, depart: inside)
        _ = makeVisit(p, arrive: after, depart: after)

        let window = TimeWindow(endDate: now, lengthDays: 15, firstVisitDate: dayOffset(-60))
        let all = try! context.fetch(FetchDescriptor<Visit>())
        let filtered = VisitWindowFilter.visits(in: window, from: all)
        XCTAssertEqual(filtered.count, 1)
    }

    func testWeightedSumsDurationPerPlace() {
        let a = makePlace(lat: 37.78, lon: -122.41)
        let b = makePlace(lat: 37.79, lon: -122.42)
        _ = makeVisit(a, arrive: dayOffset(-1), depart: cal.date(byAdding: .minute, value: 30, to: dayOffset(-1))!)
        _ = makeVisit(a, arrive: dayOffset(-2), depart: cal.date(byAdding: .minute, value: 90, to: dayOffset(-2))!)
        _ = makeVisit(b, arrive: dayOffset(-1), depart: cal.date(byAdding: .minute, value: 15, to: dayOffset(-1))!)

        let all = try! context.fetch(FetchDescriptor<Visit>())
        let weighted = VisitWindowFilter.weighted(all)
        XCTAssertEqual(weighted.count, 2)
        let weightForA = weighted.first { $0.coordinate.latitude == 37.78 }?.weight ?? 0
        let weightForB = weighted.first { $0.coordinate.latitude == 37.79 }?.weight ?? 0
        XCTAssertEqual(weightForA, 120, accuracy: 0.5)
        XCTAssertEqual(weightForB, 15, accuracy: 0.5)
    }

    func testActiveVisitTreatedAsEndingNow() {
        let p = makePlace()
        let arrival = cal.date(byAdding: .minute, value: -45, to: Date())!
        _ = makeVisit(p, arrive: arrival, depart: nil)
        let all = try! context.fetch(FetchDescriptor<Visit>())
        let weighted = VisitWindowFilter.weighted(all)
        XCTAssertEqual(weighted.count, 1)
        XCTAssertEqual(weighted[0].weight, 45, accuracy: 1)
    }

    func testSamplesCapDays() {
        let now = Date()
        let in7 = cal.date(byAdding: .day, value: -3, to: now)!
        let in12 = cal.date(byAdding: .day, value: -10, to: now)!
        let in20 = cal.date(byAdding: .day, value: -18, to: now)!
        for ts in [in7, in12, in20] {
            let s = RawLocationSample(
                latitude: 37.78, longitude: -122.41, timestamp: ts,
                horizontalAccuracy: 5, speed: 0, filterStatus: "accepted"
            )
            context.insert(s)
        }
        let window = TimeWindow(endDate: now, lengthDays: 15, firstVisitDate: dayOffset(-60))
        let all = try! context.fetch(FetchDescriptor<RawLocationSample>())
        let samples = VisitWindowFilter.samples(in: window, from: all, capDays: 7)
        XCTAssertEqual(samples.count, 1)   // only the 3-day-old sample
    }

    func testSamplesExcludesRejectedAccuracy() {
        let now = Date()
        let goodTS = cal.date(byAdding: .day, value: -2, to: now)!
        let badTS = cal.date(byAdding: .day, value: -3, to: now)!
        context.insert(RawLocationSample(
            latitude: 37.78, longitude: -122.41, timestamp: goodTS,
            horizontalAccuracy: 5, speed: 0, filterStatus: "accepted"
        ))
        context.insert(RawLocationSample(
            latitude: 37.78, longitude: -122.41, timestamp: badTS,
            horizontalAccuracy: 200, speed: 0, filterStatus: "rejected-accuracy"
        ))
        let window = TimeWindow(endDate: now, lengthDays: 15, firstVisitDate: dayOffset(-60))
        let all = try! context.fetch(FetchDescriptor<RawLocationSample>())
        let samples = VisitWindowFilter.samples(in: window, from: all, capDays: 7)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.filterStatus, "accepted")
    }
}
