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
        .overlay(alignment: .topTrailing) {
            segmentPanel
        }
    }

    private var mapPins: [MapPin] {
        var pins: [MapPin] = []
        if let course = viewModel.course {
            if let first = course.coordinates.first {
                pins.append(MapPin(
                    coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                    title: "출발",
                    color: .systemGreen,
                    systemImage: "figure.run"
                ))
            }
            if let last = course.coordinates.last, course.coordinates.count > 1 {
                pins.append(MapPin(
                    coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                    title: "도착",
                    color: .systemRed,
                    systemImage: "flag.checkered"
                ))
            }
        }
        // tap 모드에서 pendingTapStart는 코스가 비어 있을 때만 설정됨 (최초 2탭 대기)
        if viewModel.interactionMode == .tap, let start = viewModel.pendingTapStart {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude),
                title: "출발",
                color: .systemGreen,
                systemImage: "figure.run"
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
            } else if let distanceText = viewModel.distanceText {
                Text(distanceText)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("coursePlanner.distance")
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

