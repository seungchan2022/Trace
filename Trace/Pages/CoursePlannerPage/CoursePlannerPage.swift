import MapKit
import SwiftUI

struct CoursePlannerPage: View {
    @State private var viewModel: CoursePlannerPageViewModel

    init(coursePlanningService: CoursePlanningServiceProtocol) {
        _viewModel = State(initialValue: CoursePlannerPageViewModel(coursePlanningService: coursePlanningService))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapView
                .accessibilityIdentifier("coursePlanner.map")

            statusPanel
        }
    }

    private var mapView: some View {
        MapReader { proxy in
            Map {
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
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
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
    CoursePlannerPage(coursePlanningService: DependencyContainer.uiTesting().coursePlanningService)
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
