import MapKit
import SwiftUI

// 바텀시트 3단계 — 기본(헤더만) → 중간(기존 펼침 높이) → 거의 다(지도를 거의 덮는 높이).
// 드래그로 한 번에 한 단계씩 이동(기본↔중간↔거의 다), 탭 토글은 기본↔중간만 오간다
// (2026-07-12, 사용자 피드백 — "구간을 추가할 때마다 조금씩 올라오는 게 아니라 가장 최소
// 상태로 쌓인다": 단계는 순전히 제스처로만 바뀌고 구간 개수와는 무관하다).
enum SheetDetent: Int {
    case collapsed = 0
    case medium = 1
    case full = 2

    var steppedUp: SheetDetent {
        SheetDetent(rawValue: min(rawValue + 1, SheetDetent.full.rawValue)) ?? .full
    }

    var steppedDown: SheetDetent {
        SheetDetent(rawValue: max(rawValue - 1, SheetDetent.collapsed.rawValue)) ?? .collapsed
    }
}

struct CoursePlannerPage: View {
    @State var viewModel: CoursePlannerPageViewModel
    @State private var cameraRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5666, longitude: 126.9784),
        latitudinalMeters: 500,
        longitudinalMeters: 500
    )
    @State private var currentStrokePoints: [CGPoint] = []
    @State var sheetDetent: SheetDetent = .collapsed
    @State var mapHeight: CGFloat = 750
    @State var pageHeight: CGFloat = 750
    // pageHeight(GeometryReader 앵커, 항상 안정) 기준 40% — 예산 계산과 같은 앵커를 쓴다.
    // mapHeight 기준으로 두면 되먹임 폭주(2026-07-20 실기기 진단)에 함께 오염된다.
    var panelMaxListHeight: CGFloat { pageHeight * 0.4 }
    @State private var safeAreaLatch = SafeAreaInsetLatch()
    // BottomSheetComponent 확장(별도 파일)이 기존 이름 그대로 읽는다 — private 금지.
    var topSafeAreaInset: CGFloat {
        safeAreaLatch.value(isVerticallyCompact: verticalSizeClass == .compact)
    }
    @State var sheetHeaderHeight: CGFloat = 140
    @State var panelAnchorColorKey: Int?
    // 접기 직전 "최신 근처를 보고 있었는가" — 재펼침 시 이 값이 true면 옛 앵커 대신 최신을 따라간다.
    // 기본값 true: 첫 펼침(앵커 없음)에서는 restoreScrollPosition의 fallback 분기가 이미 최신으로 보내므로 무해하다.
    @State var panelWasNearLatestAtCollapse = true
    @State private var isTopHintDismissed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var topHintText: String? {
        if let errorMessage = viewModel.errorMessage { return errorMessage }
        if viewModel.isDrawingMode && viewModel.course == nil { return "꾹 눌러서 경로를 그려보세요" }
        return nil
    }

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
        // GeometryReader는 자식 크기와 무관하게 항상 제안받은 크기를 그대로 보고한다(RootView의
        // 탭바 방어와 같은 원리, 2026-07-20). 이 ZStack 자신은 mapView/bottomSheet가 커지면 이상적
        // 크기가 함께 부풀어(ZStack은 자식 중 가장 큰 이상적 크기로 스스로를 계산한다) 그 부푼 값이
        // 다음 레이아웃 패스에서 자식들에게 "제안 크기"로 되먹임된다 — 경로가 있는 가로모드에서
        // map/page 실측이 335→666까지 폭주하는 원인(2026-07-20 실기기 진단). .frame으로 ZStack의
        // 제안/보고 크기를 proxy.size에 강제 고정해 이 되먹임 고리를 여기서 끊는다.
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // mapView는 RunPage.runMap과 동일하게 프레임 캡 없이 자연 블리드시킨다 — 캡을 걸면
                // 탭바 옆 지도가 그 프레임 경계에서 잘려 다크모드에서 검은 여백이 드러난다
                // (2026-07-20 실기기 확인). ignoresSafeArea()는 크기 제안 체계를 거치지 않고 자기가
                // 원하는 크기를 그대로 주장하므로, bottomSheet를 이 ZStack의 형제로 두면 그 주장이
                // ZStack 내부 정렬 기준(native size)까지 오염시켰다 — 그래서 시트는 형제가 아니라
                // 아래 .overlay로 분리한다(이 ZStack 자신의 .frame이 이미 안정된 기준이므로).
                mapView
                    .ignoresSafeArea(edges: .top)
                    .accessibilityIdentifier("coursePlanner.map")

                // 지도가 풀블리드 배경, 아래 VStack은 그 위에 뜨는 크롬(탑바/FAB) — 프레임 캡을
                // 걸지 않아 RunPage.runMap의 컨트롤 레이어와 동일하게 자연스러운 최소 크기로만
                // 존재한다. bottomSheet가 형제가 아니라 오버레이이므로 이 VStack이 얼마나
                // 커지든 ZStack 내부 정렬 기준을 더 이상 오염시키지 않는다(2026-07-20).
                //
                // 히트테스트: 이 VStack엔 .allowsHitTesting을 아예 걸지 않는다. 원래 계획은 VStack 전체에
                // false를 걸고 topBar/fabStack 각각에 true를 다시 거는 것이었으나, 시뮬레이터 검증 중
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
                }
                .frame(height: pageHeight, alignment: .top)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            // bottomSheet는 ZStack의 형제가 아니라 이미 안정된 .frame(height: pageHeight) 위의
            // overlay다 — overlay는 자신이 얹히는 뷰의 확정된 프레임 경계에만 정렬하고, mapView나
            // 크롬 VStack이 내부적으로 얼마나 큰 크기를 주장하든 그 기준에 전혀 영향받지 않는다
            // (ZStack 형제였을 때는 그 주장이 "native size"에 섞여 들어가 시트 하단 y좌표가
            // mapHeight/FAB 여백을 따라 갈라졌다 — 2026-07-20 실기기 진단). 이 구조가 가로 밀림·
            // 시트 오염 회귀를 해소한다 — 탭바 옆 지도 잘림은 별개 원인(가로 세이프에어리어)으로
            // 추정해 아래 .ignoresSafeArea(edges: .horizontal)을 시도했으나, 시뮬레이터에서는
            // 좌우 끝까지 닿는 것을 픽셀로 확인했음에도 실기기 재확인 결과 여전히 재현됨
            // (2026-07-20) — 미해결, `docs/backlog.md` 참고.
            .overlay(alignment: .bottom) {
                bottomSheet
            }
        }
        // RootView의 루트 콘텐츠는 기본적으로 세이프에어리어 안쪽으로 제안받는다(가로에서는
        // 좌우 안전영역이 생긴다 — 다이내믹 아일랜드/홈 인디케이터가 옆으로 돌아간 자리). 이
        // GeometryReader를 여기서 좌우로 ignoresSafeArea하지 않으면 proxy.size.width 자체가
        // 이미 그만큼 좁게 보고되고, 안의 .frame(width: proxy.size.width...)이 그 좁은 값을
        // 그대로 굳혀버려 mapView/bottomSheet가 아무리 안에서 애써도 진짜 화면 끝까지 못
        // 번진다 — 가로에서 탭바/시트 옆이 검게 남는 원인이었다(2026-07-20 시뮬레이터 실측:
        // 코스 탭만 좌우로 대칭 검은 여백, 같은 RootView 아래의 러닝 탭은 이 프레임 고정이
        // 없어 정상적으로 끝까지 번짐). 세로는 좌우 안전영역이 0이라 이 modifier가 아무 효과가
        // 없다 — 세로 동작은 그대로다.
        .ignoresSafeArea(edges: .horizontal)
        // GeometryReader 자신이 보고하는 크기는 오직 "부모가 나에게 제안한 크기"일 뿐, 안의
        // ZStack이 무엇을 하든 절대 바뀌지 않는다 — 시트 예산(maxSheetHeight)이 참조하는
        // 유일하게 안정된 앵커.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            pageHeight = height
        }
        // 시트가 커질수록 이 값 자체가 시스템에 의해 더 작게 보고되는 피드백 루프가 있었다
        // (2026-07-12, XCUITest로 실측: medium 62pt → full 40pt). 한 번 잡은 값보다 작은 값은
        // 무시(ratchet)해 루프를 끊되, 가로 지원(2026-07-19) 이후로는 세로/가로의 진짜 안전영역이
        // 다르므로(세로 62 / 가로 0) size class별로 독립 latch한다 — 단일 ratchet은 가로에서
        // 세로 값이 눌러앉아 가로 full 시트가 62pt 짧아지는 stale 문제가 있었다(2026-07-20 실측).
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.top
        } action: { newValue in
            safeAreaLatch.update(newValue, isVerticallyCompact: verticalSizeClass == .compact)
        }
        .overlay(alignment: .top) {
            if let hint = topHintText, !isTopHintDismissed {
                HintPill(text: hint, isError: viewModel.errorMessage != nil)
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
        .onChange(of: topHintText) { _, _ in
            isTopHintDismissed = false
        }
        .task(id: topHintText) {
            guard topHintText != nil else { return }
            try? await Task.sleep(for: .seconds(HintPill.autoDismissDelay))
            isTopHintDismissed = true
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
                context.stroke(path, with: .color(DesignToken.Color.accent), lineWidth: 4)
            }
            .allowsHitTesting(false)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            // 예산 계산에는 더 이상 안 쓴다(pageHeight로 대체) — 진단 오버레이 비교용으로만 남긴다.
            mapHeight = height
        }
    }

    private var fabStack: some View {
        // 시트 연동 정책은 FabLayoutPolicy 참조 — 방향 스펙 §2가 기존 "collapsed 외 숨김"
        // (2026-07-13)을 대체: 시트 위로 이동 + 단계별 페이드 + 풀에서 소멸, 경로 없으면 현위치만.
        VStack(spacing: 12) {
            if FabLayoutPolicy.showsEditingGroup(
                hasCourse: viewModel.course != nil,
                canUndo: viewModel.canUndo,
                canRedo: viewModel.canRedo
            ) {
                editingFabGroup
            }
            recenterButton
        }
        .frame(width: DesignToken.Size.fab)
        .padding(.trailing, DesignToken.Size.screenMargin)
        .padding(.bottom, FabLayoutPolicy.bottomPadding(
            detent: sheetDetent,
            collapsedSheetHeight: grabberTotalHeight + sheetHeaderHeight,
            mediumListHeight: panelMaxListHeight
        ))
        .opacity(FabLayoutPolicy.opacity(for: sheetDetent))
        .animation(.easeInOut(duration: 0.2), value: sheetDetent)
        .allowsHitTesting(sheetDetent != .full)
    }

    private var editingFabGroup: some View {
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
        }
    }

    private var recenterButton: some View {
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
        .accessibilityIdentifier("coursePlanner.recenter")
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
