import MapKit
import SwiftUI

// MARK: - Supporting Types

struct MapPin: Equatable {
    let coordinate: CLLocationCoordinate2D
    let title: String
    let color: UIColor
    let systemImage: String

    static func == (lhs: MapPin, rhs: MapPin) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.title == rhs.title
    }
}

final class ColoredPinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let color: UIColor
    let systemImage: String

    init(coordinate: CLLocationCoordinate2D, title: String, color: UIColor, systemImage: String) {
        self.coordinate = coordinate
        self.title = title
        self.color = color
        self.systemImage = systemImage
    }
}

final class SegmentPolyline: MKPolyline {
    var segmentIndex: Int = 0
    // segmentIndex는 배열상 위치(선택 하이라이트 매칭용), colorKey는 attach 생성 순서(색상 identity, prepend에도 안정적)
    var colorKey: Int = 0
}

final class SegmentDistanceAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let distanceText: String
    let color: UIColor

    init(coordinate: CLLocationCoordinate2D, distanceText: String, color: UIColor) {
        self.coordinate = coordinate
        self.distanceText = distanceText
        self.color = color
    }
}

final class SegmentDistanceAnnotationView: MKAnnotationView {
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        addSubview(label)
        canShowCallout = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, color: UIColor) {
        label.text = " \(text) "
        label.backgroundColor = color
        label.sizeToFit()
        bounds = label.bounds
        centerOffset = .zero
    }
}

fileprivate struct SegmentSnapshot: Equatable {
    let coordinateCount: Int
    let first: CLLocationCoordinate2D?
    let last: CLLocationCoordinate2D?

    static func == (lhs: SegmentSnapshot, rhs: SegmentSnapshot) -> Bool {
        guard lhs.coordinateCount == rhs.coordinateCount else { return false }
        switch (lhs.first, rhs.first, lhs.last, rhs.last) {
        case (nil, nil, nil, nil): return true
        case let (lf?, rf?, ll?, rl?):
            return abs(lf.latitude - rf.latitude) < 0.00001 &&
                abs(ll.latitude - rl.latitude) < 0.00001
        default: return false
        }
    }
}

// MARK: - MapViewRepresentable

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var segments: [CourseSegment]
    // segments와 같은 순서로 정렬된 attach 생성 순번(색상 identity)
    var segmentColorKeys: [Int]
    var pins: [MapPin]
    var selectedSegmentIndex: Int?
    var isDrawingMode: Bool
    var onStrokeUpdate: ([CGPoint]) -> Void
    var onStrokeEnded: ([CourseCoordinate]) -> Void
    var onMapTap: ((CourseCoordinate) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.setRegion(region, animated: false)

        let drawGR = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDraw(_:))
        )
        drawGR.maximumNumberOfTouches = 1
        drawGR.isEnabled = false
        mapView.addGestureRecognizer(drawGR)
        context.coordinator.drawGestureRecognizer = drawGR

        let twoFingerPanGR = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerPan(_:))
        )
        twoFingerPanGR.minimumNumberOfTouches = 2
        twoFingerPanGR.maximumNumberOfTouches = 2
        twoFingerPanGR.isEnabled = false
        mapView.addGestureRecognizer(twoFingerPanGR)
        context.coordinator.twoFingerPanGestureRecognizer = twoFingerPanGR

        let pinchGR = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinchGR.isEnabled = false
        mapView.addGestureRecognizer(pinchGR)
        context.coordinator.pinchGestureRecognizer = pinchGR

        let tapGR = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGR.isEnabled = !isDrawingMode
        mapView.addGestureRecognizer(tapGR)
        context.coordinator.tapGestureRecognizer = tapGR

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self

        let mapCenter = uiView.region.center
        let latDiff = abs(mapCenter.latitude - region.center.latitude)
        let lonDiff = abs(mapCenter.longitude - region.center.longitude)
        let spanDiff = abs(uiView.region.span.latitudeDelta - region.span.latitudeDelta)
        if latDiff > 0.0001 || lonDiff > 0.0001 || spanDiff > 0.0001 {
            uiView.setRegion(region, animated: true)
        }

        let currentSnapshots = segments.map {
            SegmentSnapshot(
                coordinateCount: $0.coordinates.count,
                first: $0.coordinates.first.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
                last: $0.coordinates.last.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            )
        }
        if context.coordinator.lastSegmentSnapshots != currentSnapshots {
            uiView.removeOverlays(uiView.overlays)
            uiView.removeAnnotations(uiView.annotations.filter { $0 is SegmentDistanceAnnotation })
            for (index, segment) in segments.enumerated() {
                var coords = segment.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                guard coords.count >= 2 else { continue }
                let colorKey = index < segmentColorKeys.count ? segmentColorKeys[index] : index
                let polyline = SegmentPolyline(coordinates: &coords, count: coords.count)
                polyline.segmentIndex = index
                polyline.colorKey = colorKey
                uiView.addOverlay(polyline)

                let midIndex = coords.count / 2
                let annotation = SegmentDistanceAnnotation(
                    coordinate: coords[midIndex],
                    distanceText: String(format: "%.0fm", segment.distanceMeters),
                    color: SegmentPalette.color(at: colorKey)
                )
                uiView.addAnnotation(annotation)
            }
            context.coordinator.lastSegmentSnapshots = currentSnapshots
        }

        if context.coordinator.lastSelectedIndex != selectedSegmentIndex {
            context.coordinator.lastSelectedIndex = selectedSegmentIndex
            for overlay in uiView.overlays {
                guard let polyline = overlay as? SegmentPolyline,
                      let renderer = uiView.renderer(for: polyline) as? MKPolylineRenderer else { continue }
                configureRenderer(renderer, segmentIndex: polyline.segmentIndex, colorKey: polyline.colorKey, selected: selectedSegmentIndex)
                renderer.setNeedsDisplay()
            }
        }

        let existing = uiView.annotations.filter { !($0 is MKUserLocation) }
            .compactMap { $0 as? ColoredPinAnnotation }
        let pinsChanged = existing.count != pins.count ||
            zip(existing, pins).contains { ann, pin in
                abs(ann.coordinate.latitude - pin.coordinate.latitude) > 0.00001 ||
                abs(ann.coordinate.longitude - pin.coordinate.longitude) > 0.00001
            }
        if pinsChanged {
            uiView.removeAnnotations(uiView.annotations.compactMap { $0 as? ColoredPinAnnotation })
            for pin in pins {
                uiView.addAnnotation(ColoredPinAnnotation(
                    coordinate: pin.coordinate,
                    title: pin.title,
                    color: pin.color,
                    systemImage: pin.systemImage
                ))
            }
        }

        let wasDrawing = context.coordinator.drawGestureRecognizer?.isEnabled ?? false
        if wasDrawing != isDrawingMode {
            uiView.isScrollEnabled = !isDrawingMode
            uiView.isZoomEnabled = !isDrawingMode
            uiView.isPitchEnabled = !isDrawingMode
            uiView.isRotateEnabled = !isDrawingMode
            context.coordinator.drawGestureRecognizer?.isEnabled = isDrawingMode
            context.coordinator.twoFingerPanGestureRecognizer?.isEnabled = isDrawingMode
            context.coordinator.pinchGestureRecognizer?.isEnabled = isDrawingMode
            context.coordinator.tapGestureRecognizer?.isEnabled = !isDrawingMode
        }
    }

    private func configureRenderer(_ renderer: MKPolylineRenderer, segmentIndex: Int, colorKey: Int, selected: Int?) {
        renderer.strokeColor = SegmentPalette.color(at: colorKey)
        renderer.lineWidth = segmentIndex == selected ? 9 : 6
    }
}

// MARK: - Coordinator

extension MapViewRepresentable {
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        fileprivate var lastSegmentSnapshots: [SegmentSnapshot] = []
        var lastSelectedIndex: Int?

        init(parent: MapViewRepresentable) {
            self.parent = parent
        }

        // MARK: Overlay

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? SegmentPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            parent.configureRenderer(renderer, segmentIndex: polyline.segmentIndex, colorKey: polyline.colorKey, selected: parent.selectedSegmentIndex)
            return renderer
        }

        // MARK: Annotation

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let distanceAnnotation = annotation as? SegmentDistanceAnnotation {
                let identifier = "segmentDistance"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? SegmentDistanceAnnotationView
                    ?? SegmentDistanceAnnotationView(annotation: distanceAnnotation, reuseIdentifier: identifier)
                view.annotation = distanceAnnotation
                view.configure(text: distanceAnnotation.distanceText, color: distanceAnnotation.color)
                return view
            }
            guard let pin = annotation as? ColoredPinAnnotation else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "coloredPin")
            view.markerTintColor = pin.color
            view.glyphImage = UIImage(systemName: pin.systemImage)
            return view
        }

        // MARK: Camera

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            parent.region = mapView.region
        }

        // MARK: Gesture State

        weak var drawGestureRecognizer: UIPanGestureRecognizer?
        weak var twoFingerPanGestureRecognizer: UIPanGestureRecognizer?
        weak var pinchGestureRecognizer: UIPinchGestureRecognizer?
        weak var tapGestureRecognizer: UITapGestureRecognizer?
        private var currentStrokePoints: [CGPoint] = []
        private var currentStrokeCoords: [CourseCoordinate] = []
        private var panStartCenter: CLLocationCoordinate2D?
        private var pinchStartSpan: MKCoordinateSpan?
        private var pinchStartScale: CGFloat = 1.0

        // MARK: Draw

        @objc func handleDraw(_ recognizer: UIPanGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }

            if recognizer.numberOfTouches > 1 {
                currentStrokePoints = []
                currentStrokeCoords = []
                parent.onStrokeUpdate([])
                recognizer.state = .cancelled
                return
            }

            let point = recognizer.location(in: mapView)
            let clCoord = mapView.convert(point, toCoordinateFrom: mapView)
            let coord = CourseCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude)

            switch recognizer.state {
            case .began, .changed:
                currentStrokePoints.append(point)
                currentStrokeCoords.append(coord)
                parent.onStrokeUpdate(currentStrokePoints)
            case .ended, .cancelled:
                currentStrokePoints.append(point)
                currentStrokeCoords.append(coord)
                let stroke = currentStrokeCoords
                currentStrokePoints = []
                currentStrokeCoords = []
                parent.onStrokeUpdate([])
                if stroke.count >= 2 {
                    parent.onStrokeEnded(stroke)
                }
            default:
                break
            }
        }

        // MARK: Tap

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            let point = recognizer.location(in: mapView)
            let clCoord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onMapTap?(CourseCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude))
        }

        // MARK: Two-Finger Pan

        @objc func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            switch recognizer.state {
            case .began:
                panStartCenter = mapView.region.center
            case .changed:
                guard let startCenter = panStartCenter else { return }
                let translation = recognizer.translation(in: mapView)
                let region = mapView.region
                let latPerPoint = region.span.latitudeDelta / mapView.bounds.height
                let lonPerPoint = region.span.longitudeDelta / mapView.bounds.width
                let newCenter = CLLocationCoordinate2D(
                    latitude: startCenter.latitude + translation.y * latPerPoint,
                    longitude: startCenter.longitude - translation.x * lonPerPoint
                )
                let newRegion = MKCoordinateRegion(center: newCenter, span: region.span)
                mapView.setRegion(newRegion, animated: false)
            case .ended, .cancelled:
                panStartCenter = nil
            default:
                break
            }
        }

        // MARK: Pinch

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            switch recognizer.state {
            case .began:
                pinchStartSpan = mapView.region.span
                pinchStartScale = recognizer.scale
            case .changed:
                guard let startSpan = pinchStartSpan else { return }
                let scaleDelta = pinchStartScale / recognizer.scale
                let newSpan = MKCoordinateSpan(
                    latitudeDelta: min(max(startSpan.latitudeDelta * scaleDelta, 0.001), 100),
                    longitudeDelta: min(max(startSpan.longitudeDelta * scaleDelta, 0.001), 100)
                )
                let newRegion = MKCoordinateRegion(center: mapView.region.center, span: newSpan)
                mapView.setRegion(newRegion, animated: false)
            case .ended, .cancelled:
                pinchStartSpan = nil
            default:
                break
            }
        }
    }
}
