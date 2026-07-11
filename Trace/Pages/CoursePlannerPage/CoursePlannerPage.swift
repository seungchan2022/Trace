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
    @State var isBottomSheetExpanded = false
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
        cameraStateStore: CameraStateStore = CameraStateStore(),
        courseRepository: CourseRepositoryProtocol
    ) {
        self.cameraStateStore = cameraStateStore
        _viewModel = State(initialValue: CoursePlannerPageViewModel(
            coursePlanningService: coursePlanningService,
            locationService: locationService,
            cameraStateStore: cameraStateStore,
            courseRepository: courseRepository
        ))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapView
                .ignoresSafeArea()
                .accessibilityIdentifier("coursePlanner.map")

            // 지도가 풀블리드 배경, 아래 VStack은 그 위에 뜨는 크롬(탑바/FAB/시트) — safeAreaInset이
            // 아니므로 시트가 펼쳐져도 지도 프레임(mapView의 onGeometryChange 측정값)이 바뀌지 않는다.
            // .ignoresSafeArea()를 이 VStack에는 걸지 않아 상태바/노치·홈 인디케이터는 자동으로 피한다.
            //
            // 히트테스트: 이 VStack엔 .allowsHitTesting을 아예 걸지 않는다. 원래 계획은 VStack 전체에
            // false를 걸고 topBar/fabStack/bottomSheet 각각에 true를 다시 거는 것이었으나, 시뮬레이터 검증 중
            // 그 조합이 자식의 true를 무시하고 크롬 전체를 히트테스트 불가 상태로 만드는 것을 확인했다
            // (버튼이 전혀 반응하지 않고 모든 탭이 그 밑 지도로 흘러들어가 탭할 때마다 구간이 추가됨,
            // 2026-07-11 재현). Spacer()는 원래 그려지는 콘텐츠가 없어 히트테스트 대상이 되지 않으므로,
            // allowsHitTesting을 아무 데도 걸지 않아도 버튼은 정상 동작하고 Spacer 영역은 자동으로
            // 지도로 탭을 흘려보낸다 — 이 방식으로 로직 없이 두 요구사항이 모두 충족된다.
            VStack(spacing: 0) {
                topBar
                Spacer()
                HStack {
                    Spacer()
                    fabStack
                }
                bottomSheet
            }
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
        .sheet(isPresented: $viewModel.isCourseListPresented) {
            courseListSheet
        }
        .alert("코스 이름", isPresented: $viewModel.isSavePromptPresented) {
            TextField("예: 한강 5km", text: $viewModel.courseNameInput)
            Button("저장") { Task { await viewModel.saveCurrentCourse() } }
            Button("취소", role: .cancel) { viewModel.courseNameInput = "" }
        } message: {
            Text("현재 코스를 저장합니다")
        }
        .alert(
            "지금 만들던 코스를 대체할까요?",
            isPresented: Binding(
                get: { viewModel.pendingLoadCourse != nil },
                // 의도된 no-op: SwiftUI가 대체/취소 버튼 탭 모두에서 이 setter를 먼저 호출하므로,
                // 여기서 상태를 지우면 confirmPendingLoad()의 Task가 읽기 전에 값이 사라지는
                // 경쟁 상태가 재발한다. 상태 정리는 버튼 액션(confirmPendingLoad/cancelPendingLoad)에서만.
                set: { _ in }
            )
        ) {
            Button("대체", role: .destructive) { Task { await viewModel.confirmPendingLoad() } }
            Button("취소", role: .cancel) { viewModel.cancelPendingLoad() }
        } message: {
            Text("작업 중인 코스는 사라집니다")
        }
        // 저장 알럿의 키보드가 뜰 때 SwiftUI 자동 keyboard avoidance가 지도 프레임을
        // 축소시켜 줌아웃되는 것을 레이아웃 층위에서 차단한다. body 전체(ZStack 바깥)의 최상위,
        // 다른 모든 모디파이어보다 뒤에 있어야 keyboard 리전이 제거된다 (2026-07-08 시뮬레이터 로그 검증;
        // ZStack/safeAreaInset 어느 구조든 이 위치 규칙은 동일하게 적용된다).
        .ignoresSafeArea(.keyboard)
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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            panelMaxListHeight = height * 0.4
        }
    }

    private var fabStack: some View {
        VStack(spacing: 12) {
            Button { Task { await viewModel.undo() } } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.glassIcon(disabled: !viewModel.canUndo))
            .disabled(!viewModel.canUndo)
            .accessibilityIdentifier("coursePlanner.undo")

            Button { viewModel.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.glassIcon(disabled: !viewModel.canRedo))
            .disabled(!viewModel.canRedo)
            .accessibilityIdentifier("coursePlanner.redo")

            Button { viewModel.clear() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glassIcon(disabled: viewModel.course == nil && viewModel.pendingTapStart == nil))
            .disabled(viewModel.course == nil && viewModel.pendingTapStart == nil)
            .accessibilityIdentifier("coursePlanner.clear")

            Button {
                Task {
                    if let location = await viewModel.recenterToCurrentLocation() {
                        cameraRegion = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                            latitudinalMeters: 500,
                            longitudinalMeters: 500
                        )
                    }
                }
            } label: {
                Image(systemName: "location.fill")
            }
            .buttonStyle(.glassIcon)
        }
        .frame(width: DesignToken.Size.fab)
        .padding(.trailing, DesignToken.Size.screenMargin)
        .padding(.bottom, 16)
        .opacity(isBottomSheetExpanded ? 0 : 1)
        .offset(x: isBottomSheetExpanded ? 24 : 0)
        .animation(.easeInOut(duration: 0.2), value: isBottomSheetExpanded)
        .allowsHitTesting(!isBottomSheetExpanded)
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
        // 판별 창(~0.35초) 보류 중 임시 마커 — 확정된 출발/도착 핀(초록 러너/빨강 깃발)과
        // 혼동되지 않도록 중립 스타일을 쓴다. 예전엔 첫 탭/두번째 탭 여부로 출발·도착 스타일을
        // 그대로 재사용했는데, 그 판정(pendingTapStart == nil)이 라우팅 완료 전에 이미 바뀌어버려
        // 확정 직후 짧게 라벨이 뒤바뀌어 보이는 버그가 있었다 (2026-07-05 실기기 확인).
        // 중립 스타일은 위치 구분이 필요 없어 그 버그 자체가 성립하지 않는다.
        if viewModel.interactionMode == .tap, let pending = viewModel.pendingTapMarker {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: pending.latitude, longitude: pending.longitude),
                title: "확인 중",
                color: .systemGray,
                systemImage: "circle.dashed",
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
}

#Preview {
    let container = DependencyContainer.uiTesting()
    CoursePlannerPage(
        coursePlanningService: container.coursePlanningService,
        locationService: container.locationService,
        cameraStateStore: container.cameraStateStore,
        courseRepository: container.courseRepository
    )
}
