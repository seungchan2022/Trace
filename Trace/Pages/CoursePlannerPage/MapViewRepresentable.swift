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

// MARK: - MapViewRepresentable

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var overlayCoordinates: [CLLocationCoordinate2D]
    var pins: [MapPin]
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

        // 1손가락 드로우 GR (초기엔 비활성)
        let drawGR = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDraw(_:))
        )
        drawGR.maximumNumberOfTouches = 1
        drawGR.isEnabled = false
        mapView.addGestureRecognizer(drawGR)
        context.coordinator.drawGestureRecognizer = drawGR

        // 2손가락 pan GR (그리기 모드에서 지도 이동, 초기엔 비활성)
        let twoFingerPanGR = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerPan(_:))
        )
        twoFingerPanGR.minimumNumberOfTouches = 2
        twoFingerPanGR.maximumNumberOfTouches = 2
        twoFingerPanGR.isEnabled = false
        mapView.addGestureRecognizer(twoFingerPanGR)
        context.coordinator.twoFingerPanGestureRecognizer = twoFingerPanGR

        // 핀치 GR (그리기 모드에서 줌, 초기엔 비활성)
        let pinchGR = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinchGR.isEnabled = false
        mapView.addGestureRecognizer(pinchGR)
        context.coordinator.pinchGestureRecognizer = pinchGR

        // 탭 GR
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

        // Camera: parent가 시작한 유의미한 이동만 반영 (무한루프 방지)
        let mapCenter = uiView.region.center
        let latDiff = abs(mapCenter.latitude - region.center.latitude)
        let lonDiff = abs(mapCenter.longitude - region.center.longitude)
        let spanDiff = abs(uiView.region.span.latitudeDelta - region.span.latitudeDelta)
        if latDiff > 0.0001 || lonDiff > 0.0001 || spanDiff > 0.0001 {
            uiView.setRegion(region, animated: true)
        }

        // Overlays: count + 첫/끝 좌표가 달라질 때만 교체
        let existingPolyline = uiView.overlays.compactMap { $0 as? MKPolyline }.first
        let needsOverlayUpdate: Bool = {
            guard let existingPolyline, existingPolyline.pointCount == overlayCoordinates.count,
                  !overlayCoordinates.isEmpty else {
                return (existingPolyline?.pointCount ?? 0) != overlayCoordinates.count
            }
            let pts = existingPolyline.points()
            let first = pts[0].coordinate
            let last = pts[existingPolyline.pointCount - 1].coordinate
            return abs(first.latitude - overlayCoordinates[0].latitude) > 0.00001 ||
                abs(last.latitude - overlayCoordinates[overlayCoordinates.count - 1].latitude) > 0.00001
        }()
        if needsOverlayUpdate {
            uiView.removeOverlays(uiView.overlays)
            if !overlayCoordinates.isEmpty {
                var coords = overlayCoordinates
                uiView.addOverlay(MKPolyline(coordinates: &coords, count: coords.count))
            }
        }

        // Annotations: 최대 2개, 변경 시 재구성
        let existing = uiView.annotations.filter { !($0 is MKUserLocation) }
            .compactMap { $0 as? ColoredPinAnnotation }
        let pinsChanged = existing.count != pins.count ||
            zip(existing, pins).contains { ann, pin in
                abs(ann.coordinate.latitude - pin.coordinate.latitude) > 0.00001 ||
                abs(ann.coordinate.longitude - pin.coordinate.longitude) > 0.00001
            }
        if pinsChanged {
            uiView.removeAnnotations(uiView.annotations.filter { !($0 is MKUserLocation) })
            for pin in pins {
                uiView.addAnnotation(ColoredPinAnnotation(
                    coordinate: pin.coordinate,
                    title: pin.title,
                    color: pin.color,
                    systemImage: pin.systemImage
                ))
            }
        }

        // 제스처 모드 동기화
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
}

// MARK: - Coordinator

extension MapViewRepresentable {
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable

        init(parent: MapViewRepresentable) {
            self.parent = parent
        }

        // MARK: Overlay

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 6
            return renderer
        }

        // MARK: Annotation

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
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

            // 두 번째 손가락이 들어오면 진행 중인 stroke 취소
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
