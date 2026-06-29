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
    }

    private var overlayCoordinates: [CLLocationCoordinate2D] {
        viewModel.course?.coordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        } ?? []
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
        // tap 모드에서 pendingTapStart는 course 유무와 무관하게 항상 표시
        if viewModel.interactionMode == .tap, let start = viewModel.pendingTapStart {
            let hasCourse = viewModel.course != nil
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude),
                title: hasCourse ? "연결점" : "출발",
                color: hasCourse ? .systemOrange : .systemGreen,
                systemImage: hasCourse ? "mappin.circle" : "figure.run"
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

