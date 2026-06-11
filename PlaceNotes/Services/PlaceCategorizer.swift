import Foundation
import MapKit

/// Uses MKLocalSearch to categorize places by nearby points of interest.
final class PlaceCategorizer {

    /// Known POI categories mapped to human-readable labels and SF Symbols.
    static let categoryMap: [(category: MKPointOfInterestCategory, label: String, icon: String)] = [
        (.restaurant, "Restaurant", "fork.knife"),
        (.cafe, "Cafe", "cup.and.saucer.fill"),
        (.bakery, "Bakery", "birthday.cake"),
        (.brewery, "Brewery", "mug.fill"),
        (.foodMarket, "Grocery", "cart.fill"),
        (.fitnessCenter, "Gym", "figure.run"),
        (.hospital, "Hospital", "cross.case.fill"),
        (.pharmacy, "Pharmacy", "pills.fill"),
        (.school, "School", "graduationcap.fill"),
        (.university, "University", "building.columns.fill"),
        (.library, "Library", "books.vertical.fill"),
        (.store, "Store", "bag.fill"),
        (.gasStation, "Gas Station", "fuelpump.fill"),
        (.parking, "Parking", "p.square.fill"),
        (.park, "Park", "leaf.fill"),
        (.beach, "Beach", "beach.umbrella"),
        (.theater, "Theater", "theatermasks.fill"),
        (.museum, "Museum", "building.columns"),
        (.nightlife, "Nightlife", "music.note"),
        (.hotel, "Hotel", "bed.double.fill"),
        (.airport, "Airport", "airplane"),
        (.publicTransport, "Transit", "bus.fill"),
        (.bank, "Bank", "banknote.fill"),
        (.postOffice, "Post Office", "envelope.fill"),
        (.laundry, "Laundry", "washer.fill"),
    ]

    /// Looks up the nearest POI category for a coordinate.
    /// Returns a human-readable category string, or nil if no POI is found nearby.
    ///
    /// One `.includingAll` request, matched locally against `categoryMap` —
    /// MKLocalSearch is OS-rate-limited, so issuing one request per known
    /// category (25 sequential network calls) is not an option here.
    static func categorize(latitude: Double, longitude: Double) async -> (label: String, icon: String)? {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let targetLocation = CLLocation(latitude: latitude, longitude: longitude)
        let radius: CLLocationDistance = 100

        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        request.pointOfInterestFilter = .includingAll
        let search = MKLocalSearch(request: request)

        guard let response = try? await search.start() else { return nil }

        let nearest = response.mapItems
            .compactMap { item -> (category: MKPointOfInterestCategory, distance: CLLocationDistance)? in
                guard let category = item.pointOfInterestCategory,
                      let location = item.placemark.location else { return nil }
                let distance = location.distance(from: targetLocation)
                guard distance < radius else { return nil }
                return (category, distance)
            }
            .min { $0.distance < $1.distance }

        guard let nearest else { return nil }

        if let match = categoryMap.first(where: { $0.category == nearest.category }) {
            return (match.label, match.icon)
        }
        // Return the raw category name cleaned up
        let raw = nearest.category.rawValue
            .replacingOccurrences(of: "MKPOICategory", with: "")
        return (raw, "mappin")
    }

    /// Returns the SF Symbol for a category label.
    static func icon(for categoryLabel: String?) -> String {
        guard let label = categoryLabel else { return "mappin.circle.fill" }
        return categoryMap.first(where: { $0.label == label })?.icon ?? "mappin.circle.fill"
    }

    /// Emoji mapping for categories — used for map annotations.
    private static let emojiMap: [String: String] = [
        "Restaurant": "\u{1F374}",    // fork and knife
        "Cafe": "\u{2615}",           // hot beverage
        "Bakery": "\u{1F370}",        // shortcake
        "Brewery": "\u{1F37A}",       // beer mug
        "Grocery": "\u{1F6D2}",       // shopping cart
        "Gym": "\u{1F4AA}",           // flexed biceps
        "Hospital": "\u{1F3E5}",      // hospital
        "Pharmacy": "\u{1F48A}",      // pill
        "School": "\u{1F393}",        // graduation cap
        "University": "\u{1F3DB}",    // classical building
        "Library": "\u{1F4DA}",       // books
        "Store": "\u{1F6CD}",         // shopping bags
        "Gas Station": "\u{26FD}",    // fuel pump
        "Parking": "\u{1F17F}",       // P button
        "Park": "\u{1F333}",          // deciduous tree
        "Beach": "\u{1F3D6}",         // beach with umbrella
        "Theater": "\u{1F3AD}",       // performing arts
        "Museum": "\u{1F3DB}",        // classical building
        "Nightlife": "\u{1F3B6}",     // musical notes
        "Hotel": "\u{1F3E8}",         // hotel
        "Airport": "\u{2708}",        // airplane
        "Transit": "\u{1F68C}",       // bus
        "Bank": "\u{1F3E6}",          // bank
        "Post Office": "\u{1F4EE}",   // postbox
        "Laundry": "\u{1F9FA}",       // basket
    ]

    /// Returns an emoji for a category label.
    static func emoji(for categoryLabel: String?) -> String {
        guard let label = categoryLabel else { return "\u{1F4CD}" } // round pushpin
        return emojiMap[label] ?? "\u{1F4CD}"
    }
}
