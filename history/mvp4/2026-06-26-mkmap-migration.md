# mkmap-migration 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SwiftUI `Map`을 `MKMapView(UIViewRepresentable)`로 교체해 그리기 중에도 2손가락으로 지도를 이동할 수 있게 한다.

**Architecture:** `MapViewRepresentable`(신규)이 MKMapView를 UIViewRepresentable로 래핑하고 Coordinator가 MKMapViewDelegate를 구현한다. CoursePlannerPage는 기존 Map 블록을 MapViewRepresentable로 교체하며, ViewModel과 Domain/Infrastructure 레이어는 일절 변경하지 않는다.

**Tech Stack:** Swift, SwiftUI, UIKit(MKMapView, UIPanGestureRecognizer, UITapGestureRecognizer), MapKit

## Global Constraints

- iOS 17.0+ 최소 지원, Swift 6 스타일 `async`/`await`
- ViewModel은 MapKit을 import하지 않는다 — MapKit 타입은 Page 레이어에서만 사용
- ViewModel API(`appendStroke`, `handleMapTap`, `recenterToCurrentLocation`)는 변경 없음
- 기존 `CoursePlannerPageViewModel`, `DrawnPathSampler`, `StrokeDirectionResolver`, `MapKitCoursePlanningService`를 수정하지 않음
- `CameraStateStore` 저장/복원 로직 유지
- 1손가락=그리기, 2손가락=지도 이동/줌

---

## 파일 구조

| 역할 | 파일 | 변경 |
|------|------|------|
| MKMapView 래퍼 | `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` | 신규 |
| 페이지 뷰 | `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` | 수정 |

---

## Task 1: MapViewRepresentable — 코어 (카메라 + 오버레이 + 어노테이션)

**Files:**
- Create: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`

**Interfaces:**
- Produces:
  - `struct MapPin: Equatable` — 핀 데이터 전달용 값 타입
  - `struct MapViewRepresentable: UIViewRepresentable` — `region`, `overlayCoordinates`, `pins` 파라미터 포함 (제스처 콜백은 Task 2에서 추가)
  - `final class ColoredPinAnnotation: NSObject, MKAnnotation` — 색상 정보를 담는 어노테이션

- [ ] **Step 1: 파일 생성 — 타입 정의와 기본 UIViewRepresentable 골격**

`Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` 에 아래를 작성:

```swift
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

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Camera: parent가 시작한 유의미한 이동만 반영 (무한루프 방지)
        let mapCenter = uiView.region.center
        let latDiff = abs(mapCenter.latitude - region.center.latitude)
        let lonDiff = abs(mapCenter.longitude - region.center.longitude)
        if latDiff > 0.0001 || lonDiff > 0.0001 {
            uiView.setRegion(region, animated: true)
        }

        // Overlays: 좌표 수가 달라질 때만 교체
        let existingCount = uiView.overlays.compactMap { $0 as? MKPolyline }.first?.pointCount ?? 0
        if existingCount != overlayCoordinates.count {
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
                abs(ann.coordinate.latitude - pin.coordinate.latitude) > 0.00001
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
    }
}
```

- [ ] **Step 2: CoursePlannerPage.swift — import 추가 확인**

`CoursePlannerPage.swift` 상단에 `import MapKit` 이 이미 있는지 확인. 없으면 추가.

- [ ] **Step 3: 빌드 확인 (시뮬레이터 빌드만)**

```
Xcode → Product → Build (⌘B)
```
Expected: 빌드 성공, 경고 없음.

- [ ] **Step 4: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift
git commit -m "feat(mkmap-migration): MapViewRepresentable 코어 — 카메라/오버레이/어노테이션"
```

---

## Task 2: MapViewRepresentable — 제스처 (드로우 + 탭)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`

**Interfaces:**
- Consumes: Task 1의 `MapViewRepresentable`, `Coordinator`
- Produces:
  - `MapViewRepresentable` 에 추가된 파라미터: `isDrawingMode: Bool`, `onStrokeUpdate: ([CGPoint]) -> Void`, `onStrokeEnded: ([CourseCoordinate]) -> Void`, `onMapTap: ((CourseCoordinate) -> Void)?`
  - `Coordinator` 에 추가: `drawGestureRecognizer`, `tapGestureRecognizer`, `handleDraw(_:)`, `handleTap(_:)`

- [ ] **Step 1: MapViewRepresentable에 제스처 파라미터 추가**

`MapViewRepresentable` struct의 저장 프로퍼티 블록을 아래로 교체:

```swift
struct MapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var overlayCoordinates: [CLLocationCoordinate2D]
    var pins: [MapPin]
    var isDrawingMode: Bool
    var onStrokeUpdate: ([CGPoint]) -> Void
    var onStrokeEnded: ([CourseCoordinate]) -> Void
    var onMapTap: ((CourseCoordinate) -> Void)?
    // makeCoordinator, makeUIView, updateUIView는 아래에서 수정
```

- [ ] **Step 2: makeUIView에 제스처 설정 추가**

`makeUIView` 함수 전체를 아래로 교체:

```swift
func makeUIView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator
    mapView.showsUserLocation = true
    mapView.setRegion(region, animated: false)

    // MKMapView 기본 1손가락 팬을 2손가락으로 변경 → 1손가락 드로우와 충돌 방지
    for gr in mapView.gestureRecognizers ?? [] {
        if let pan = gr as? UIPanGestureRecognizer {
            pan.minimumNumberOfTouches = 2
        }
    }

    // 드로우 제스처: 1손가락 최대, 초기엔 비활성화
    let drawGR = UIPanGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleDraw(_:))
    )
    drawGR.maximumNumberOfTouches = 1
    drawGR.isEnabled = false
    mapView.addGestureRecognizer(drawGR)
    context.coordinator.drawGestureRecognizer = drawGR

    // 탭 제스처
    let tapGR = UITapGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleTap(_:))
    )
    mapView.addGestureRecognizer(tapGR)
    context.coordinator.tapGestureRecognizer = tapGR

    return mapView
}
```

- [ ] **Step 3: updateUIView에 제스처 모드 동기화 추가**

`updateUIView` 함수 끝에 아래 두 줄 추가 (Annotations 블록 이후):

```swift
// 제스처 모드 동기화
context.coordinator.drawGestureRecognizer?.isEnabled = isDrawingMode
context.coordinator.tapGestureRecognizer?.isEnabled = !isDrawingMode
```

- [ ] **Step 4: Coordinator에 제스처 핸들러 추가**

`Coordinator` 클래스에 아래를 추가 (Camera 섹션 뒤):

```swift
// MARK: Gesture State

weak var drawGestureRecognizer: UIPanGestureRecognizer?
weak var tapGestureRecognizer: UITapGestureRecognizer?
private var currentStrokePoints: [CGPoint] = []
private var currentStrokeCoords: [CourseCoordinate] = []

// MARK: Draw

@objc func handleDraw(_ recognizer: UIPanGestureRecognizer) {
    guard let mapView = recognizer.view as? MKMapView else { return }
    let point = recognizer.location(in: mapView)
    let clCoord = mapView.convert(point, toCoordinateFrom: mapView)
    let coord = CourseCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude)

    switch recognizer.state {
    case .began, .changed:
        currentStrokePoints.append(point)
        currentStrokeCoords.append(coord)
        parent.onStrokeUpdate(currentStrokePoints)
    case .ended, .cancelled:
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
```

- [ ] **Step 5: 빌드 확인**

```
Xcode → Product → Build (⌘B)
```
Expected: 빌드 성공.

- [ ] **Step 6: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift
git commit -m "feat(mkmap-migration): 제스처 추가 — 1손가락 드로우 / 2손가락 지도 이동"
```

---

## Task 3: CoursePlannerPage 통합

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`

**Interfaces:**
- Consumes: Task 2의 `MapViewRepresentable`, `MapPin`

- [ ] **Step 1: @State 프로퍼티 교체**

`CoursePlannerPage` 의 `@State` 블록을 아래로 교체 (기존 `cameraPosition`, `currentStroke`, `currentStrokePoints`, `lastCameraRegion` 제거 후 대체):

```swift
@State private var cameraRegion: MKCoordinateRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 37.5666, longitude: 126.9784),
    latitudinalMeters: 500,
    longitudinalMeters: 500
)
@State private var currentStrokePoints: [CGPoint] = []
```

- [ ] **Step 2: mapView computed property 교체**

기존 `private var mapView: some View` 전체를 아래로 교체:

```swift
private var mapView: some View {
    MapViewRepresentable(
        region: $cameraRegion,
        overlayCoordinates: overlayCoordinates,
        pins: mapPins,
        isDrawingMode: viewModel.isDrawingMode,
        onStrokeUpdate: { points in currentStrokePoints = points },
        onStrokeEnded: { stroke in Task { await viewModel.appendStroke(stroke) } },
        onMapTap: { coord in Task { await viewModel.handleMapTap(at: coord) } }
    )
    .overlay {
        Canvas { context, _ in
            guard currentStrokePoints.count > 1 else { return }
            var path = Path()
            path.addLines(currentStrokePoints)
            context.stroke(path, with: .color(.orange), lineWidth: 4)
        }
        .allowsHitTesting(false)
    }
    .overlay(alignment: .bottomTrailing) {
        Button {
            Task {
                if let location = await viewModel.recenterToCurrentLocation() {
                    cameraRegion = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: location.latitude,
                            longitude: location.longitude
                        ),
                        latitudinalMeters: 100,
                        longitudinalMeters: 100
                    )
                }
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.title2)
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .padding()
    }
}
```

- [ ] **Step 3: 헬퍼 computed property 추가**

`CoursePlannerPage` 에 아래 두 computed property를 추가 (어디든 `private var` 블록):

```swift
private var overlayCoordinates: [CLLocationCoordinate2D] {
    viewModel.course?.coordinates.map {
        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
    } ?? []
}

private var mapPins: [MapPin] {
    var pins: [MapPin] = []
    if viewModel.interactionMode == .tap {
        if let start = viewModel.startCoordinate {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude),
                title: "출발",
                color: .systemGreen,
                systemImage: "figure.run"
            ))
        }
        if let destination = viewModel.destinationCoordinate {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude),
                title: "도착",
                color: .systemRed,
                systemImage: "flag.checkered"
            ))
        }
    } else if viewModel.interactionMode == .draw, let course = viewModel.course {
        if let first = course.coordinates.first {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                title: "출발",
                color: .systemGreen,
                systemImage: "figure.run"
            ))
        }
        if let last = course.coordinates.last {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                title: "도착",
                color: .systemRed,
                systemImage: "flag.checkered"
            ))
        }
    }
    return pins
}
```

- [ ] **Step 4: .task 블록 카메라 복원 코드 수정**

기존 `.task` 블록의 카메라 복원 로직을 아래로 교체:

```swift
.task {
    if let bounds = cameraStateStore.restore() {
        cameraRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.latitude, longitude: bounds.longitude),
            latitudinalMeters: bounds.latitudinalMeters,
            longitudinalMeters: bounds.longitudinalMeters
        )
    }

    await viewModel.bootstrapLocation()

    if let center = viewModel.initialCameraCoordinate {
        cameraRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
    }
}
```

- [ ] **Step 5: saveCameraPosition() 수정**

기존 `saveCameraPosition()` 함수 전체를 아래로 교체:

```swift
private func saveCameraPosition() {
    cameraStateStore.save(
        latitude: cameraRegion.center.latitude,
        longitude: cameraRegion.center.longitude,
        latitudinalMeters: cameraRegion.span.latitudeDelta * 111_000,
        longitudinalMeters: cameraRegion.span.longitudeDelta * 111_000
            * cos(cameraRegion.center.latitude * .pi / 180)
    )
}
```

- [ ] **Step 6: 기존 private extension 확인**

`CoursePlannerPage.swift` 하단의 `private extension CLLocationCoordinate2D`와 `private extension CourseCoordinate`는 이제 사용하지 않으므로 삭제.

- [ ] **Step 7: 빌드 확인**

```
Xcode → Product → Build (⌘B)
```
Expected: 빌드 성공, 경고 없음.

- [ ] **Step 8: 시뮬레이터 수동 검증 체크리스트**

시뮬레이터 실행 후 순서대로 확인:

| 항목 | 통과 기준 |
|------|-----------|
| 지도 로드 | 시뮬레이터 위치 부근 지도 표시 |
| 파란 현위치 점 | 시뮬레이터 기본 위치에 파란 점 표시 |
| 탭 모드 1손가락 이동 | 탭 모드에서 1손가락 드래그 시 지도 이동 |
| 탭 모드 핀 | 지도 탭 두 번 → 녹색 출발 핀 + 빨강 도착 핀 표시 |
| 경로 폴리라인 | 핀 두 개 찍은 후 파란 폴리라인 표시 |
| 그리기 모드 진입 | 그리기 모드 토글 후 UI 상태 정상 |
| 1손가락 드로우 | 그리기 모드에서 1손가락 드래그 시 주황 프리뷰 + 경로 계산 |
| 2손가락 지도 이동 | 그리기 모드에서 2손가락 드래그 시 지도 이동 |
| 내 위치 버튼 | 내 위치 버튼 탭 시 카메라 이동 |
| 카메라 복원 | 앱 백그라운드 후 재실행 시 이전 위치로 복원 |

- [ ] **Step 9: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift
git commit -m "feat(mkmap-migration): CoursePlannerPage Map→MapViewRepresentable 통합"
```
