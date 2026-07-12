import SwiftUI

extension CoursePlannerPage {
    var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(DesignToken.Color.grabber)
                .frame(width: 38, height: 5)
                .padding(.top, 8)
                .frame(maxWidth: .infinity)

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
            // 유리 재질(블러)은 항상 깔아둔 채 그 위에 surface 틴트를 얹는다 — 다크는 surface 알파가
            // 1.0이라 블러가 완전히 가려져 솔리드로 보이고(스펙: "다크 시트는 유리 아님"), 라이트는
            // surface 알파가 .74라 블러된 지도 위에 은은하게 겹쳐 보인다(스펙: 라이트 = Glassmorphism).
            // 이전엔 펼침 여부로 material/flat-color를 스위칭해 펼친 상태(라이트)에서 블러 없이 알파색만
            // 깔려 지도 글자가 또렷하게 비쳐 보이는 버그가 있었다 (2026-07-12 실기기 확인).
            //
            // 히트테스트 백스톱도 겸한다: .background 콘텐츠는 foreground(위 VStack)와 별개의
            // 형제 레이어라 Button 히트테스트와 경쟁하지 않는다 — 실제로 VStack 바깥쪽에 직접
            // contentShape+onTapGesture를 걸었더니 "저장" 버튼 등 모든 자식 Button이 먹통이 되는
            // 회귀가 있어(2026-07-12 실기기 확인) 이 방식으로 바꿨다. 여기 건 gesture는 배경 프레임
            // (VStack 자연 크기 + ignoresSafeArea로 확장된 홈 인디케이터 영역)에서만 탭을 흡수해,
            // 시트 안 빈 곳(예: sheetHeader의 Spacer())이나 맨 아래 띠를 눌러도 지도로 새지 않는다.
            shape
                .fill(.regularMaterial)
                .overlay(shape.fill(DesignToken.Color.surface))
                .ignoresSafeArea(edges: .bottom)
                .contentShape(Rectangle())
                .onTapGesture {}
        }
        .accessibilityIdentifier("coursePlanner.segmentPanel")
    }

    private var sheetHeaderStatusChipKind: StatusChipKind? {
        if viewModel.isLoading { return .calculating }
        if let errorMessage = viewModel.errorMessage { return .error(errorMessage) }
        if viewModel.distanceText != nil {
            if let index = viewModel.selectedSegmentIndex {
                return .route(segmentLabel: "구간 \(index + 1)")
            }
            return .startSet
        }
        return nil
    }

    // SwiftUI는 Button 라벨 안에 또 다른 Button을 중첩하면 탭 판정이 불안정해진다(어느 쪽이
    // 반응할지 보장 안 됨). 그래서 "펼치기/접기" 탭 영역(거리·서브타이틀)과 "저장"/"전체 왕복"은
    // 하나의 Button label 안에 넣지 않고, 바깥 HStack의 형제(sibling)로 둔다.
    private var sheetHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Button {
                // 스펙 §1.4 시트 높이 전환(0.32s) — 펼침/접힘 모두 이 spring으로 애니메이션.
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isBottomSheetExpanded.toggle()
                }
                if !isBottomSheetExpanded {
                    let keys = viewModel.segmentColorKeys
                    let anchorIndex = panelAnchorColorKey.flatMap { keys.firstIndex(of: $0) }
                    let latestIndex = SegmentPanelLogic.latestIndex(colorKeys: keys)
                    panelWasNearLatestAtCollapse = SegmentPanelLogic.shouldAutoScroll(
                        anchorIndex: anchorIndex, previousLatestIndex: latestIndex
                    )
                }
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
