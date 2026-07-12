import SwiftUI

extension CoursePlannerPage {
    var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            grabberHandle

            sheetHeader

            if isBottomSheetExpanded {
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

    // 드래그 제스처는 그래버에만 건다 — sheetHeader나 시트 전체에 걸면 그 안의 Button들과
    // 히트테스트가 충돌해 전부 먹통이 되는 회귀가 실제로 있었다(2026-07-12, bottomSheet 배경
    // 히트테스트 백스톱 작업 중 확인). 그래버는 Button이 없는 순수 장식 요소라 안전하다.
    // 탭 토글(sheetHeader)은 그대로 유지 — 드래그는 추가 입력 방식이지 대체가 아니다.
    private var grabberHandle: some View {
        Capsule()
            .fill(DesignToken.Color.grabber)
            .frame(width: 38, height: 5)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        let threshold: CGFloat = 40
                        guard abs(value.translation.height) > threshold else { return }
                        // Gesture의 onEnded는 Button 액션과 달리 SwiftUI가 안전하게 지연 디스패치하지
                        // 않는다 — 여기서 곧바로 @State를 쓰면 "Modifying state during view update"
                        // 경고가 발생한다(2026-07-12 실기기 콘솔 로그로 재현·확정, 탭 토글에서는 없음).
                        // 다음 런루프로 한 틱 미뤄 현재 진행 중인 뷰 업데이트 트랜잭션 밖에서 쓰게 한다.
                        let expand = value.translation.height < 0
                        DispatchQueue.main.async {
                            setSheetExpanded(expand)
                        }
                    }
            )
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
    private func setSheetExpanded(_ newValue: Bool) {
        // 스펙 §1.4 시트 높이 전환(0.32s) — 펼침/접힘 모두 이 spring으로 애니메이션.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isBottomSheetExpanded = newValue
        }
        if !newValue {
            let keys = viewModel.segmentColorKeys
            let anchorIndex = panelAnchorColorKey.flatMap { keys.firstIndex(of: $0) }
            let latestIndex = SegmentPanelLogic.latestIndex(colorKeys: keys)
            panelWasNearLatestAtCollapse = SegmentPanelLogic.shouldAutoScroll(
                anchorIndex: anchorIndex, previousLatestIndex: latestIndex
            )
        }
    }

    private var sheetHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Button {
                setSheetExpanded(!isBottomSheetExpanded)
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
                if let kind = sheetHeaderStatusChipKind {
                    StatusChip(kind: kind)
                }
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
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        panelContentHeight = height
                    }
                }
                // ScrollView는 greedy — 내용이 적으면 내용 높이만큼, 많으면 지도 높이 40% 상한
                .frame(height: min(panelContentHeight, panelMaxListHeight))
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
