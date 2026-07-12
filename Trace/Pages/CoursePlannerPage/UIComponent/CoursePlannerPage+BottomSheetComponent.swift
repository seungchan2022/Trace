import SwiftUI

extension CoursePlannerPage {
    var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            grabberHandle

            sheetHeader

            if sheetDetent != .collapsed {
                expandedSheetBody
            }
        }
        .background {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: DesignToken.Corner.sheetTop,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: DesignToken.Corner.sheetTop
            )
            // 완전 불투명 솔리드 — 스펙 원안은 라이트를 반투명 유리(Glassmorphism)로 뒀으나,
            // 실기기 확인 결과 지도 텍스트가 그대로 겹쳐 보여 거의 읽을 수 없었다. 라이트/다크 모두
            // 불투명으로 통일하기로 결정 (2026-07-12, 사용자 — project-decisions.md 기록).
            // surface 컬러 자체가 라이트/다크 모두 알파 1.0이라 별도 material 블러가 필요 없다.
            //
            // 히트테스트 백스톱도 겸한다: .background 콘텐츠는 foreground(위 VStack)와 별개의
            // 형제 레이어라 Button 히트테스트와 경쟁하지 않는다 — 실제로 VStack 바깥쪽에 직접
            // contentShape+onTapGesture를 걸었더니 "저장" 버튼 등 모든 자식 Button이 먹통이 되는
            // 회귀가 있어(2026-07-12 실기기 확인) 이 방식으로 바꿨다. 여기 건 gesture는 배경 프레임
            // (VStack 자연 크기 + ignoresSafeArea로 확장된 홈 인디케이터 영역)에서만 탭을 흡수해,
            // 시트 안 빈 곳(예: sheetHeader의 Spacer())이나 맨 아래 띠를 눌러도 지도로 새지 않는다.
            shape
                .fill(DesignToken.Color.surface)
                .ignoresSafeArea(edges: .bottom)
                .contentShape(Rectangle())
                .onTapGesture {}
        }
        .accessibilityIdentifier("coursePlanner.segmentPanel")
    }

    // 그래버(38x5, 상하 10pt 패딩)만으로는 손가락으로 잡기엔 너무 좁다는 실기기 피드백(2026-07-12)
    // — sheetHeader 영역 전체에서도 드래그가 되도록 이 제스처를 sheetHeader의 배경(뒷면 레이어)에도
    // 건다. 배경은 foreground(버튼들)와 별개 형제 레이어라 히트테스트가 경쟁하지 않는다 — sheetHeader나
    // 시트 전체에 *직접* 걸면(래핑) 그 안의 Button들이 전부 먹통이 되는 회귀가 실제로 있었다
    // (2026-07-12, bottomSheet 배경 히트테스트 백스톱 작업 중 확인). 그래버 자체에도 남겨 시각적
    // 어포던스가 있는 곳에서도 그대로 동작하게 한다.
    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                let threshold: CGFloat = 40
                guard abs(value.translation.height) > threshold else { return }
                // 탭 토글도 경로 유무와 무관하게 기본↔중간을 오가므로, 드래그도 똑같이 경로
                // 유무와 무관하게 단계를 이동한다 — 둘의 동작이 다르면 안 된다는 사용자 확인
                // (2026-07-12: "빈 경로일 때 버튼을 누르면 시트가 올라가는데 드래그로는 안돼").
                let goingUp = value.translation.height < 0
                let nextDetent: SheetDetent = goingUp ? sheetDetent.steppedUp : sheetDetent.steppedDown
                // Gesture의 onEnded는 Button 액션과 달리 SwiftUI가 안전하게 지연 디스패치하지
                // 않는다 — 여기서 곧바로 @State를 쓰면 "Modifying state during view update"
                // 경고가 발생한다(2026-07-12 실기기 콘솔 로그로 재현·확정, 탭 토글에서는 없음).
                // 다음 런루프로 한 틱 미뤄 현재 진행 중인 뷰 업데이트 트랜잭션 밖에서 쓰게 한다.
                DispatchQueue.main.async {
                    setSheetDetent(nextDetent)
                }
            }
    }

    private var grabberHandle: some View {
        Capsule()
            .fill(DesignToken.Color.grabber)
            .frame(width: 38, height: 5)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(sheetDragGesture)
            .accessibilityIdentifier("coursePlanner.segmentPanel.grabber")
    }

    // "출발 지정됨" 상태는 없앴다 — 구간이 몇 개든 특정 구간을 선택 중이 아니면 항상 이 문구가
    // 떠서 의미가 없었다(2026-07-12, 사용자 확인 — project-decisions.md 기록). 경로가 있으면
    // 선택된 구간, 없으면 가장 최근 구간 번호를 보여주고, 경로 자체가 없으면 칩을 아예 띄우지 않는다.
    private var sheetHeaderStatusChipKind: StatusChipKind? {
        if viewModel.isLoading { return .calculating }
        if let errorMessage = viewModel.errorMessage { return .error(errorMessage) }
        guard let segments = viewModel.course?.segments, !segments.isEmpty else { return nil }
        let index = viewModel.selectedSegmentIndex ?? (segments.count - 1)
        return .route(segmentLabel: "구간 \(index + 1)")
    }

    // SwiftUI는 Button 라벨 안에 또 다른 Button을 중첩하면 탭 판정이 불안정해진다(어느 쪽이
    // 반응할지 보장 안 됨). 그래서 "펼치기/접기" 탭 영역(거리·서브타이틀)과 "저장"/"전체 왕복"은
    // 하나의 Button label 안에 넣지 않고, 바깥 HStack의 형제(sibling)로 둔다.
    // 탭 토글과 드래그 제스처가 공유하는 단일 진입점 — 앵커 스크롤 위치 계산이
    // 두 입력 방식 모두에서 똑같이 일어나도록 한다(2026-07-12, 드래그 리사이즈 추가하며 분리).
    private func setSheetDetent(_ newDetent: SheetDetent) {
        // 스펙 §1.4 시트 높이 전환(0.32s) — 모든 단계 전환에 이 spring을 쓴다.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            sheetDetent = newDetent
        }
        if newDetent == .collapsed {
            let keys = viewModel.segmentColorKeys
            let anchorIndex = panelAnchorColorKey.flatMap { keys.firstIndex(of: $0) }
            let latestIndex = SegmentPanelLogic.latestIndex(colorKeys: keys)
            panelWasNearLatestAtCollapse = SegmentPanelLogic.shouldAutoScroll(
                anchorIndex: anchorIndex, previousLatestIndex: latestIndex
            )
        }
    }

    // .firstTextBaseline이었을 때 로딩 중 헤더가 순간적으로 커지는 움찔거림이 있었다(2026-07-13,
    // XCUITest로 헤더 높이 실측: 대기 105pt → 로딩 중 131pt). StatusChip의 첫 자식이 .calculating일
    // 땐 ProgressView(텍스트 아님), .route일 땐 Text라서, 이 헤더 HStack이 baseline 정렬을 쓰면
    // 두 상태의 암묵적 베이스라인 기준점이 달라져 전체 높이가 흔들렸다. .top으로 바꿔 이 클래스의
    // 버그 자체를 없앤다.
    private var sheetHeader: some View {
        HStack(alignment: .top) {
            Button {
                // 탭은 기본↔중간만 오간다 — "거의 다"는 드래그로만 도달(2026-07-12, 사용자 확인).
                setSheetDetent(sheetDetent == .collapsed ? .medium : .collapsed)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if let distanceText = viewModel.distanceText {
                        // viewModel.distanceText는 "1.43 km"처럼 단위가 이미 포함된 문자열이다
                        // (ViewModel은 이 작업 범위 밖 — Global Constraint). 스펙 §2가 요구하는
                        // "44pt 숫자 + 17pt 'km' 단위" 분리 표기를 위해 뷰 레이어에서만 단위를 떼어낸다.
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(distanceText.replacingOccurrences(of: " km", with: ""))
                                .font(DesignToken.Typography.distanceHeadline)
                                .foregroundStyle(DesignToken.Color.ink)
                                .accessibilityIdentifier("coursePlanner.distance")
                            Text("km")
                                .font(DesignToken.Typography.distanceUnit)
                                .foregroundStyle(DesignToken.Color.ink2)
                        }
                    } else {
                        Text("0")
                            .font(DesignToken.Typography.distanceHeadline)
                            .foregroundStyle(DesignToken.Color.ink2)
                    }
                    Text(subtitleText)
                        .font(DesignToken.Typography.subtitle)
                        .foregroundStyle(DesignToken.Color.ink2)
                        .accessibilityIdentifier(subtitleAccessibilityIdentifier)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coursePlanner.segmentPanel.collapsed")

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                // 칩을 조건부로 넣고 빼면(nil ↔ 값) 그 자리만큼 헤더 전체 높이가 바뀐다 — 저장/전체
                // 왕복 버튼처럼 opacity로만 숨기고 자리는 항상 차지하게 해서, 로딩 시작 등으로 칩이
                // 나타나는 순간 헤더(그리고 시트 전체)가 살짝 커졌다 줄어드는 움찔거림을 없앤다
                // (2026-07-12, 사용자 — "계산중에 해당하는 부분들이 보일때 시트가 살짝 올라갔다
                // 다시 내려오는 느낌").
                StatusChip(kind: sheetHeaderStatusChipKind ?? .route(segmentLabel: " "))
                    .opacity(sheetHeaderStatusChipKind == nil ? 0 : 1)
                    .accessibilityHidden(sheetHeaderStatusChipKind == nil)
                HStack(spacing: 8) {
                    // "저장"은 텍스트+아이콘 캡슐이라 GlassIconButtonStyle(42×42 고정 프레임)에
                    // 억지로 끼우면 라벨이 잘린다 — 이 버튼만 인라인 Capsule 배경을 직접 사용한다.
                    Button { viewModel.isSavePromptPresented = true } label: {
                        Label("저장", systemImage: "bookmark.fill")
                            .font(DesignToken.Typography.chip)
                            .foregroundStyle(DesignToken.Color.accentInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(DesignToken.Color.accent))
                    }
                    .disabled(!viewModel.canSaveCourse)
                    .opacity(viewModel.canSaveCourse ? 1 : 0.4)
                    .accessibilityIdentifier("coursePlanner.saveCourse")

                    Button { viewModel.insertWholeCourseRoundTrip() } label: {
                        Text("전체 왕복")
                            .font(DesignToken.Typography.sectionLabel)
                            .foregroundStyle(DesignToken.Color.accent)
                    }
                    .disabled(!viewModel.canInsertWholeCourseRoundTrip)
                    .opacity(viewModel.canInsertWholeCourseRoundTrip ? 1 : 0.4)
                    .accessibilityIdentifier("coursePlanner.wholeCourseRoundTrip")
                }
            }
        }
        .padding(.horizontal, DesignToken.Size.sheetPadding)
        .padding(.vertical, 16)
        .background {
            // 드래그 히트 영역 확장용 — 배경이라 foreground의 Button들과 히트테스트가 경쟁하지 않는다.
            Color.clear
                .contentShape(Rectangle())
                .gesture(sheetDragGesture)
        }
        // "거의 다" 단계의 최대 높이를 계산하려면 헤더 자신의 높이가 필요하다 — 리스트 높이가
        // 헤더 높이에 영향을 주지 않으므로(반대 방향 의존) 순환이 아니다.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            sheetHeaderHeight = height
        }
    }

    private var subtitleText: String {
        if viewModel.isLoading { return "경로를 계산하고 있어요" }
        if viewModel.errorMessage != nil { return "도로에 더 가까운 지점을 눌러보세요" }
        if let infoMessage = viewModel.infoMessage { return infoMessage }
        if viewModel.distanceText != nil { return "도보 기준 · 탭해서 이어 그리기" }
        if viewModel.isDrawingMode { return "지도에 손으로 경로를 그려보세요" }
        return "지도를 탭해 출발지를 선택하세요"
    }

    private var subtitleAccessibilityIdentifier: String {
        if viewModel.isLoading { return "coursePlanner.loading" }
        if viewModel.errorMessage != nil { return "coursePlanner.error" }
        if viewModel.infoMessage != nil { return "coursePlanner.info" }
        return "coursePlanner.prompt"
    }

    // 행 identity는 colorKey(생성 순번) — prepend로 인덱스가 밀려도 행 정체성과
    // scrollTo 대상이 안정적으로 유지된다 (MVP7 colorKey와 같은 원리).
    private struct PanelRow: Identifiable {
        let index: Int
        let colorKey: Int
        let segment: CourseSegment
        var id: Int { colorKey }
    }

    private var panelRows: [PanelRow] {
        let segments = viewModel.course?.segments ?? []
        let keys = viewModel.segmentColorKeys
        return segments.enumerated().map { index, segment in
            PanelRow(index: index, colorKey: index < keys.count ? keys[index] : index, segment: segment)
        }
    }

    // presentationDetents처럼 단계별 고정 높이 — 콘텐츠 양은 높이에 전혀 영향을 주지 않는다.
    // 구간이 적으면 그냥 빈 공간이 남고, 많으면 스크롤된다. 이전엔 min(실측 콘텐츠 높이, 상한)으로
    // 짜여 있어 구간이 늘어날 때마다 시트가 실측 높이만큼 점점 커지는 문제가 있었다(2026-07-12,
    // 사용자 확인 — "추가할 때마다 늘어나면 안 된다"). collapsed는 expandedSheetBody 자체가
    // 렌더되지 않아 이 값이 쓰이지 않는다.
    // fabStack이 collapsed 시트 높이를 계산할 때도 참조하므로(CoursePlannerPage.swift) private가 아니다.
    var grabberTotalHeight: CGFloat { 25 }

    // 시트가 top safe area 계산에 쓰는 여유값보다 더 커질수록, 시스템이 실제 top safe area
    // 자체를 조금씩 더 작게 보고하는 잔여 현상이 남아있다(2026-07-12, 피드백 루프를 끊은 뒤에도
    // XCUITest 실측: topBar가 여전히 11pt 밀림). 12pt로는 이 잔여분을 못 흡수해 상태바/다이내믹
    // 아일랜드와 살짝 겹쳤다 — 여유를 넉넉히 둬서 흡수한다.
    private var sheetTopMargin: CGFloat { 40 }

    // 풀 시트가 다이내믹 아일랜드/상태 바 바로 아래에서 멈추도록 하는 상한 — 시스템 시트의
    // large detent와 같은 발상. expandedListHeight(.full)의 리스트 높이 계산에만 쓴다.
    //
    // 한 번은 이 값을 bottomSheet 자체에도 .frame(maxHeight:, alignment: .top)으로 강제해
    // 오버슈트를 물리적으로 막으려 했으나, ZStack이 자식에게 화면 전체 높이를 제안하는 상황에서
    // maxHeight만 있고 exact height가 없는 프레임은 제안받은 크기(여기선 화면 높이)까지 그대로
    // 차지해버려 시트 전체가 화면 위쪽 절반을 덮는 보이지 않는 히트테스트 영역이 되었다 — collapsed/
    // medium 단계에서 지도 탭이 그 영역에 흡수되어 경로 생성 자체가 안 되는 회귀였다(2026-07-12,
    // XCUITest 접근성 트리 덤프로 확인 후 되돌림). 오버슈트 방어는 다시 시도하더라도 bottomSheet
    // 전체가 아니라 expandedSheetBody의 리스트 높이 안쪽에서만 해야 한다.
    private var maxSheetHeight: CGFloat {
        mapHeight - topSafeAreaInset - sheetTopMargin
    }

    // presentationDetents처럼 단계별 고정 높이 — 콘텐츠 양은 높이에 전혀 영향을 주지 않는다.
    // 구간이 적으면 그냥 빈 공간이 남고, 많으면 스크롤된다. 이전엔 min(실측 콘텐츠 높이, 상한)으로
    // 짜여 있어 구간이 늘어날 때마다 시트가 실측 높이만큼 점점 커지는 문제가 있었다(2026-07-12,
    // 사용자 확인 — "추가할 때마다 늘어나면 안 된다"). collapsed는 expandedSheetBody 자체가
    // 렌더되지 않아 이 값이 쓰이지 않는다.
    private var expandedListHeight: CGFloat {
        switch sheetDetent {
        case .collapsed: return 0
        case .medium: return panelMaxListHeight
        case .full:
            // 시스템 시트의 large detent처럼 위쪽 안전영역(+여백)만 남기고 나머지를 채운다 —
            // 이전엔 panelMaxListHeight의 고정 배수를 써서 기기에 따라 시트가 상태바까지
            // 뚫고 올라가는 버그가 있었다(2026-07-12 실기기 확인, 사용자 스크린샷).
            let maxListHeight = maxSheetHeight - grabberTotalHeight - sheetHeaderHeight
            return max(panelMaxListHeight, maxListHeight)
        }
    }

    private var expandedSheetBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(panelRows) { row in
                            segmentRow(row)
                        }
                    }
                    .scrollTargetLayout()
                }
                // 고정 높이 — 자기 콘텐츠를 측정해서 자기 프레임에 다시 먹이는 순환(측정→적용→재측정)이
                // 없다. 이 순환이 구간 선택처럼 콘텐츠가 미세하게 바뀔 때마다 레이아웃이 잠깐
                // 움찔거리는 원인 중 하나였다(2026-07-12, 사용자 확인).
                .frame(height: expandedListHeight)
                // 콘텐츠 여백만 12pt로 주고 스크롤 인디케이터는 기본 여백(에지에 붙게) 유지 —
                // .padding()으로 ScrollView 전체를 감싸면 인디케이터까지 같이 밀려 보인다 (실기기 QA 발견).
                .contentMargins(.horizontal, 12, for: .scrollContent)
                .contentMargins(.bottom, 12, for: .scrollContent)
                .scrollPosition(id: $panelAnchorColorKey, anchor: .center)
                .onAppear {
                    restoreScrollPosition(proxy)
                }
                .onChange(of: viewModel.segmentColorKeys.max()) { oldMax, newMax in
                    // 증가(새 구간)일 때만 — undo/clear로 줄어들 때는 보던 위치 유지 (스펙)
                    guard let newMax, newMax > (oldMax ?? Int.min) else { return }
                    autoScrollIfNearLatest(proxy, previousMaxKey: oldMax)
                }
            }
        }
        .frame(minWidth: 220)
    }

    private func segmentRow(_ row: PanelRow) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.selectSegment(at: row.index)
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(uiColor: SegmentPalette.color(at: row.colorKey)))
                        .frame(width: 10, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("구간 \(row.index + 1)")
                            .font(DesignToken.Typography.segmentRowTitle)
                            .foregroundStyle(DesignToken.Color.ink)
                        Text(row.segment.isRoundTrip ? "왕복" : "지점 연결")
                            .font(DesignToken.Typography.segmentRowSubtitle)
                            .foregroundStyle(DesignToken.Color.ink2)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0fm", row.segment.distanceMeters))
                            .font(DesignToken.Typography.segmentRowDistance)
                            .foregroundStyle(DesignToken.Color.ink)
                        Text(String(format: "누적 %.2fkm", cumulativeDistanceMeters(upTo: row.index) / 1000))
                            .font(.caption2)
                            .foregroundStyle(DesignToken.Color.ink2)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: DesignToken.Corner.row)
                        .fill(row.index == viewModel.selectedSegmentIndex ? DesignToken.Color.surface2 : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignToken.Corner.row)
                        .strokeBorder(
                            row.index == viewModel.selectedSegmentIndex ? DesignToken.Color.accent : Color.clear,
                            lineWidth: 1.5
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coursePlanner.segmentPanel.item.\(row.index)")

            Button {
                viewModel.insertRoundTrip(afterColorKey: row.colorKey)
            } label: {
                Image(systemName: "arrow.uturn.down.circle")
                    .font(.callout)
                    .foregroundStyle(DesignToken.Color.ink2)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canInsertRoundTrip(afterColorKey: row.colorKey))
            .opacity(viewModel.canInsertRoundTrip(afterColorKey: row.colorKey) ? 1 : 0.4)
            .accessibilityIdentifier("coursePlanner.segmentPanel.roundTrip.\(row.index)")
        }
    }

    // 새 구간 추가 시: 직전 최신 구간 근처를 보고 있을 때만 최신으로 스크롤 (채팅 앱 방식)
    private func autoScrollIfNearLatest(_ proxy: ScrollViewProxy, previousMaxKey: Int?) {
        let keys = viewModel.segmentColorKeys
        guard let maxKey = keys.max() else { return }
        let anchorIndex = panelAnchorColorKey.flatMap { keys.firstIndex(of: $0) }
        let previousLatestIndex = previousMaxKey.flatMap { keys.firstIndex(of: $0) }
        guard SegmentPanelLogic.shouldAutoScroll(
            anchorIndex: anchorIndex, previousLatestIndex: previousLatestIndex
        ) else { return }
        withAnimation {
            proxy.scrollTo(maxKey, anchor: .bottom)
        }
    }

    // 재펼침 시: 접기 직전 최신 근처였다면 최신을 계속 따라간다(접혀 있는 동안 구간이
    // 늘었을 수 있으므로 "그때의 최신"이 아니라 "지금의 최신"). 그렇지 않으면 보던 위치를
    // 복원하고, 없으면(첫 펼침/해당 행 삭제됨) 최신 구간으로 fallback.
    private func restoreScrollPosition(_ proxy: ScrollViewProxy) {
        let keys = viewModel.segmentColorKeys
        if panelWasNearLatestAtCollapse, let maxKey = keys.max() {
            proxy.scrollTo(maxKey, anchor: .bottom)
        } else if let anchor = panelAnchorColorKey, keys.contains(anchor) {
            proxy.scrollTo(anchor, anchor: .center)
        } else if let maxKey = keys.max() {
            proxy.scrollTo(maxKey, anchor: .bottom)
        }
    }

    private func cumulativeDistanceMeters(upTo index: Int) -> Double {
        guard let segments = viewModel.course?.segments, index < segments.count else { return 0 }
        return segments.prefix(through: index).reduce(0) { $0 + $1.distanceMeters }
    }
}
