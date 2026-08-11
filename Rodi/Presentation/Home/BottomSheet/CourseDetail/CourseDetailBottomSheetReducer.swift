//
//  CourseDetailBottomSheetReducer.swift
//  Rodi
//

import Foundation

struct CourseDetailBottomSheetReducer: Reducer {
    enum Presentation: Equatable {
        case sheet
        case expandedDetail
        case allReviews
        case reportForm
    }

    struct ReviewPageState: Equatable {
        var items: [PlaceReviewItem] = []
        var hasNext = false
        var nextCursor: String?
        var totalCount: Int?
        var isInitialLoading = false
        var isLoadingNextPage = false
        var errorMessage: String?
    }

    struct ReviewSummaryState: Equatable {
        var value: PlaceReviewSummary?
        var isLoading = false
        var errorMessage: String?
    }

    enum ReportFormState: Equatable {
        case idle
        case loading
        case loaded(ReviewReportForm)
        case failed
    }

    struct State {
        var detail: PlaceDetail?
        var routeOverlay: RodiRouteOverlay?
        var isRouteLoading = false
        var routeStatusMessage: String?
        var isBookmarkUpdating = false
        var isPracticeRegistrationPending = false
        var practiceRegistrationRequestRevision = UUID()

        var presentation: Presentation = .sheet
        var isRouteTimelineExpanded = false

        var selectedReviewLevel: ReviewLevelFilter = .current
        var reviewSummaries: [ReviewLevelFilter: ReviewSummaryState] = [:]
        var reviewPages: [ReviewLevelFilter: ReviewPageState] = [:]
        var reviewRequestRevision = UUID()

        var reportReturnPresentation: Presentation?
        var reportTargetReviewID: Int?
        var reportFormState: ReportFormState = .idle
        var selectedReportOption: ReviewReportOption?
        var reportDetail = ""
        var isReportSubmitting = false
        var isRefreshingReportedReviews = false
        var isReportCompletionPresented = false
        var reportRequestRevision = UUID()
        var shouldReloadReviewsAfterReportCompletion = false
        var reportedReviewIDs: Set<Int> = []

        var blockTargetMemberID: Int?
        var isBlockConfirmationPresented = false
        var isBlockingMember = false
        var blockRequestRevision = UUID()
        var blockedMemberIDs: Set<Int> = []

        var canSubmitReport: Bool {
            guard let selectedReportOption else { return false }
            guard selectedReportOption.requiresTextInput else { return true }
            return !reportDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var reportDetailMaximumLength: Int? {
            guard let selectedReportOption,
                  selectedReportOption.requiresTextInput
            else {
                return nil
            }
            return min(selectedReportOption.textInputMaxLength ?? 100, 100)
        }
    }

    enum Action {
        case present(PlaceDetail, source: String)
        case dismiss
        case cancelRoadRouteLoading
        case cancelReviewLoading
        case toggleBookmark
        case bookmarkUpdated(placeID: Int, isBookmarked: Bool, source: String)
        case bookmarkFailed(previousDetail: PlaceDetail, message: String)
        case roadRouteLoaded(courseID: Int, path: [RodiCoordinate])
        case roadRouteFailed(courseID: Int, message: String?)
        case externalRouteGuidanceOpened(placeID: Int)
        case practiceRegistrationCompleted(PracticeRegistrationResult, placeID: Int, revision: UUID)
        case cancelPracticeRegistration

        case expandRequested
        case collapseRequested
        case routeTimelineToggled
        case allReviewsRequested
        case reviewLevelSelected(ReviewLevelFilter)
        case reviewsRetryRequested
        case nextReviewPageRequested
        case reviewSummaryLoaded(ReviewSummaryResult, placeID: Int, level: ReviewLevelFilter, revision: UUID)
        case reviewPageLoaded(ReviewPageResult, placeID: Int, level: ReviewLevelFilter, isNextPage: Bool, revision: UUID)
        case reviewWritingRequested
        case reviewReportRequested(reviewID: Int)
        case reviewBlockRequested(reviewID: Int)
        case reviewBlockCancelled
        case reviewBlockConfirmed
        case memberBlockCompleted(BlockMemberResult, memberID: Int, revision: UUID)
        case reportBackTapped
        case reportFormRetryTapped
        case reportFormLoaded(ReportFormResult, reviewID: Int, revision: UUID)
        case reportOptionSelected(ReviewReportOption)
        case reportDetailChanged(String)
        case reportSubmitTapped
        case reportSubmissionCompleted(ReportSubmissionResult, reviewID: Int, revision: UUID)
        case reportReviewsRefreshed(ReportRefreshResult, reviewID: Int, placeID: Int, level: ReviewLevelFilter, revision: UUID)
        case reportCompletionConfirmed
        case cancelReportWorkflow
        case cancelBlockWorkflow

        case delegate(Delegate)
    }

    enum Delegate {
        case dismissed
        case routeOverlayChanged(RodiRouteOverlay?)
        case requestAuthentication
        case showSnackbar(String)
        case reviewWritingRequested(ReviewWriteRequest)
    }

    enum ReviewSummaryResult {
        case success(PlaceReviewSummary)
        case failure(String)
    }

    enum ReviewPageResult {
        case success(PlaceReviewPage)
        case failure(String)
    }

    enum ReportFormResult {
        case success(ReviewReportForm)
        case failure(String)
    }

    enum ReportSubmissionResult {
        case success
        case failure(String)
    }

    enum ReportRefreshResult {
        case success(PlaceReviewSummary, PlaceReviewPage)
        case failure
    }

    enum BlockMemberResult {
        case success
        case failure(String)
    }

    enum PracticeRegistrationResult {
        case success
        case failure(String)
    }

    private enum EffectID: Hashable {
        case reviewLoading
        case reportWorkflow
        case blockWorkflow
        case practiceRegistration
    }

    private let placeRepository: PlaceRepository
    private let memberRepository: MemberRepository
    private let practiceRepository: PracticeRepository
    private let reviewRepository: ReviewRepository
    private let hasActiveSession: () -> Bool
    private let onDelegate: (Delegate) -> Void

    init(
        placeRepository: PlaceRepository,
        memberRepository: MemberRepository,
        practiceRepository: PracticeRepository,
        reviewRepository: ReviewRepository,
        hasActiveSession: @escaping () -> Bool,
        onDelegate: @escaping (Delegate) -> Void = { _ in }
    ) {
        self.placeRepository = placeRepository
        self.memberRepository = memberRepository
        self.practiceRepository = practiceRepository
        self.reviewRepository = reviewRepository
        self.hasActiveSession = hasActiveSession
        self.onDelegate = onDelegate
    }
}

// MARK: - Reduce
extension CourseDetailBottomSheetReducer {

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .present(let detail, _):
            guard detail.type == .course else { return .none }
            state = State(detail: detail)
            let item = RodiCourseItem(placeDetail: detail)
            RodiAnalytics.track(.placeDetailOpened(source: "home", placeType: detail.type.rawValue))
            return configureRoute(for: item, state: &state)

        case .dismiss:
            guard state.detail != nil else { return .none }
            state = State()
            return .run { send in
                await send(.cancelRoadRouteLoading)
                await send(.cancelPracticeRegistration)
                await send(.cancelReviewLoading)
                await send(.cancelReportWorkflow)
                await send(.cancelBlockWorkflow)
                await send(.delegate(.dismissed))
            }

        case .cancelRoadRouteLoading:
            return .cancel(id: BottomSheetEffectID.routeLoading)

        case .cancelPracticeRegistration:
            return .cancel(id: EffectID.practiceRegistration)

        case .cancelReviewLoading:
            return .cancel(id: EffectID.reviewLoading)

        case .cancelReportWorkflow:
            return .cancel(id: EffectID.reportWorkflow)

        case .cancelBlockWorkflow:
            return .cancel(id: EffectID.blockWorkflow)

        case .toggleBookmark:
            guard let detail = state.detail, !state.isBookmarkUpdating else { return .none }
            guard hasActiveSession() else { return .send(.delegate(.requestAuthentication)) }
            let previousDetail = detail
            let isBookmarked = !detail.isBookmarked
            state.detail = detail.updatingBookmark(isBookmarked: isBookmarked)
            state.isBookmarkUpdating = true
            return updateBookmarkEffect(placeID: detail.id, isBookmarked: isBookmarked, previousDetail: previousDetail)

        case .bookmarkUpdated(let id, let isBookmarked, let source):
            guard state.detail?.id == id else { return .none }
            state.detail = state.detail?.updatingBookmark(isBookmarked: isBookmarked)
            state.isBookmarkUpdating = false
            RodiAnalytics.track(.bookmarkUpdated(isBookmarked: isBookmarked, source: source, placeType: PlaceType.course.rawValue))
            return .send(.delegate(.showSnackbar(isBookmarked ? "북마크를 저장했어요." : "북마크를 해제했어요.")))

        case .bookmarkFailed(let previousDetail, let message):
            guard state.detail?.id == previousDetail.id else { return .none }
            state.detail = previousDetail
            state.isBookmarkUpdating = false
            return .send(.delegate(.showSnackbar(message)))

        case .roadRouteLoaded(let courseID, let path):
            guard let overlay = state.routeOverlay, overlay.courseID == courseID else { return .none }
            state.routeOverlay = RodiRouteOverlay(courseID: courseID, points: overlay.points, path: path, isRoadRoute: true)
            state.isRouteLoading = false
            state.routeStatusMessage = nil
            return .send(.delegate(.routeOverlayChanged(state.routeOverlay)))

        case .roadRouteFailed(let courseID, let message):
            guard state.routeOverlay?.courseID == courseID else { return .none }
            state.isRouteLoading = false
            state.routeStatusMessage = message
            return .send(.delegate(.routeOverlayChanged(state.routeOverlay)))

        case .externalRouteGuidanceOpened(let placeID):
            guard state.detail?.id == placeID,
                  !state.isPracticeRegistrationPending
            else {
                return .none
            }
            guard hasActiveSession() else { return .send(.delegate(.requestAuthentication)) }
            state.isPracticeRegistrationPending = true
            let revision = UUID()
            state.practiceRegistrationRequestRevision = revision
            return registerPracticeEffect(placeID: placeID, revision: revision)

        case let .practiceRegistrationCompleted(result, placeID, revision):
            guard state.detail?.id == placeID,
                  state.practiceRegistrationRequestRevision == revision,
                  state.isPracticeRegistrationPending
            else {
                return .none
            }
            state.isPracticeRegistrationPending = false
            if case .failure(let message) = result {
                return .send(.delegate(.showSnackbar(message)))
            }

        case .expandRequested:
            guard state.detail != nil, state.presentation == .sheet else { return .none }
            state.presentation = .expandedDetail
            return loadInitialReviewsIfNeeded(state: &state)

        case .collapseRequested:
            switch state.presentation {
            case .sheet:
                return .none
            case .expandedDetail:
                state.presentation = .sheet
            case .allReviews:
                state.presentation = .expandedDetail
            case .reportForm:
                return returnFromReportForm(state: &state)
            }

        case .routeTimelineToggled:
            guard state.presentation == .expandedDetail else { return .none }
            state.isRouteTimelineExpanded.toggle()

        case .allReviewsRequested:
            guard state.presentation == .expandedDetail,
                  (state.reviewSummaries[state.selectedReviewLevel]?.value?.totalReviewCount ?? 0) > 0
            else {
                return .none
            }
            state.presentation = .allReviews
            return loadInitialReviewsIfNeeded(state: &state)

        case .reviewLevelSelected(let level):
            guard state.presentation != .sheet,
                  state.selectedReviewLevel != level
            else {
                return .none
            }
            resetInitialLoading(for: state.selectedReviewLevel, state: &state)
            state.selectedReviewLevel = level
            state.reviewRequestRevision = UUID()
            return loadInitialReviewsIfNeeded(state: &state)

        case .reviewsRetryRequested:
            guard state.presentation != .sheet else { return .none }
            state.reviewSummaries[state.selectedReviewLevel] = .init()
            state.reviewPages[state.selectedReviewLevel] = nil
            return loadInitialReviews(state: &state, force: true)

        case .nextReviewPageRequested:
            guard state.presentation == .allReviews,
                  let detail = state.detail,
                  var page = state.reviewPages[state.selectedReviewLevel],
                  page.hasNext,
                  !page.isLoadingNextPage,
                  let cursor = page.nextCursor
            else {
                return .none
            }
            page.isLoadingNextPage = true
            page.errorMessage = nil
            state.reviewPages[state.selectedReviewLevel] = page
            return loadReviewPageEffect(
                placeID: detail.id,
                level: state.selectedReviewLevel,
                cursor: cursor,
                isNextPage: true,
                revision: state.reviewRequestRevision
            )

        case let .reviewSummaryLoaded(result, placeID, level, revision):
            guard state.detail?.id == placeID,
                  state.selectedReviewLevel == level,
                  state.reviewRequestRevision == revision
            else {
                return .none
            }
            var summaryState = state.reviewSummaries[level] ?? .init()
            summaryState.isLoading = false
            switch result {
            case .success(let summary):
                summaryState.value = summary
                summaryState.errorMessage = nil
            case .failure(let message):
                summaryState.errorMessage = message
            }
            state.reviewSummaries[level] = summaryState

        case let .reviewPageLoaded(result, placeID, level, isNextPage, revision):
            guard state.detail?.id == placeID,
                  state.selectedReviewLevel == level,
                  state.reviewRequestRevision == revision
            else {
                return .none
            }
            var page = state.reviewPages[level] ?? .init()
            page.isInitialLoading = false
            page.isLoadingNextPage = false

            switch result {
            case .success(let response):
                let items = response.items.filter {
                    !state.reportedReviewIDs.contains($0.id) && !state.blockedMemberIDs.contains($0.memberID)
                }
                page.items = isNextPage ? page.items + items : items
                page.hasNext = response.hasNext
                page.nextCursor = response.nextCursor
                page.totalCount = response.totalCount ?? page.totalCount
                page.errorMessage = nil
            case .failure(let message):
                page.errorMessage = message
            }
            state.reviewPages[level] = page

        case .reviewWritingRequested:
            guard let detail = state.detail else { return .none }
            guard hasActiveSession() else { return .send(.delegate(.requestAuthentication)) }
            return .send(
                .delegate(
                    .reviewWritingRequested(
                        .init(placeID: detail.id, placeName: detail.name)
                    )
                )
            )

        case .reviewReportRequested(let reviewID):
            guard state.presentation == .expandedDetail || state.presentation == .allReviews,
                  !state.isReportSubmitting,
                  !state.isRefreshingReportedReviews
            else {
                return .none
            }
            state.reportReturnPresentation = state.presentation
            state.reportTargetReviewID = reviewID
            state.reportFormState = .loading
            state.selectedReportOption = nil
            state.reportDetail = ""
            state.isReportCompletionPresented = false
            state.shouldReloadReviewsAfterReportCompletion = false
            let revision = UUID()
            state.reportRequestRevision = revision
            state.presentation = .reportForm
            return loadReportFormEffect(reviewID: reviewID, revision: revision)

        case .reviewBlockRequested(let reviewID):
            guard state.presentation == .expandedDetail || state.presentation == .allReviews,
                  !state.isBlockConfirmationPresented,
                  !state.isBlockingMember,
                  let memberID = reviewItem(id: reviewID, state: state)?.memberID
            else {
                return .none
            }
            guard hasActiveSession() else { return .send(.delegate(.requestAuthentication)) }
            state.blockTargetMemberID = memberID
            state.isBlockConfirmationPresented = true

        case .reviewBlockCancelled:
            guard state.isBlockConfirmationPresented, !state.isBlockingMember else { return .none }
            clearBlockConfirmation(state: &state)

        case .reviewBlockConfirmed:
            guard state.isBlockConfirmationPresented,
                  !state.isBlockingMember,
                  let memberID = state.blockTargetMemberID
            else {
                return .none
            }
            state.isBlockingMember = true
            let revision = UUID()
            state.blockRequestRevision = revision
            return blockMemberEffect(memberID: memberID, revision: revision)

        case let .memberBlockCompleted(result, memberID, revision):
            guard state.isBlockConfirmationPresented,
                  state.blockTargetMemberID == memberID,
                  state.blockRequestRevision == revision,
                  state.isBlockingMember
            else {
                return .none
            }
            state.isBlockingMember = false
            switch result {
            case .success:
                state.blockedMemberIDs.insert(memberID)
                removeBlockedMember(memberID, state: &state)
                clearBlockConfirmation(state: &state)
            case .failure(let message):
                return .send(.delegate(.showSnackbar(message)))
            }

        case .reportBackTapped:
            guard state.presentation == .reportForm,
                  !state.isReportSubmitting,
                  !state.isRefreshingReportedReviews
            else {
                return .none
            }
            return returnFromReportForm(state: &state)

        case .reportFormRetryTapped:
            guard state.presentation == .reportForm,
                  let reviewID = state.reportTargetReviewID,
                  state.reportFormState != .loading
            else {
                return .none
            }
            state.reportFormState = .loading
            let revision = UUID()
            state.reportRequestRevision = revision
            return loadReportFormEffect(reviewID: reviewID, revision: revision)

        case let .reportFormLoaded(result, reviewID, revision):
            guard state.presentation == .reportForm,
                  state.reportTargetReviewID == reviewID,
                  state.reportRequestRevision == revision
            else {
                return .none
            }
            switch result {
            case .success(let form):
                state.reportFormState = .loaded(form)
            case .failure(let message):
                state.reportFormState = .failed
                return .send(.delegate(.showSnackbar(message)))
            }

        case .reportOptionSelected(let option):
            guard case let .loaded(form) = state.reportFormState,
                  form.options.contains(where: { $0.code == option.code })
            else {
                return .none
            }
            state.selectedReportOption = option
            if !option.requiresTextInput {
                state.reportDetail = ""
            }

        case .reportDetailChanged(let detail):
            guard let option = state.selectedReportOption,
                  option.requiresTextInput,
                  state.reportDetailMaximumLength.map({ detail.count <= $0 }) ?? true
            else {
                return .none
            }
            state.reportDetail = detail

        case .reportSubmitTapped:
            guard state.presentation == .reportForm,
                  state.canSubmitReport,
                  !state.isReportSubmitting,
                  !state.isRefreshingReportedReviews,
                  let reviewID = state.reportTargetReviewID,
                  let option = state.selectedReportOption
            else {
                return .none
            }
            state.isReportSubmitting = true
            let revision = UUID()
            state.reportRequestRevision = revision
            return submitReportEffect(
                reviewID: reviewID,
                submission: .init(
                    reasonCode: option.code,
                    detail: option.requiresTextInput ? normalizedOptionalText(state.reportDetail) : nil
                ),
                revision: revision
            )

        case let .reportSubmissionCompleted(result, reviewID, revision):
            guard state.presentation == .reportForm,
                  state.reportTargetReviewID == reviewID,
                  state.reportRequestRevision == revision,
                  state.isReportSubmitting
            else {
                return .none
            }
            state.isReportSubmitting = false
            switch result {
            case .success:
                guard let detail = state.detail else { return .none }
                state.reportedReviewIDs.insert(reviewID)
                removeReportedReview(reviewID, state: &state)
                state.reviewRequestRevision = UUID()
                state.isRefreshingReportedReviews = true
                let refreshRevision = UUID()
                state.reportRequestRevision = refreshRevision
                return refreshReportedReviewsEffect(
                    reviewID: reviewID,
                    placeID: detail.id,
                    level: state.selectedReviewLevel,
                    revision: refreshRevision
                )
            case .failure(let message):
                return .send(.delegate(.showSnackbar(message)))
            }

        case let .reportReviewsRefreshed(result, reviewID, placeID, level, revision):
            guard state.presentation == .reportForm,
                  state.reportTargetReviewID == reviewID,
                  state.detail?.id == placeID,
                  state.selectedReviewLevel == level,
                  state.reportRequestRevision == revision,
                  state.isRefreshingReportedReviews
            else {
                return .none
            }
            state.isRefreshingReportedReviews = false
            switch result {
            case .success(let summary, let page):
                state.reviewSummaries[level] = .init(value: summary)
                state.reviewPages[level] = reviewPage(
                    from: page,
                    removing: state.reportedReviewIDs,
                    blockedMemberIDs: state.blockedMemberIDs
                )
                state.shouldReloadReviewsAfterReportCompletion = false
            case .failure:
                state.reviewSummaries[level] = .init()
                state.reviewPages[level] = nil
                state.shouldReloadReviewsAfterReportCompletion = true
            }
            state.isReportCompletionPresented = true

        case .reportCompletionConfirmed:
            guard state.presentation == .reportForm,
                  state.isReportCompletionPresented
            else {
                return .none
            }
            return returnFromReportForm(state: &state)

        case .delegate(let delegate):
            onDelegate(delegate)
        }

        return .none
    }
}

// MARK: - Effect
private extension CourseDetailBottomSheetReducer {

    func returnFromReportForm(state: inout State) -> Effect<Action> {
        let returnPresentation = state.reportReturnPresentation ?? .expandedDetail
        let shouldReloadReviews = state.shouldReloadReviewsAfterReportCompletion
        clearReportForm(state: &state)
        state.presentation = returnPresentation
        guard shouldReloadReviews else { return .cancel(id: EffectID.reportWorkflow) }
        return loadInitialReviews(state: &state, force: true)
    }

    func clearReportForm(state: inout State) {
        state.reportReturnPresentation = nil
        state.reportTargetReviewID = nil
        state.reportFormState = .idle
        state.selectedReportOption = nil
        state.reportDetail = ""
        state.isReportSubmitting = false
        state.isRefreshingReportedReviews = false
        state.isReportCompletionPresented = false
        state.shouldReloadReviewsAfterReportCompletion = false
        state.reportRequestRevision = UUID()
    }

    func clearBlockConfirmation(state: inout State) {
        state.blockTargetMemberID = nil
        state.isBlockConfirmationPresented = false
        state.isBlockingMember = false
        state.blockRequestRevision = UUID()
    }

    func removeReportedReview(_ reviewID: Int, state: inout State) {
        for level in Array(state.reviewPages.keys) {
            guard var page = state.reviewPages[level] else { continue }
            page.items.removeAll { $0.id == reviewID }
            state.reviewPages[level] = page
        }
    }

    func removeBlockedMember(_ memberID: Int, state: inout State) {
        for level in Array(state.reviewPages.keys) {
            guard var page = state.reviewPages[level] else { continue }
            page.items.removeAll { $0.memberID == memberID }
            state.reviewPages[level] = page
        }
    }

    func reviewItem(id reviewID: Int, state: State) -> PlaceReviewItem? {
        state.reviewPages.values
            .lazy
            .flatMap(\.items)
            .first { $0.id == reviewID }
    }

    func reviewPage(
        from page: PlaceReviewPage,
        removing reportedReviewIDs: Set<Int>,
        blockedMemberIDs: Set<Int>
    ) -> ReviewPageState {
        .init(
            items: page.items.filter { !reportedReviewIDs.contains($0.id) && !blockedMemberIDs.contains($0.memberID) },
            hasNext: page.hasNext,
            nextCursor: page.nextCursor,
            totalCount: page.totalCount
        )
    }

    func normalizedOptionalText(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func configureRoute(for item: RodiCourseItem, state: inout State) -> Effect<Action> {
        let points = item.routeOverlayPoints
        guard points.count >= 2 else {
            state.routeOverlay = nil
            state.isRouteLoading = false
            state.routeStatusMessage = "경로 좌표가 아직 준비되지 않았어요."
            return .cancel(id: BottomSheetEffectID.routeLoading)
        }
        state.routeOverlay = RodiRouteOverlay(courseID: item.id, points: points, path: points.map(\.coordinate), isRoadRoute: false)
        state.isRouteLoading = true
        return loadRoadRouteEffect(courseID: item.id, points: points)
    }

    func updateBookmarkEffect(placeID: Int, isBookmarked: Bool, previousDetail: PlaceDetail) -> Effect<Action> {
        let repository = placeRepository
        return .run { send in
            do {
                if isBookmarked { try await repository.bookmark(placeID: placeID) }
                else { try await repository.unbookmark(placeID: placeID) }
                await send(.bookmarkUpdated(placeID: placeID, isBookmarked: isBookmarked, source: "home"))
            } catch is CancellationError {
                return
            } catch {
                if requiresAuthentication(error) { await send(.delegate(.requestAuthentication)) }
                else { await send(.bookmarkFailed(previousDetail: previousDetail, message: "북마크를 \(isBookmarked ? "저장" : "해제")하지 못했어요.")) }
            }
        }
        .cancelTask(id: BottomSheetEffectID.bookmarkUpdating)
    }

    func registerPracticeEffect(placeID: Int, revision: UUID) -> Effect<Action> {
        let repository = practiceRepository
        return .run { send in
            do {
                _ = try await repository.register(placeID: placeID)
                await send(.practiceRegistrationCompleted(.success, placeID: placeID, revision: revision))
            } catch is CancellationError {
                return
            } catch let error as NetworkError {
                if requiresAuthentication(error) {
                    await send(.delegate(.requestAuthentication))
                }
                await send(.practiceRegistrationCompleted(
                    .failure("연습 목록에 담지 못했어요. 다시 시도해주세요."),
                    placeID: placeID,
                    revision: revision
                ))
            } catch {
                await send(.practiceRegistrationCompleted(
                    .failure("연습 목록에 담지 못했어요. 다시 시도해주세요."),
                    placeID: placeID,
                    revision: revision
                ))
            }
        }
        .cancelTask(id: EffectID.practiceRegistration)
    }

    func loadRoadRouteEffect(courseID: Int, points: [RodiRouteOverlayPoint]) -> Effect<Action> {
        .run { send in
            do {
                let path = try await KakaoDirectionsService().fetchRoute(points: points)
                await send(.roadRouteLoaded(courseID: courseID, path: path))
            } catch is CancellationError {
                return
            } catch let error as KakaoDirectionsError {
                await send(.roadRouteFailed(courseID: courseID, message: error.fallbackMessage))
            } catch {
                await send(.roadRouteFailed(courseID: courseID, message: "도로 경로를 불러오지 못해 대체 경로로 표시 중이에요."))
            }
        }
        .cancelTask(id: BottomSheetEffectID.routeLoading)
    }

    func loadInitialReviewsIfNeeded(state: inout State) -> Effect<Action> {
        let level = state.selectedReviewLevel
        let summaryState = state.reviewSummaries[level] ?? .init()
        let page = state.reviewPages[level]

        guard !summaryState.isLoading,
              page?.isInitialLoading != true,
              summaryState.value == nil || page == nil
        else {
            return .none
        }
        return loadInitialReviews(state: &state, force: false)
    }

    func loadInitialReviews(state: inout State, force: Bool) -> Effect<Action> {
        guard let detail = state.detail else { return .none }

        let level = state.selectedReviewLevel
        let needsSummary = force || state.reviewSummaries[level]?.value == nil
        let needsPage = force || state.reviewPages[level] == nil

        guard needsSummary || needsPage else {
            return .none
        }

        let revision = UUID()
        state.reviewRequestRevision = revision

        if needsSummary {
            var summaryState = state.reviewSummaries[level] ?? .init()
            summaryState.value = force ? nil : summaryState.value
            summaryState.isLoading = true
            summaryState.errorMessage = nil
            state.reviewSummaries[level] = summaryState
        }

        if needsPage {
            var page = state.reviewPages[level] ?? .init()
            page.isInitialLoading = true
            page.isLoadingNextPage = false
            page.errorMessage = nil
            if force {
                page.items = []
                page.hasNext = false
                page.nextCursor = nil
                page.totalCount = nil
            }
            state.reviewPages[level] = page
        }
        return loadInitialReviewsEffect(
            placeID: detail.id,
            level: level,
            needsSummary: needsSummary,
            needsPage: needsPage,
            revision: revision
        )
    }

    func loadInitialReviewsEffect(
        placeID: Int,
        level: ReviewLevelFilter,
        needsSummary: Bool,
        needsPage: Bool,
        revision: UUID
    ) -> Effect<Action> {
        let repository = reviewRepository
        return .run { send in
            if needsSummary && needsPage {
                async let summaryResult = reviewSummaryResult(
                    repository: repository,
                    placeID: placeID,
                    level: level
                )
                async let pageResult = firstReviewPageResult(
                    repository: repository,
                    placeID: placeID,
                    level: level
                )

                let (summary, page) = await (summaryResult, pageResult)
                guard !Task.isCancelled else { return }
                await send(.reviewSummaryLoaded(summary, placeID: placeID, level: level, revision: revision))
                await send(.reviewPageLoaded(page, placeID: placeID, level: level, isNextPage: false, revision: revision))
            } else if needsSummary {
                let summary = await reviewSummaryResult(
                    repository: repository,
                    placeID: placeID,
                    level: level
                )
                guard !Task.isCancelled else { return }
                await send(.reviewSummaryLoaded(summary, placeID: placeID, level: level, revision: revision))
            } else if needsPage {
                let page = await firstReviewPageResult(
                    repository: repository,
                    placeID: placeID,
                    level: level
                )
                guard !Task.isCancelled else { return }
                await send(.reviewPageLoaded(page, placeID: placeID, level: level, isNextPage: false, revision: revision))
            }
        }
        .cancelTask(id: EffectID.reviewLoading)
    }

    func reviewSummaryResult(
        repository: ReviewRepository,
        placeID: Int,
        level: ReviewLevelFilter
    ) async -> ReviewSummaryResult {
        do {
            return .success(try await repository.fetchSummary(placeID: placeID, level: level))
        } catch {
            return .failure("후기 요약을 불러오지 못했어요.")
        }
    }

    func firstReviewPageResult(
        repository: ReviewRepository,
        placeID: Int,
        level: ReviewLevelFilter
    ) async -> ReviewPageResult {
        do {
            return .success(try await repository.fetchReviews(
                placeID: placeID,
                query: PlaceReviewQuery(level: level)
            ))
        } catch {
            return .failure("후기를 불러오지 못했어요.")
        }
    }

    func resetInitialLoading(for level: ReviewLevelFilter, state: inout State) {
        if var summaryState = state.reviewSummaries[level] {
            summaryState.isLoading = false
            state.reviewSummaries[level] = summaryState
        }
        if var page = state.reviewPages[level] {
            page.isInitialLoading = false
            page.isLoadingNextPage = false
            state.reviewPages[level] = page
        }
    }

    func loadReviewPageEffect(
        placeID: Int,
        level: ReviewLevelFilter,
        cursor: String,
        isNextPage: Bool,
        revision: UUID
    ) -> Effect<Action> {
        let repository = reviewRepository
        return .run { send in
            do {
                let page = try await repository.fetchReviews(
                    placeID: placeID,
                    query: PlaceReviewQuery(level: level, cursor: cursor)
                )
                await send(.reviewPageLoaded(
                    .success(page),
                    placeID: placeID,
                    level: level,
                    isNextPage: isNextPage,
                    revision: revision
                ))
            } catch is CancellationError {
                return
            } catch {
                await send(.reviewPageLoaded(
                    .failure("후기를 더 불러오지 못했어요."),
                    placeID: placeID,
                    level: level,
                    isNextPage: isNextPage,
                    revision: revision
                ))
            }
        }
        .cancelTask(id: EffectID.reviewLoading)
    }

    func blockMemberEffect(memberID: Int, revision: UUID) -> Effect<Action> {
        let repository = memberRepository
        return .run { send in
            do {
                try await repository.block(memberID: memberID)
                await send(.memberBlockCompleted(.success, memberID: memberID, revision: revision))
            } catch is CancellationError {
                return
            } catch let error as NetworkError {
                if requiresAuthentication(error) {
                    await send(.delegate(.requestAuthentication))
                }
                await send(.memberBlockCompleted(
                    .failure("사용자를 차단하지 못했어요. 다시 시도해주세요."),
                    memberID: memberID,
                    revision: revision
                ))
            } catch {
                await send(.memberBlockCompleted(
                    .failure("사용자를 차단하지 못했어요. 다시 시도해주세요."),
                    memberID: memberID,
                    revision: revision
                ))
            }
        }
        .cancelTask(id: EffectID.blockWorkflow)
    }

    func loadReportFormEffect(
        reviewID: Int,
        revision: UUID
    ) -> Effect<Action> {
        let repository = reviewRepository
        return .run { send in
            do {
                let form = try await repository.fetchReportForm()
                await send(.reportFormLoaded(.success(form), reviewID: reviewID, revision: revision))
            } catch is CancellationError {
                return
            } catch let error as NetworkError {
                if requiresAuthentication(error) {
                    await send(.delegate(.requestAuthentication))
                }
                await send(.reportFormLoaded(
                    .failure("신고 사유를 불러오지 못했어요. 다시 시도해주세요."),
                    reviewID: reviewID,
                    revision: revision
                ))
            } catch {
                await send(.reportFormLoaded(
                    .failure("신고 사유를 불러오지 못했어요. 다시 시도해주세요."),
                    reviewID: reviewID,
                    revision: revision
                ))
            }
        }
        .cancelTask(id: EffectID.reportWorkflow)
    }

    func submitReportEffect(
        reviewID: Int,
        submission: ReviewReportSubmission,
        revision: UUID
    ) -> Effect<Action> {
        let repository = reviewRepository
        return .run { send in
            do {
                try await repository.report(reviewID: reviewID, submission: submission)
                await send(.reportSubmissionCompleted(.success, reviewID: reviewID, revision: revision))
            } catch is CancellationError {
                return
            } catch let error as NetworkError {
                if requiresAuthentication(error) {
                    await send(.delegate(.requestAuthentication))
                }
                await send(.reportSubmissionCompleted(
                    .failure(error.localizedDescription),
                    reviewID: reviewID,
                    revision: revision
                ))
            } catch {
                await send(.reportSubmissionCompleted(
                    .failure("후기를 신고하지 못했어요. 다시 시도해주세요."),
                    reviewID: reviewID,
                    revision: revision
                ))
            }
        }
        .cancelTask(id: EffectID.reportWorkflow)
    }

    func refreshReportedReviewsEffect(
        reviewID: Int,
        placeID: Int,
        level: ReviewLevelFilter,
        revision: UUID
    ) -> Effect<Action> {
        let repository = reviewRepository
        return .run { send in
            do {
                async let summary = repository.fetchSummary(placeID: placeID, level: level)
                async let page = repository.fetchReviews(
                    placeID: placeID,
                    query: PlaceReviewQuery(level: level)
                )
                let (resolvedSummary, resolvedPage) = try await (summary, page)
                await send(.reportReviewsRefreshed(
                    .success(resolvedSummary, resolvedPage),
                    reviewID: reviewID,
                    placeID: placeID,
                    level: level,
                    revision: revision
                ))
            } catch is CancellationError {
                return
            } catch let error as NetworkError {
                if requiresAuthentication(error) {
                    await send(.delegate(.requestAuthentication))
                }
                await send(.reportReviewsRefreshed(
                    .failure,
                    reviewID: reviewID,
                    placeID: placeID,
                    level: level,
                    revision: revision
                ))
            } catch {
                await send(.reportReviewsRefreshed(
                    .failure,
                    reviewID: reviewID,
                    placeID: placeID,
                    level: level,
                    revision: revision
                ))
            }
        }
        .cancelTask(id: EffectID.reportWorkflow)
    }

    func requiresAuthentication(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkError else { return false }
        return switch networkError {
        case .refreshFailGoRoot, .httpStatusCode(401): true
        case .apiError(let code, _, _): code.hasPrefix("AUTH_401") || code == "AUTH_400_1"
        default: false
        }
    }
}
