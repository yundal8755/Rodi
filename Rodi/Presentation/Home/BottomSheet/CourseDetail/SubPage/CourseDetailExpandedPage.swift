import SwiftUI

struct CourseDetailExpandedPage: View {
    @Environment(\.screenSafeAreaInsets) private var screenSafeAreaInsets
    @State private var activeReviewDropdown: CourseReviewDropdown?

    let state: CourseDetailBottomSheetReducer.State
    let send: (CourseDetailBottomSheetReducer.Action) -> Void
    let bookmarkAction: () -> Void
    let routeGuidanceAction: () -> Void

    var body: some View {
        if let detail = state.detail {
            page(detail: detail)
        }
    }
}

private extension CourseDetailExpandedPage {

    @ViewBuilder
    func page(detail: PlaceDetail) -> some View {
        Group {
            if state.presentation == .reportForm {
                CourseReviewReportPage(state: state, send: send)
            } else if state.presentation == .allReviews {
                allReviewsPage(detail: detail)
            } else {
                detailPage(detail: detail)
            }
        }
        .overlayPreferenceValue(RodiDropdownAnchorPreferenceKey.self) { anchors in
            reviewLevelDropdownOverlay(anchors: anchors)
        }
        .overlay {
            if state.isBlockConfirmationPresented {
                blockConfirmationDialog
            }
        }
    }

    func detailPage(detail: PlaceDetail) -> some View {
        ZStack {
            RodiColor.white
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        courseInformation(detail: detail)
                        routeSection(detail: detail)
                            .padding(.top, 28)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                    fullWidthDivider(height: 2)
                        .padding(.vertical, 24)

                    reviewSection
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(dropdownDismissDragGesture)
            .safeAreaInset(edge: .top, spacing: 0) {
                fixedHeader(title: nil)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                fixedActionBar(detail: detail)
            }
        }
    }

    func allReviewsPage(detail: PlaceDetail) -> some View {
        ZStack {
            RodiColor.white
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CourseReviewAllContent(
                        summary: selectedReviewSummary,
                        page: state.reviewPages[state.selectedReviewLevel],
                        isSummaryLoading: selectedReviewSummaryState.isLoading,
                        summaryErrorMessage: selectedReviewSummaryState.errorMessage,
                        selectedLevel: state.selectedReviewLevel,
                        activeDropdown: $activeReviewDropdown,
                        onLoadMore: { send(.nextReviewPageRequested) },
                        onRetry: { send(.reviewsRetryRequested) }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(dropdownDismissDragGesture)
            .safeAreaInset(edge: .top, spacing: 0) {
                fixedHeader(title: "레벨별 후기")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                fixedActionBar(detail: detail)
            }
        }
    }

    func fullWidthDivider(height: CGFloat) -> some View {
        Rectangle()
            .fill(RodiColor.primaryMinus100)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityHidden(true)
    }

    var topBarInset: CGFloat {
        max(screenSafeAreaInsets.top, 20)
    }

    var bottomBarInset: CGFloat {
        max(screenSafeAreaInsets.bottom, 34)
    }

    func fixedHeader(title: String?) -> some View {
        header(title: title)
            .padding(.horizontal, 16)
            .padding(.top, topBarInset + 4)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(RodiColor.white)
    }

    func fixedActionBar(detail: PlaceDetail) -> some View {
        actionBar(detail: detail)
            .padding(.bottom, bottomBarInset)
            .background(RodiColor.white)
    }

    func header(title: String?) -> some View {
        ZStack {
            if let title {
                Text(title)
                    .rodiTypography(.body1SemiBold)
                    .foregroundStyle(RodiColor.black)
            }

            HStack {
                Button {
                    send(.collapseRequested)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(RodiColor.black)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.presentation == .allReviews ? "코스 상세로 돌아가기" : "코스 시트로 돌아가기")

                Spacer()
            }
        }
        .padding(.leading, -10)
    }

    func courseInformation(detail: PlaceDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.name)
                .rodiTypography(.headline1)
                .foregroundStyle(RodiColor.black)
                .lineLimit(1)

            HStack(spacing: 4) {
                if let distance = detail.course?.distanceMeters {
                    Text(formattedDistance(distance))
                        .rodiTypography(.body1SemiBold)
                        .foregroundStyle(RodiColor.primary)
                }

                Text("주행거리")
                    .rodiTypography(.caption1Medium)
                    .foregroundStyle(RodiColor.gray800)
            }

            if !visibleTags(detail).isEmpty || remainingTagCount(detail) > 0 {
                HStack(spacing: 4) {
                    ForEach(visibleTags(detail), id: \.self) { tag in
                        Text(tag)
                            .rodiTypography(.caption1Medium)
                            .foregroundStyle(RodiColor.gray600)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RodiColor.gray200)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .lineLimit(1)
                    }

                    if remainingTagCount(detail) > 0 {
                        Text("+\(remainingTagCount(detail))")
                            .rodiTypography(.caption1Medium)
                            .foregroundStyle(RodiColor.gray700)
                    }
                }
                .lineLimit(1)
            }

            if let cautionText = cautionText(detail) {
                HStack(spacing: 4) {
                    Image("ic_alert_triangle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)

                    Text(cautionText)
                        .rodiTypography(.caption1Medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(RodiColor.secondary400)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            if let summary = detail.course?.summary, !summary.isEmpty {
                Text(summary)
                    .rodiTypography(.caption1Regular)
                    .foregroundStyle(RodiColor.gray800)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 37)
                    .background(RodiColor.gray100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 18)
            }
        }
    }

    func routeSection(detail: PlaceDetail) -> some View {
        let points = RodiCourseItem(placeDetail: detail).routeOverlayPoints
        return VStack(alignment: .leading, spacing: 14) {
            Text("경로 정보")
                .rodiTypography(.headline2)
                .foregroundStyle(RodiColor.black)
                .padding(.bottom, 10)

            if points.isEmpty {
                Text("경로 정보를 준비 중이에요.")
                    .rodiTypography(.caption1Regular)
                    .foregroundStyle(RodiColor.gray600)
            } else {
                CourseRouteTimelineView(points: visibleRoutePoints(points))

                Button {
                    send(.routeTimelineToggled)
                } label: {
                    HStack(spacing: 10) {
                        Text(state.isRouteTimelineExpanded ? "접기" : "자세히 보기")
                            .rodiTypography(.body3Medium)

                        Image("ic_chevron_down")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .rotationEffect(.degrees(state.isRouteTimelineExpanded ? 180 : 0))
                    }
                    .foregroundStyle(RodiColor.gray700)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(RodiColor.gray300, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(points.count <= 1)
            }
        }
    }

    var reviewSection: some View {
        CourseReviewSection(
            summary: selectedReviewSummary,
            page: state.reviewPages[state.selectedReviewLevel],
            isSummaryLoading: selectedReviewSummaryState.isLoading,
            summaryErrorMessage: selectedReviewSummaryState.errorMessage,
            selectedLevel: state.selectedReviewLevel,
            showsAllReviewsButton: (selectedReviewSummary?.totalReviewCount ?? 0) > 0,
            activeDropdown: $activeReviewDropdown,
            onSelectLevel: { send(.reviewLevelSelected($0)) },
            onShowAllReviews: { send(.allReviewsRequested) },
            onRetry: { send(.reviewsRetryRequested) },
            onWriteReview: { send(.reviewWritingRequested) }
        )
    }

    @ViewBuilder
    func reviewLevelDropdownOverlay(
        anchors: [AnyHashable: Anchor<CGRect>]
    ) -> some View {
        if let activeReviewDropdown,
           let anchor = anchors[activeReviewDropdown] {
            GeometryReader { proxy in
                let triggerFrame = proxy[anchor]

                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            self.activeReviewDropdown = nil
                        }

                    reviewDropdownMenu(
                        for: activeReviewDropdown,
                        triggerFrame: triggerFrame
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea()
            .zIndex(10)
        }
    }

    var effectiveSelectedReviewLevel: ReviewLevel? {
        switch state.selectedReviewLevel {
        case .current:
            selectedReviewSummary?.level
        case .level(let level):
            level
        case .all:
            nil
        }
    }

    var reviewLevelOptions: [RodiDropdownOption] {
        ReviewLevel.allCases
            .filter { $0 != selectedReviewLevel }
            .map { .init(id: $0.rawValue, title: $0.displayName) }
    }

    var reviewActionOptions: [RodiDropdownOption] {
        [
            .init(id: "report", title: "신고하기"),
            .init(id: "block", title: "차단")
        ]
    }

    var selectedReviewLevel: ReviewLevel? {
        effectiveSelectedReviewLevel
    }

    var selectedReviewSummaryState: CourseDetailBottomSheetReducer.ReviewSummaryState {
        state.reviewSummaries[state.selectedReviewLevel] ?? .init()
    }

    var selectedReviewSummary: PlaceReviewSummary? {
        selectedReviewSummaryState.value
    }

    var dropdownDismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                activeReviewDropdown = nil
            }
    }

    func selectReviewLevel(_ level: ReviewLevel) {
        send(.reviewLevelSelected(.level(level)))
    }

    @ViewBuilder
    func reviewDropdownMenu(
        for dropdown: CourseReviewDropdown,
        triggerFrame: CGRect
    ) -> some View {
        switch dropdown {
        case .allReviewsHeader, .summary:
            RodiDropdownMenu(
                options: reviewLevelOptions,
                onSelect: { option in
                    self.activeReviewDropdown = nil
                    guard let level = ReviewLevel(rawValue: option.id) else { return }
                    selectReviewLevel(level)
                }
            )
            .alignmentGuide(.leading) { dimensions in
                dimensions[.trailing] - triggerFrame.maxX
            }
            .alignmentGuide(.top) { dimensions in
                dimensions[.top] - triggerFrame.maxY - 8
            }

        case .reviewMenu(let reviewID):
            RodiDropdownMenu(
                options: reviewActionOptions,
                onSelect: { option in
                    self.activeReviewDropdown = nil
                    if option.id == "report" {
                        send(.reviewReportRequested(reviewID: reviewID))
                    } else if option.id == "block" {
                        send(.reviewBlockRequested(reviewID: reviewID))
                    }
                }
            )
            .alignmentGuide(.leading) { dimensions in
                dimensions[.trailing] - triggerFrame.maxX
            }
            .alignmentGuide(.top) { dimensions in
                dimensions[.top] - triggerFrame.maxY - 8
            }
        }
    }

    func actionBar(detail: PlaceDetail) -> some View {
        HStack(spacing: 8) {
            Button(action: bookmarkAction) {
                Group {
                    if state.isBookmarkUpdating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(detail.isBookmarked ? "ic_bookmark_action_filled" : "ic_bookmark_action")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(width: 46, height: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(RodiColor.gray300, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(state.isBookmarkUpdating)
            .accessibilityLabel(detail.isBookmarked ? "북마크 해제" : "북마크 저장")

            Button(action: routeGuidanceAction) {
                HStack(spacing: 8) {
                    if state.isRouteLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(RodiColor.white)
                    }
                    Text("연습하러 가기")
                        .rodiTypography(.buttonMedium)
                }
                .foregroundStyle(RodiColor.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background((detail.course?.waypoints.count ?? 0) >= 2 ? RodiColor.primary : RodiColor.gray300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled((detail.course?.waypoints.count ?? 0) < 2 || state.isRouteLoading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(RodiColor.white)
        .shadow(color: RodiColor.black.opacity(0.12), radius: 8, x: 0, y: -3)
    }

    var blockConfirmationDialog: some View {
        RodiModalBackground {
            RodiDialog(contentInsets: .init(top: 32, leading: 20, bottom: 32, trailing: 20)) {
                VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        Text("사용자를 차단하겠습니까?")
                            .rodiTypography(.body1SemiBold)
                            .foregroundStyle(RodiColor.black)

                        Text("이 사용자의 모든 리뷰를 보지 않습니다.")
                            .rodiTypography(.caption1Medium)
                            .foregroundStyle(RodiColor.black)
                            .multilineTextAlignment(.center)
                            .frame(height: 60)
                    }
                    .frame(minWidth: 240)

                    HStack(spacing: 8) {
                        Button {
                            send(.reviewBlockCancelled)
                        } label: {
                            Text("취소")
                                .rodiTypography(.buttonMedium)
                                .foregroundStyle(RodiColor.gray800)
                                .frame(width: 116, height: 42)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(RodiColor.gray300, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(state.isBlockingMember)
                        .accessibilityLabel("차단 취소")

                        Button {
                            send(.reviewBlockConfirmed)
                        } label: {
                            Group {
                                if state.isBlockingMember {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(RodiColor.white)
                                } else {
                                    Text("차단")
                                        .rodiTypography(.buttonMedium)
                                }
                            }
                            .foregroundStyle(RodiColor.white)
                            .frame(width: 116, height: 42)
                            .background(RodiColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(state.isBlockingMember)
                        .accessibilityLabel("사용자 차단")
                    }
                    .padding(.top, 24)
                }
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    func visibleRoutePoints(_ points: [RodiRouteOverlayPoint]) -> [RodiRouteOverlayPoint] {
        state.isRouteTimelineExpanded ? points : Array(points.prefix(1))
    }

    func formattedDistance(_ meters: Int) -> String {
        let kilometers = Double(meters) / 1_000
        return kilometers.rounded() == kilometers
            ? String(format: "%.0fkm", kilometers)
            : String(format: "%.1fkm", kilometers)
    }

    func visibleTags(_ detail: PlaceDetail) -> [String] {
        Array(detail.practiceTypes.map(PlacePracticeType.displayName(for:)).prefix(4))
    }

    func remainingTagCount(_ detail: PlaceDetail) -> Int {
        max(0, detail.practiceTypes.count - visibleTags(detail).count)
    }

    func cautionText(_ detail: PlaceDetail) -> String? {
        let cautions = Array((detail.course?.cautions ?? []).prefix(2))
        return cautions.isEmpty ? nil : cautions.joined(separator: " ･ ")
    }
}
