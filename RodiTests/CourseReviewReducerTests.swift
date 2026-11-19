import XCTest
@testable import Rodi

@MainActor
final class CourseReviewReducerTests: XCTestCase {
    func testFilterResetSendsEmptyTagsWithoutCommittingBeforeSuccess() async {
        var sentTags: [PlacePracticeType]?
        let reducer = FilterBottomSheetReducer(
            memberRepository: MemberRepositoryStub(onSortTagsUpdate: { sentTags = $0 }),
            hasActiveSession: { true }
        )
        var state = FilterBottomSheetReducer.State()
        state.appliedSelection = .default
        state.appliedSelection.toggleType(.merging)
        state.draftSelection = state.appliedSelection

        let effect = reducer.reduce(&state, with: .resetForNationwideBrowse)
        XCTAssertTrue(state.isApplying)
        XCTAssertEqual(state.appliedSelection.filterTags, [.merging])
        guard case .none = reducer.reduce(&state, with: .reset).caseOf else {
            return XCTFail("초기화 중에는 재요청하지 않아야 합니다.")
        }
        guard case let .run(_, task) = effect.caseOf else { return XCTFail("초기화 요청이 필요합니다.") }
        var completion: FilterBottomSheetReducer.Action?
        await task { completion = $0 }
        XCTAssertEqual(sentTags, [])
        guard let completion, case .applied(let selection, true) = completion else { return XCTFail("전국 조회 초기화 성공 결과가 필요합니다.") }
        XCTAssertTrue(selection.filterTags.isEmpty)
        XCTAssertNil(selection.category)
    }

    func testGuestCannotSaveFilterReset() {
        let reducer = FilterBottomSheetReducer(memberRepository: MemberRepositoryStub(), hasActiveSession: { false })
        var state = FilterBottomSheetReducer.State()
        let effect = reducer.reduce(&state, with: .reset)
        guard case .send(.delegate(.requestAuthentication)) = effect.caseOf else {
            return XCTFail("비로그인 초기화는 인증 안내만 전달해야 합니다.")
        }
        XCTAssertFalse(state.isApplying)
    }

    func testFilterSaveFailureDoesNotCommitSelection() async {
        let reducer = FilterBottomSheetReducer(
            memberRepository: MemberRepositoryStub(sortTagsError: .networkUnavailable),
            hasActiveSession: { true }
        )
        var state = FilterBottomSheetReducer.State()
        state.appliedSelection = .default
        state.draftSelection = .default
        state.draftSelection.selectCategory(.parking)
        let effect = reducer.reduce(&state, with: .apply)
        XCTAssertTrue(state.isApplying)
        guard case .none = reducer.reduce(&state, with: .apply).caseOf else {
            return XCTFail("저장 중 중복 요청은 없어야 합니다.")
        }
        guard case let .run(_, task) = effect.caseOf else { return XCTFail("저장 요청이 필요합니다.") }
        var completion: FilterBottomSheetReducer.Action?
        await task { completion = $0 }
        guard let completion, case .failed = completion else { return XCTFail("저장 실패가 필요합니다.") }
        _ = reducer.reduce(&state, with: completion)
        XCTAssertFalse(state.isApplying)
        XCTAssertTrue(state.appliedSelection.filterTags.isEmpty)
        XCTAssertEqual(state.draftSelection.filterTags, [.parking])
    }

    func testReportedReviewIsRemovedAndReturnsToOriginalRoute() {
        let reducer = makeReducer()
        let review = makeReview(id: 10, memberID: 100)
        var state = CourseReviewReducer.State(
            placeID: 1,
            route: .report,
            reportReturnRoute: .preview,
            pages: [.current: .init(items: [review])]
        )

        _ = reducer.reduce(
            &state,
            with: .report(.delegate(.submitted(reviewID: review.id)))
        )

        XCTAssertEqual(state.route, .preview)
        XCTAssertTrue(state.reportedReviewIDs.contains(review.id))
        XCTAssertTrue(state.pages[.current]?.items.isEmpty == true)
    }

    func testBlockedMemberIsRemovedFromEveryCachedLevel() {
        let reducer = makeReducer()
        let blocked = makeReview(id: 10, memberID: 100)
        let remaining = makeReview(id: 11, memberID: 200)
        var state = CourseReviewReducer.State(
            placeID: 1,
            pages: [
                .current: .init(items: [blocked, remaining]),
                .level(.seed): .init(items: [blocked])
            ]
        )

        _ = reducer.reduce(
            &state,
            with: .block(.delegate(.blocked(memberID: blocked.memberID)))
        )

        XCTAssertTrue(state.blockedMemberIDs.contains(blocked.memberID))
        XCTAssertEqual(state.pages[.current]?.items, [remaining])
        XCTAssertTrue(state.pages[.level(.seed)]?.items.isEmpty == true)
    }

    private func makeReducer() -> CourseReviewReducer {
        .init(repository: ReviewRepositoryStub(), memberRepository: MemberRepositoryStub(), hasActiveSession: { true })
    }

    private func makeReview(id: Int, memberID: Int) -> PlaceReviewItem {
        .init(id: id, memberID: memberID, nickname: "테스터", practiceMethod: .solo, content: "후기", isMine: false, isEditable: false, isHidden: false, isVerifiedVisit: false, createdAt: "2026-08-12")
    }
}

private struct ReviewRepositoryStub: ReviewRepository {
    func fetchWritingForm(placeID: Int) async throws(NetworkError) -> ReviewWritingForm { fatalError() }
    func create(placeID: Int, submission: PlaceReviewSubmission) async throws(NetworkError) {}
    func fetchDetail(reviewID: Int) async throws(NetworkError) -> ReviewDetail { fatalError() }
    func update(reviewID: Int, submission: PlaceReviewSubmission) async throws(NetworkError) {}
    func fetchSummary(placeID: Int, level: ReviewLevelFilter) async throws(NetworkError) -> PlaceReviewSummary { fatalError() }
    func fetchReviews(placeID: Int, query: PlaceReviewQuery) async throws(NetworkError) -> PlaceReviewPage { fatalError() }
    func fetchMyReviews(query: MyReviewQuery) async throws(NetworkError) -> MyReviewPage { fatalError() }
    func delete(reviewID: Int) async throws(NetworkError) {}
    func fetchReportForm() async throws(NetworkError) -> ReviewReportForm { fatalError() }
    func report(reviewID: Int, submission: ReviewReportSubmission) async throws(NetworkError) {}
}

private struct MemberRepositoryStub: MemberRepository {
    var sortTagsError: NetworkError? = nil
    var onSortTagsUpdate: (([PlacePracticeType]) -> Void)? = nil
    func fetchOnboardingForm() async throws(NetworkError) -> MemberOnboardingForm { fatalError() }
    func fetchMyProfile() async throws(NetworkError) -> MemberProfile { fatalError() }
    func withdraw() async throws(NetworkError) {}
    func hardWithdraw() async throws(NetworkError) {}
    func block(memberID: Int) async throws(NetworkError) {}
    func fetchBlockedMembers(query: BlockedMemberQuery) async throws(NetworkError) -> BlockedMemberPage { fatalError() }
    func unblock(memberID: Int) async throws(NetworkError) {}
    func updateDrivingGoal(_ drivingGoal: String) async throws(NetworkError) {}
    func updateNickname(_ nickname: String) async throws(NetworkError) -> String { nickname }
    func updatePlaceFilterTags(_ tags: [PlacePracticeType]) async throws(NetworkError) {
        if let sortTagsError { throw sortTagsError }
        onSortTagsUpdate?(tags)
    }
    func submitOnboarding(_ submission: MemberOnboardingSubmission) async throws(NetworkError) {}
    func completeCourseTutorial() async throws(NetworkError) -> CourseTutorialCompletion { fatalError() }
}
