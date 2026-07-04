import MapKit
import SwiftUI

// MARK: - Supporting Types

struct MapPin: Equatable {
    let coordinate: CLLocationCoordinate2D
    let title: String
    let color: UIColor
    let systemImage: String
    let role: CoursePinRole

    static func == (lhs: MapPin, rhs: MapPin) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.title == rhs.title &&
            lhs.role == rhs.role   // 좌표가 같아도 스타일 전환(출발/도착 ↔ 병합)을 diff가 감지
    }
}

final class ColoredPinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let color: UIColor
    let systemImage: String
    let role: CoursePinRole

    init(coordinate: CLLocationCoordinate2D, title: String, color: UIColor, systemImage: String, role: CoursePinRole) {
        self.coordinate = coordinate
        self.title = title
        self.color = color
        self.systemImage = systemImage
        self.role = role
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

// 경유점(구간 경계) 마커 — annotation이 아니라 오버레이로 그린다.
// MapKit은 오버레이를 항상 애노테이션보다 아래에 그린다는 구조적 보장이 있어서,
// 거리 라벨(annotation)과의 z-order 경쟁(추가 순서·zPosition 둘 다 실기기에서 불안정했음) 없이
// 항상 라벨 아래에 위치한다 — 실기기 QA에서 두 방식 모두 재발해 오버레이 레이어로 옮김(2026-07-04).
final class WaypointDotsOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let points: [CLLocationCoordinate2D]

    init(points: [CLLocationCoordinate2D]) {
        self.points = points
        self.coordinate = points.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        if points.isEmpty {
            self.boundingMapRect = .null
        } else {
            let mapPoints = points.map { MKMapPoint($0) }
            let minX = mapPoints.map(\.x).min() ?? 0
            let maxX = mapPoints.map(\.x).max() ?? 0
            let minY = mapPoints.map(\.y).min() ?? 0
            let maxY = mapPoints.map(\.y).max() ?? 0
            let padding = 2000.0 // 점 반경을 어느 줌에서든 넉넉히 덮을 여유
            self.boundingMapRect = MKMapRect(
                x: minX - padding, y: minY - padding,
                width: (maxX - minX) + padding * 2, height: (maxY - minY) + padding * 2
            )
        }
    }
}

final class WaypointDotsRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let dotsOverlay = overlay as? WaypointDotsOverlay else { return }
        let radius: CGFloat = 5 / zoomScale
        let borderWidth: CGFloat = 2 / zoomScale
        for coordinate in dotsOverlay.points {
            let point = self.point(for: MKMapPoint(coordinate))
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.setFillColor(UIColor.white.cgColor)
            context.setStrokeColor(UIColor.systemGray.cgColor)
            context.setLineWidth(borderWidth)
            context.fillEllipse(in: rect)
            context.strokeEllipse(in: rect)
        }
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
    var waypoints: [CLLocationCoordinate2D]
    var onStrokeUpdate: ([CGPoint]) -> Void
    var onStrokeEnded: ([CourseCoordinate], CoursePinRole?) -> Void
    var onMapTap: ((CourseCoordinate, CoursePinRole?) -> Void)?
    var onPendingTap: ((CourseCoordinate, CoursePinRole?) -> Void)?
    var onPendingTapCancelled: (() -> Void)?

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
        twoFingerPanGR.delegate = context.coordinator
        mapView.addGestureRecognizer(twoFingerPanGR)
        context.coordinator.twoFingerPanGestureRecognizer = twoFingerPanGR

        let tapGR = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGR.isEnabled = !isDrawingMode
        mapView.addGestureRecognizer(tapGR)
        context.coordinator.tapGestureRecognizer = tapGR

        let touchObserver = TouchObserverGestureRecognizer()
        touchObserver.cancelsTouchesInView = false
        touchObserver.delaysTouchesBegan = false
        touchObserver.onTouchBegan = { [weak coordinator = context.coordinator, weak mapView] point in
            guard let coordinator, let mapView else { return }
            coordinator.observedTouchBegan(at: point, in: mapView)
        }
        touchObserver.isEnabled = !isDrawingMode
        touchObserver.delegate = context.coordinator
        mapView.addGestureRecognizer(touchObserver)
        context.coordinator.touchObserverRecognizer = touchObserver

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
            // 겹치는 경로는 표시 좌표만 옆으로 비켜 그린다 (도메인 좌표 불변).
            // 스냅샷 게이트 안이므로 세그먼트가 실제로 바뀔 때만 재계산된다.
            let displayCoordinates = OverlapOffsetResolver.displayCoordinates(
                segments: segments, colorKeys: segmentColorKeys
            )
            for (index, segment) in segments.enumerated() {
                var coords = displayCoordinates[index].map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                guard coords.count >= 2 else { continue }
                let colorKey = index < segmentColorKeys.count ? segmentColorKeys[index] : index
                let polyline = SegmentPolyline(coordinates: &coords, count: coords.count)
                polyline.segmentIndex = index
                polyline.colorKey = colorKey
                uiView.addOverlay(polyline)

                let annotation = SegmentDistanceAnnotation(
                    coordinate: midpointAlongPath(coords),
                    distanceText: String(format: "%.0fm", segment.distanceMeters),
                    color: SegmentPalette.color(at: colorKey)
                )
                uiView.addAnnotation(annotation)
            }
            if !waypoints.isEmpty {
                uiView.addOverlay(WaypointDotsOverlay(points: waypoints))
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

        let existing = uiView.annotations.compactMap { $0 as? ColoredPinAnnotation }
        let existingAsPins = existing.map {
            MapPin(coordinate: $0.coordinate, title: $0.title ?? "", color: $0.color, systemImage: $0.systemImage, role: $0.role)
        }
        let pinsChanged = existingAsPins.count != pins.count ||
            zip(existingAsPins, pins).contains { $0 != $1 }
        if pinsChanged {
            uiView.removeAnnotations(uiView.annotations.compactMap { $0 as? ColoredPinAnnotation })
            for pin in pins {
                uiView.addAnnotation(ColoredPinAnnotation(
                    coordinate: pin.coordinate,
                    title: pin.title,
                    color: pin.color,
                    systemImage: pin.systemImage,
                    role: pin.role
                ))
            }
        }

        let wasDrawing = context.coordinator.drawGestureRecognizer?.isEnabled ?? false
        if wasDrawing != isDrawingMode {
            uiView.isScrollEnabled = !isDrawingMode
            uiView.isPitchEnabled = !isDrawingMode
            uiView.isRotateEnabled = !isDrawingMode
            context.coordinator.drawGestureRecognizer?.isEnabled = isDrawingMode
            context.coordinator.twoFingerPanGestureRecognizer?.isEnabled = isDrawingMode
            context.coordinator.tapGestureRecognizer?.isEnabled = !isDrawingMode
            context.coordinator.touchObserverRecognizer?.isEnabled = !isDrawingMode
            context.coordinator.resetTapClassification(in: uiView)   // 판별 창 중 모드 전환 → 보류 취소
        }
    }

    private func configureRenderer(_ renderer: MKPolylineRenderer, segmentIndex: Int, colorKey: Int, selected: Int?) {
        renderer.strokeColor = SegmentPalette.color(at: colorKey)
        renderer.lineWidth = segmentIndex == selected ? 9 : 6
    }

    // 배열 인덱스 절반이 아니라 실제 누적 거리 절반 지점을 찾는다.
    // 라우팅 결과는 좌표 밀도가 균일하지 않아(커브에 촘촘, 직선에 듬성) 인덱스 기준으로는
    // 라벨이 경로 중간이 아니라 엉뚱한 곳(핀·경유점 근처 등)에 찍히는 문제가 있었다 (2026-07-04 실기기 확인).
    private func midpointAlongPath(_ coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard let first = coords.first else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        guard coords.count > 1 else { return first }

        var cumulative: [Double] = [0]
        for index in 1..<coords.count {
            let pointA = CLLocation(latitude: coords[index - 1].latitude, longitude: coords[index - 1].longitude)
            let pointB = CLLocation(latitude: coords[index].latitude, longitude: coords[index].longitude)
            cumulative.append(cumulative[index - 1] + pointA.distance(from: pointB))
        }

        let half = (cumulative.last ?? 0) / 2
        for index in 1..<cumulative.count {
            guard cumulative[index] >= half else { continue }
            let segStart = cumulative[index - 1]
            let segEnd = cumulative[index]
            let ratio = segEnd > segStart ? (half - segStart) / (segEnd - segStart) : 0
            return CLLocationCoordinate2D(
                latitude: coords[index - 1].latitude + (coords[index].latitude - coords[index - 1].latitude) * ratio,
                longitude: coords[index - 1].longitude + (coords[index].longitude - coords[index - 1].longitude) * ratio
            )
        }
        return coords[coords.count / 2]
    }
}

// MARK: - Coordinator

extension MapViewRepresentable {
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapViewRepresentable
        fileprivate var lastSegmentSnapshots: [SegmentSnapshot] = []
        var lastSelectedIndex: Int?
        static let mergedBadgeTag = 990

        init(parent: MapViewRepresentable) {
            self.parent = parent
        }

        // MARK: Overlay

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let dotsOverlay = overlay as? WaypointDotsOverlay {
                return WaypointDotsRenderer(overlay: dotsOverlay)
            }
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
            // 출발/도착 핀은 거리 라벨과 겹쳐도 MapKit 충돌 처리로 가려지면 안 됨(최대 2개뿐이라 성능 영향 없음)
            view.displayPriority = .required
            view.collisionMode = .none
            view.isEnabled = false
            view.subviews.filter { $0.tag == Self.mergedBadgeTag }.forEach { $0.removeFromSuperview() }
            if pin.role == .merged {
                let badge = UIImageView(image: UIImage(systemName: "flag.checkered"))
                badge.tag = Self.mergedBadgeTag
                badge.tintColor = .white
                badge.backgroundColor = .systemRed
                badge.layer.cornerRadius = 10
                badge.clipsToBounds = true
                badge.contentMode = .scaleAspectFit
                badge.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(badge)
                NSLayoutConstraint.activate([
                    badge.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 4),
                    badge.topAnchor.constraint(equalTo: view.topAnchor, constant: -6),
                    badge.widthAnchor.constraint(equalToConstant: 20),
                    badge.heightAnchor.constraint(equalToConstant: 20)
                ])
            }
            return view
        }

        // MARK: Camera

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            parent.region = mapView.region
        }

        // MARK: Gesture Delegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // 커스텀 두손가락 팬 ↔ 네이티브 두손가락 탭 줌아웃 경쟁 완화: 동시 인식 허용.
            // 탭 줌아웃은 이동량이 없어 팬 로직에 영향이 없고, 실제 팬 중에는 탭 줌아웃이 스스로 실패한다.
            // 터치 관찰자는 인식 전이가 없어 항상 무해 — 명시적으로 허용해 둔다.
            gestureRecognizer === twoFingerPanGestureRecognizer
                || gestureRecognizer === touchObserverRecognizer
        }

        // MARK: Gesture State

        weak var drawGestureRecognizer: UIPanGestureRecognizer?
        weak var twoFingerPanGestureRecognizer: UIPanGestureRecognizer?
        weak var tapGestureRecognizer: UITapGestureRecognizer?
        private var currentStrokePoints: [CGPoint] = []
        private var currentStrokeCoords: [CourseCoordinate] = []
        private var panStartCenter: CLLocationCoordinate2D?
        // 그리기 시작 시점(.began)에 잡은 핀 히트 — 실거리와 무관한 화면 24pt 근접 판정용
        private var strokeStartPinRole: CoursePinRole?

        // MARK: Draw

        @objc func handleDraw(_ recognizer: UIPanGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }

            if recognizer.numberOfTouches > 1 {
                currentStrokePoints = []
                currentStrokeCoords = []
                strokeStartPinRole = nil
                parent.onStrokeUpdate([])
                recognizer.state = .cancelled
                return
            }

            let point = recognizer.location(in: mapView)
            let clCoord = mapView.convert(point, toCoordinateFrom: mapView)
            let coord = CourseCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude)

            if recognizer.state == .began {
                let hit = pinHit(at: point, in: mapView)
                strokeStartPinRole = hit == .pendingStart ? nil : hit
            }

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
                let startHit = strokeStartPinRole
                strokeStartPinRole = nil
                parent.onStrokeUpdate([])
                if stroke.count >= 2 {
                    parent.onStrokeEnded(stroke, startHit)
                }
            default:
                break
            }
        }

        // MARK: Tap Classification

        let tapClassifier = TapClassifier()
        weak var touchObserverRecognizer: TouchObserverGestureRecognizer?
        private var confirmWorkItem: DispatchWorkItem?
        // 보류 시점에 좌표·핀 히트를 동봉해 확정 시 그대로 사용 (판별 창 중 지도 이동에 안전)
        private var pendingCoordinate: CourseCoordinate?
        private var pendingPinRole: CoursePinRole?

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            let point = recognizer.location(in: mapView)
            process(tapClassifier.tapEnded(at: point, time: CACurrentMediaTime()), in: mapView)
        }

        func observedTouchBegan(at point: CGPoint, in mapView: MKMapView) {
            process(tapClassifier.touchBegan(at: point, time: CACurrentMediaTime()), in: mapView)
        }

        func resetTapClassification(in mapView: MKMapView) {
            process(tapClassifier.reset(), in: mapView)
        }

        private func process(_ events: [TapClassifierEvent], in mapView: MKMapView) {
            for event in events {
                switch event {
                case .pending(let point):
                    let clCoord = mapView.convert(point, toCoordinateFrom: mapView)
                    pendingCoordinate = CourseCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude)
                    pendingPinRole = pinHit(at: point, in: mapView)
                    if let coordinate = pendingCoordinate {
                        parent.onPendingTap?(coordinate, pendingPinRole)
                    }
                    scheduleConfirm(in: mapView)
                case .cancelled:
                    confirmWorkItem?.cancel()
                    confirmWorkItem = nil
                    pendingCoordinate = nil
                    pendingPinRole = nil
                    parent.onPendingTapCancelled?()
                case .confirmed:
                    confirmWorkItem?.cancel()
                    confirmWorkItem = nil
                    guard let coordinate = pendingCoordinate else { break }
                    let role = pendingPinRole
                    pendingCoordinate = nil
                    pendingPinRole = nil
                    parent.onMapTap?(coordinate, role)
                }
            }
        }

        private func scheduleConfirm(in mapView: MKMapView) {
            confirmWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.process(self.tapClassifier.windowElapsed(time: CACurrentMediaTime()), in: mapView)
            }
            confirmWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + tapClassifier.window, execute: item)
        }

        // 화면 포인트 기반 핀 히트 — 지도거리(줌 종속)가 아니라 화면 24pt 반경으로 판정한다.
        private func pinHit(at point: CGPoint, in mapView: MKMapView) -> CoursePinRole? {
            let hitRadius: CGFloat = 24
            var best: (role: CoursePinRole, distance: CGFloat)?
            for annotation in mapView.annotations.compactMap({ $0 as? ColoredPinAnnotation }) {
                let pinPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
                let distance = hypot(pinPoint.x - point.x, pinPoint.y - point.y)
                if distance <= hitRadius, distance < (best?.distance ?? .infinity) {
                    best = (annotation.role, distance)
                }
            }
            return best?.role
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
    }
}

// MARK: - TouchObserverGestureRecognizer

// 원시 터치 다운만 관찰해 탭 판별기에 공급한다. 절대 인식 상태로 전이하지 않으므로
// 네이티브 줌을 포함한 다른 인식기를 방해하지 않는다 (스펙 '구조' 절: 관찰 필수 근거).
final class TouchObserverGestureRecognizer: UIGestureRecognizer {
    var onTouchBegan: ((CGPoint) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        onTouchBegan?(touch.location(in: view))
    }
}
