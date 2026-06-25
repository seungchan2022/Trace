import MapKit
import SwiftUI

struct CoursePlannerPage: View {
    @State var viewModel: CoursePlannerPageViewModel
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5666, longitude: 126.9784),
        latitudinalMeters: 500,
        longitudinalMeters: 500
    ))
    @State private var currentStroke: [CourseCoordinate] = []
    @State private var currentStrokePoints: [CGPoint] = []
    @State private var lastCameraRegion: MKCoordinateRegion?
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
                // 저장된 카메라 복원 (즉시, 점프 없음)
                if let bounds = cameraStateStore.restore() {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: bounds.latitude, longitude: bounds.longitude),
                        latitudinalMeters: bounds.latitudinalMeters,
                        longitudinalMeters: bounds.longitudinalMeters
                    ))
                }

                await viewModel.bootstrapLocation()

                // 저장된 카메라가 없었던 경우(첫 실행)에만 위치로 이동
                if let center = viewModel.initialCameraCoordinate {
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                            latitudinalMeters: 500,
                            longitudinalMeters: 500
                        ))
                    }
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
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: viewModel.isDrawingMode ? [] : .all) {
                UserAnnotation()

                if let course = viewModel.course {
                    MapPolyline(coordinates: course.coordinates.map(CLLocationCoordinate2D.init))
                        .stroke(.blue, lineWidth: 6)
                }

                // 탭 모드: startCoordinate/destinationCoordinate 기반
                if viewModel.interactionMode == .tap {
                    if let start = viewModel.startCoordinate {
                        Marker("출발", systemImage: "figure.run", coordinate: CLLocationCoordinate2D(start))
                            .tint(.green)
                    }
                    if let destination = viewModel.destinationCoordinate {
                        Marker("도착", systemImage: "flag.checkered", coordinate: CLLocationCoordinate2D(destination))
                            .tint(.red)
                    }
                }

                // 그리기 모드: course의 첫/끝 좌표 기반
                if viewModel.interactionMode == .draw, let course = viewModel.course,
                   let first = course.coordinates.first, let last = course.coordinates.last {
                    Marker("출발", systemImage: "figure.run", coordinate: CLLocationCoordinate2D(first))
                        .tint(.green)
                    Marker("도착", systemImage: "flag.checkered", coordinate: CLLocationCoordinate2D(last))
                        .tint(.red)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                lastCameraRegion = context.region
            }
            .overlay {
                Canvas { context, _ in
                    guard currentStrokePoints.count > 1 else { return }
                    var path = Path()
                    path.addLines(currentStrokePoints)
                    context.stroke(path, with: .color(.orange), lineWidth: 4)
                }
                .contentShape(Rectangle())
                .allowsHitTesting(viewModel.isDrawingMode)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            currentStrokePoints.append(value.location)
                            if let coord = proxy.convert(value.location, from: .local) {
                                currentStroke.append(CourseCoordinate(coord))
                            }
                        }
                        .onEnded { _ in
                            let stroke = currentStroke
                            currentStroke = []
                            currentStrokePoints = []
                            Task { await viewModel.appendStroke(stroke) }
                        }
                )
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    Task {
                        if let location = await viewModel.recenterToCurrentLocation() {
                            cameraPosition = .region(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                                latitudinalMeters: 100,
                                longitudinalMeters: 100
                            ))
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
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard viewModel.isDrawingMode == false else { return }
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        Task {
                            await viewModel.handleMapTap(at: CourseCoordinate(coordinate))
                        }
                    }
            )
        }
    }

    private func saveCameraPosition() {
        guard let region = lastCameraRegion else { return }
        cameraStateStore.save(
            latitude: region.center.latitude,
            longitude: region.center.longitude,
            latitudinalMeters: region.span.latitudeDelta * 111_000,
            longitudinalMeters: region.span.longitudeDelta * 111_000 * cos(region.center.latitude * .pi / 180)
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
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("coursePlanner.distance")
            } else {
                Text(viewModel.isDrawingMode ? "경로를 그려주세요" : "지도에서 출발지를 선택하세요")
                    .accessibilityIdentifier("coursePlanner.prompt")
            }
        }
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

private extension CLLocationCoordinate2D {
    init(_ coordinate: CourseCoordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

private extension CourseCoordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
