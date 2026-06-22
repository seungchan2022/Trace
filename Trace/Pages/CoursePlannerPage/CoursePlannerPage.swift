import MapKit
import SwiftUI

struct CoursePlannerPage: View {
    @State var viewModel: CoursePlannerPageViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentStroke: [CourseCoordinate] = []
    @State private var currentStrokePoints: [CGPoint] = []

    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol
    ) {
        _viewModel = State(initialValue: CoursePlannerPageViewModel(
            coursePlanningService: coursePlanningService,
            locationService: locationService
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
                await viewModel.bootstrapLocation()
                if let center = viewModel.initialCameraCoordinate {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                        latitudinalMeters: 1000,
                        longitudinalMeters: 1000
                    ))
                }
            }
    }

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: viewModel.isDrawingMode ? [] : .all) {
                if let course = viewModel.course {
                    MapPolyline(coordinates: course.coordinates.map(CLLocationCoordinate2D.init))
                        .stroke(.blue, lineWidth: 6)
                }

                if let start = viewModel.startCoordinate {
                    Marker("출발", systemImage: "figure.run", coordinate: CLLocationCoordinate2D(start))
                        .tint(.green)
                }

                if let destination = viewModel.destinationCoordinate {
                    Marker("도착", systemImage: "flag.checkered", coordinate: CLLocationCoordinate2D(destination))
                        .tint(.red)
                }
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

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("pts: \(currentStrokePoints.count)")
                .font(.caption.monospacedDigit())
                .accessibilityIdentifier("coursePlanner.debugCount")
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
                Text("지도에서 출발지를 선택하세요")
                    .accessibilityIdentifier("coursePlanner.prompt")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }
}

#Preview {
    CoursePlannerPage(
        coursePlanningService: DependencyContainer.uiTesting().coursePlanningService,
        locationService: DependencyContainer.uiTesting().locationService
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
