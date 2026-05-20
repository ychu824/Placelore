import SwiftUI
import MapKit
import UIKit

struct MapContainerView: UIViewRepresentable {
    let overlayMode: OverlayMode
    let window: TimeWindow
    let weightedPoints: [WeightedPoint]
    let pathSamples: [RawLocationSample]
    let rankings: [PlaceRanking]
    let placesInWindow: Set<UUID>
    let userLocation: CLLocationCoordinate2D?
    let onSelectPlace: (Place) -> Void
    @Binding var recenterTrigger: Int       // bump to recenter to user location

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.register(
            PlaceHostingAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: PlaceHostingAnnotationView.reuseID
        )
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(
            map: map,
            mode: overlayMode,
            window: window,
            weightedPoints: weightedPoints,
            pathSamples: pathSamples,
            rankings: rankings,
            placesInWindow: placesInWindow,
            style: map.traitCollection.userInterfaceStyle
        )
        if context.coordinator.lastRecenterTrigger != recenterTrigger,
           let coord = userLocation {
            map.setRegion(
                MKCoordinateRegion(center: coord, latitudinalMeters: 500, longitudinalMeters: 500),
                animated: true
            )
            context.coordinator.lastRecenterTrigger = recenterTrigger
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapContainerView
        var lastRecenterTrigger = 0
        private var currentMode: OverlayMode = .heatmap
        private var heatOverlay: HeatmapTileRenderer?
        private var pathOverlay: MKPolyline?
        private var annotationCache: [String: PlaceAnnotation] = [:]
        private var lastHeatPoints: [WeightedPoint] = []
        private var lastHeatStyle: UIUserInterfaceStyle = .unspecified
        private var lastPathSamplesCount: Int = -1
        private var lastPathLastTimestamp: Date?

        init(parent: MapContainerView) { self.parent = parent }

        func update(
            map: MKMapView,
            mode: OverlayMode,
            window: TimeWindow,
            weightedPoints: [WeightedPoint],
            pathSamples: [RawLocationSample],
            rankings: [PlaceRanking],
            placesInWindow: Set<UUID>,
            style: UIUserInterfaceStyle
        ) {
            syncAnnotations(map: map, rankings: rankings, placesInWindow: placesInWindow, mode: mode)
            syncOverlays(map: map, mode: mode, weightedPoints: weightedPoints, pathSamples: pathSamples, style: style)
            currentMode = mode
        }

        // MARK: Annotations

        private func syncAnnotations(
            map: MKMapView,
            rankings: [PlaceRanking],
            placesInWindow: Set<UUID>,
            mode: OverlayMode
        ) {
            guard mode == .pins else {
                if !annotationCache.isEmpty {
                    map.removeAnnotations(Array(annotationCache.values))
                    annotationCache.removeAll()
                }
                return
            }
            var fresh: [String: PlaceAnnotation] = [:]
            for ranking in rankings {
                let id = ranking.place.id.uuidString
                let annotation = annotationCache[id] ?? PlaceAnnotation(ranking: ranking)
                annotation.ranking = ranking
                annotation.dimmed = !placesInWindow.contains(ranking.place.id)
                annotation.coordinate = ranking.place.coordinate
                fresh[id] = annotation
            }
            let oldIDs = Set(annotationCache.keys)
            let newIDs = Set(fresh.keys)
            let toRemove = oldIDs.subtracting(newIDs).compactMap { annotationCache[$0] }
            let toAdd = newIDs.subtracting(oldIDs).compactMap { fresh[$0] }
            map.removeAnnotations(toRemove)
            map.addAnnotations(toAdd)
            for id in newIDs.intersection(oldIDs) {
                if let view = map.view(for: fresh[id]!) as? PlaceHostingAnnotationView {
                    view.configure(with: fresh[id]!.ranking, dimmed: fresh[id]!.dimmed)
                }
            }
            annotationCache = fresh
        }

        // MARK: Overlays

        private func syncOverlays(
            map: MKMapView,
            mode: OverlayMode,
            weightedPoints: [WeightedPoint],
            pathSamples: [RawLocationSample],
            style: UIUserInterfaceStyle
        ) {
            // Heat
            let wantHeat = (mode == .heatmap && !weightedPoints.isEmpty)
            if wantHeat {
                let unchanged = weightedPoints == lastHeatPoints && style == lastHeatStyle && heatOverlay != nil
                if !unchanged {
                    let newHeat = HeatmapTileRenderer(points: weightedPoints, style: style)
                    if let existing = heatOverlay { map.removeOverlay(existing) }
                    map.addOverlay(newHeat, level: .aboveLabels)
                    heatOverlay = newHeat
                    lastHeatPoints = weightedPoints
                    lastHeatStyle = style
                }
            } else if let existing = heatOverlay {
                map.removeOverlay(existing)
                heatOverlay = nil
                lastHeatPoints = []
            }
            // Path
            let wantPath = (mode == .path && !pathSamples.isEmpty)
            if wantPath {
                let sig = pathSamples.count
                let lastTS = pathSamples.last?.timestamp
                let unchanged = sig == lastPathSamplesCount && lastTS == lastPathLastTimestamp && pathOverlay != nil
                if !unchanged {
                    let coords = pathSamples.sorted { $0.timestamp < $1.timestamp }.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                    let newPath = MKPolyline(coordinates: coords, count: coords.count)
                    if let existing = pathOverlay { map.removeOverlay(existing) }
                    map.addOverlay(newPath)
                    pathOverlay = newPath
                    lastPathSamplesCount = sig
                    lastPathLastTimestamp = lastTS
                }
            } else if let existing = pathOverlay {
                map.removeOverlay(existing)
                pathOverlay = nil
                lastPathSamplesCount = -1
                lastPathLastTimestamp = nil
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? HeatmapTileRenderer {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor.systemOrange
                r.lineWidth = 4
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard let place = annotation as? PlaceAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: PlaceHostingAnnotationView.reuseID,
                for: place
            ) as! PlaceHostingAnnotationView
            view.configure(with: place.ranking, dimmed: place.dimmed)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let place = view.annotation as? PlaceAnnotation {
                parent.onSelectPlace(place.ranking.place)
                mapView.deselectAnnotation(view.annotation, animated: false)
            }
        }
    }
}

// MARK: - Annotation model

final class PlaceAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var ranking: PlaceRanking
    var dimmed: Bool = false

    init(ranking: PlaceRanking) {
        self.ranking = ranking
        self.coordinate = ranking.place.coordinate
    }
}

// MARK: - Hosting annotation view

final class PlaceHostingAnnotationView: MKAnnotationView {
    static let reuseID = "PlaceHostingAnnotationView"
    private var hostingController: UIHostingController<AnyView>?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        collisionMode = .circle
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with ranking: PlaceRanking, dimmed: Bool) {
        let content = AnyView(
            PlaceAnnotationView(ranking: ranking)
                .opacity(dimmed ? 0.35 : 1.0)
        )
        if let host = hostingController {
            host.rootView = content
        } else {
            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.centerXAnchor.constraint(equalTo: centerXAnchor),
                host.view.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            hostingController = host
        }
        let size = hostingController!.view.intrinsicContentSize
        bounds = CGRect(origin: .zero, size: CGSize(
            width: max(size.width, 36),
            height: max(size.height, 36)
        ))
    }

    override func prepareForReuse() {
        super.prepareForReuse()
    }
}
