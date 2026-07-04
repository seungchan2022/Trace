import MapKit
import SwiftUI

struct CoursePlannerPage: View {
    @State var viewModel: CoursePlannerPageViewModel
    @State private var cameraRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5666, longitude: 126.9784),
        latitudinalMeters: 500,
        longitudinalMeters: 500
    )
    @State private var currentStrokePoints: [CGPoint] = []
    @State var isSegmentPanelExpanded = false
    @State var panelContentHeight: CGFloat = 0
    @State var panelMaxListHeight: CGFloat = 300
    @State var panelAnchorColorKey: Int?
    // 접기 직전 "최신 근처를 보고 있었는가" — 재펼침 시 이 값이 true면 옛 앵커 대신 최신을 따라간다.
    // 기본값 true: 첫 펼침(앵커 없음)에서는 restoreScrollPosition의 fallback 분기가 이미 최신으로 보내므로 무해하다.
    @State var panelWasNearLatestAtCollapse = true
    @Environment(\.scenePhase) private var scenePhase

    private let cameraStateStore: CameraStateStore

    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol,
        cameraStateStore: CameraStateStore = CameraStateStore()
    ) {
        self.cameraStateStore = cameraStateStore
        _viewModel = State(initialValue: CoursePlannerPageViewModel(
            coursePlanningService: coursePlanningService,
            locationService: locationService,
            cameraStateStore: cameraStateStore
        ))
    }

    var body: some View {
        mapView
            .accessibilityIdentifier("coursePlanner.map")
            .safeAreaInset(edge: .top) {
                controls
            }
            .safeAreaInset(edge: .bottom) {
                statusPanel
            }
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
            .onChange(of: viewModel.selectedSegmentIndex) { _, newIndex in
                guard let newIndex,
                      let segments = viewModel.course?.segments,
                      newIndex < segments.count,
                      let region = regionFitting(segments[newIndex].coordinates) else { return }
                cameraRegion = region
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    saveCameraPosition()
                }
            }
            .alert("위치 권한이 필요합니다", isPresented: $viewModel.showLocationDeniedAlert) {
                Button("설정으로 이동") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("닫기", role: .cancel) {}
            }
    }

    private var mapView: some View {
        MapViewRepresentable(
            region: $cameraRegion,
            segments: viewModel.course?.segments ?? [],
            segmentColorKeys: viewModel.segmentColorKeys,
            pins: mapPins,
            selectedSegmentIndex: viewModel.selectedSegmentIndex,
            isDrawingMode: viewModel.isDrawingMode,
            waypoints: viewModel.waypointCoordinates.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            },
            onStrokeUpdate: { points in currentStrokePoints = points },
            onStrokeEnded: { stroke, startHit in Task { await viewModel.appendStroke(stroke, startPinHit: startHit) } },
            onMapTap: { coord, hitPin in Task { await viewModel.handleMapTap(at: coord, hitPin: hitPin) } },
            onPendingTap: { coord, hitPin in viewModel.pendingTapBegan(at: coord, hitPin: hitPin) },
            onPendingTapCancelled: { viewModel.pendingTapCancelled() }
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
                            latitudinalMeters: 500,
                            longitudinalMeters: 500
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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            panelMaxListHeight = height * 0.4
        }
        .overlay(alignment: .topTrailing) {
            segmentPanel
        }
    }

    private var mapPins: [MapPin] {
        var pins: [MapPin] = []
        if let course = viewModel.course {
            if viewModel.isClosedCourse, let first = course.coordinates.first {
                // 닫힌 코스: 출발·도착이 같은 지점 — 병합 핀 하나만
                pins.append(MapPin(
                    coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                    title: "출발/도착",
                    color: .systemGreen,
                    systemImage: "figure.run",
                    role: .merged
                ))
            } else {
                if let first = course.coordinates.first {
                    pins.append(MapPin(
                        coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                        title: "출발",
                        color: .systemGreen,
                        systemImage: "figure.run",
                        role: .start
                    ))
                }
                if let last = course.coordinates.last, course.coordinates.count > 1 {
                    pins.append(MapPin(
                        coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                        title: "도착",
                        color: .systemRed,
                        systemImage: "flag.checkered",
                        role: .end
                    ))
                }
            }
        }
        // tap 모드에서 pendingTapStart는 코스가 비어 있을 때만 설정됨 (최초 2탭 대기)
        if viewModel.interactionMode == .tap, let start = viewModel.pendingTapStart {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude),
                title: "출발",
                color: .systemGreen,
                systemImage: "figure.run",
                role: .pendingStart
            ))
        }
        // 판별 창 보류 중 임시 마커 — 확정이 수렴하는 모양(첫 탭=출발, 이후=도착)과 동일 (스펙 '임시 마커' 절)
        if viewModel.interactionMode == .tap, let pending = viewModel.pendingTapMarker {
            let isFirstPoint = viewModel.course == nil && viewModel.pendingTapStart == nil
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: pending.latitude, longitude: pending.longitude),
                title: isFirstPoint ? "출발" : "도착",
                color: isFirstPoint ? .systemGreen : .systemRed,
                systemImage: isFirstPoint ? "figure.run" : "flag.checkered",
                role: .pendingStart
            ))
        }
        return pins
    }

    private func saveCameraPosition() {
        cameraStateStore.save(
            latitude: cameraRegion.center.latitude,
            longitude: cameraRegion.center.longitude,
            latitudinalMeters: cameraRegion.span.latitudeDelta * 111_000,
            longitudinalMeters: cameraRegion.span.longitudeDelta * 111_000
                * cos(cameraRegion.center.latitude * .pi / 180)
        )
    }

    private func regionFitting(_ coordinates: [CourseCoordinate]) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.003),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.003)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isLoading {
                Text("경로 계산 중")
                    .accessibilityIdentifier("coursePlanner.loading")
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("coursePlanner.error")
            } else if let infoMessage = viewModel.infoMessage {
                Text(infoMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("coursePlanner.info")
            } else if let distanceText = viewModel.distanceText {
                HStack(spacing: 6) {
                    Text(distanceText)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("coursePlanner.distance")
                    if viewModel.roundTripHintVisible {
                        Text("· 출발핀을 탭하면 왕복 완성")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("coursePlanner.roundTripHint")
                    }
                }
            } else {
                Text(viewModel.isDrawingMode ? "경로를 그려주세요" : "지도에서 출발지를 선택하세요")
                    .accessibilityIdentifier("coursePlanner.prompt")
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }
}

#Preview {
    let container = DependencyContainer.uiTesting()
    CoursePlannerPage(
        coursePlanningService: container.coursePlanningService,
        locationService: container.locationService,
        cameraStateStore: container.cameraStateStore
    )
}

