//
//  ReviewFlowCoordinatorReducer.swift
//  Rodi
//

import Foundation

/// 전역 후기 flow의 진입 출처, 완료 갱신, snackbar와 연습 복귀 정책을 중재한다.
struct ReviewFlowCoordinatorReducer: Reducer {

    struct State {
        var review = ReviewReducer.State()
        var entrySource: ReviewFlowEntrySource?
        var snackbarMessage: String?
        var homeFinishedRequestID = 0
        var myPracticeRecordsFinishedRequestID = 0
        var myPostsFinishedRequestID = 0
        var completionRefreshFlowID: UUID?
    }

    enum Action {
        case debugPromptRequested
        case requested(ReviewFlowRequest)
        case review(ReviewReducer.Action)
        case practiceReturnPromptRequested(PracticeReturnPrompt)
        case practiceReturnPromptInteractionResolved(PracticeReturnPromptInteraction)
        case practiceReturnVisitSubmissionChanged(Bool)
        case practiceReturnFinishedWithoutReview(String)
        case externalSnackbarRequested(String)
        case completionRefreshCompleted(flowID: UUID)
        case snackbarDismissed(String)
        case delegate(Delegate)
    }

    enum Delegate {
        case practiceReturnPromptInteractionRequested(PracticeReturnPromptInteraction)
    }

    private enum EffectID {
        case snackbar
        case completionRefresh
    }

    private let reviewReducer: ReviewReducer
    private let refreshService: ReviewFlowRefreshServicing

    init(
        reviewReducer: ReviewReducer,
        refreshService: ReviewFlowRefreshServicing
    ) {
        self.reviewReducer = reviewReducer
        self.refreshService = refreshService
    }
}

// MARK: - Reduce
extension ReviewFlowCoordinatorReducer {

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .debugPromptRequested:
            #if DEBUG
            guard state.review.route == .hidden else { return .none }
            state.entrySource = .home
            return reduceReview(&state, action: .debugPromptRequested)
            #else
            return .none
            #endif

        case .requested(let request):
            guard state.review.route == .hidden else { return .none }
            state.entrySource = request.entrySource
            switch request.entry {
            case .writing(let request):
                return reduceReview(&state, action: .directWritingRequested(request))
            case .editing(let reviewID):
                return reduceReview(&state, action: .editingRequested(reviewID: reviewID))
            }

        case .review(let action):
            if let promptInteraction = promptInteraction(for: action) {
                return .send(.delegate(.practiceReturnPromptInteractionRequested(promptInteraction)))
            }
            return reduceReview(&state, action: action)

        case .practiceReturnPromptRequested(let prompt):
            guard state.review.route == .hidden else { return .none }
            state.entrySource = .home
            return reduceReview(
                &state,
                action: .promptRequested(
                    placeID: prompt.placeID,
                    placeName: prompt.placeName,
                    allowsSkipReason: prompt.allowsSkipReason,
                    allowsReviewWriting: prompt.allowsReviewWriting,
                    visitedSnackbarMessage: prompt.visitedSnackbarMessage
                )
            )

        case .practiceReturnPromptInteractionResolved(let interaction):
            return reduceReview(&state, action: reviewPromptAction(for: interaction))

        case .practiceReturnVisitSubmissionChanged(let isSubmitting):
            return reduceReview(&state, action: .prompt(.visitSubmissionChanged(isSubmitting)))

        case .practiceReturnFinishedWithoutReview(let message):
            state.review = .init()
            state.entrySource = nil
            state.homeFinishedRequestID += 1
            return presentSnackbar(message, state: &state)

        case .externalSnackbarRequested(let message):
            return presentSnackbar(message, state: &state)

        case .completionRefreshCompleted(let flowID):
            guard state.completionRefreshFlowID == flowID else { return .none }
            state.completionRefreshFlowID = nil
            return reduceReview(&state, action: .writing(.completionRefreshFinished(flowID: flowID)))

        case .snackbarDismissed(let message):
            guard state.snackbarMessage == message else { return .none }
            state.snackbarMessage = nil
            return .none

        case .delegate:
            return .none
        }
    }
}

// MARK: - Child Delegate
private extension ReviewFlowCoordinatorReducer {

    func reduceReview(
        _ state: inout State,
        action: ReviewReducer.Action
    ) -> Effect<Action> {
        if case .delegate(let delegate) = action {
            return reduceReviewDelegate(delegate, state: &state)
        }
        return reviewReducer.reduce(&state.review, with: action).map(Action.review)
    }

    func reduceReviewDelegate(
        _ delegate: ReviewReducer.Delegate,
        state: inout State
    ) -> Effect<Action> {
        switch delegate {
        case .finished:
            finishReviewFlow(state: &state)
            return .none

        case .completionRefreshRequested(let target, let flowID):
            guard state.completionRefreshFlowID == nil,
                  let entrySource = state.entrySource
            else { return .none }
            state.completionRefreshFlowID = flowID
            let refreshService = refreshService
            return .run { send in
                await refreshService.refresh(entrySource: entrySource, placeID: target.placeID)
                await send(.completionRefreshCompleted(flowID: flowID))
            }
            .cancelTask(id: EffectID.completionRefresh)

        case .showSnackbar(let message), .visitedWithoutReview(let message):
            return presentSnackbar(message, state: &state)

        case .editingFailed(let message):
            state.review = .init()
            state.entrySource = nil
            return presentSnackbar(message, state: &state)
        }
    }

}

// MARK: - State
private extension ReviewFlowCoordinatorReducer {

    func finishReviewFlow(state: inout State) {
        let entrySource = state.entrySource
        state.review = .init()
        state.entrySource = nil
        state.completionRefreshFlowID = nil

        switch entrySource {
        case .home, .courseDetail:
            state.homeFinishedRequestID += 1
        case .my:
            state.myPracticeRecordsFinishedRequestID += 1
            state.myPostsFinishedRequestID += 1
        case .myPosts:
            state.myPostsFinishedRequestID += 1
        case nil:
            break
        }
    }

    func presentSnackbar(_ message: String, state: inout State) -> Effect<Action> {
        state.snackbarMessage = message
        return .run { send in
            try? await Task.sleep(for: .seconds(3))
            await send(.snackbarDismissed(message))
        }
        .cancelTask(id: EffectID.snackbar)
    }

    func promptInteraction(for action: ReviewReducer.Action) -> PracticeReturnPromptInteraction? {
        guard case .prompt(let promptAction) = action else { return nil }
        switch promptAction {
        case .visitedTapped:
            return .visited
        case .notVisitedTapped:
            return .notVisited
        case .closeTapped:
            return .closed
        default:
            return nil
        }
    }

    func reviewPromptAction(for interaction: PracticeReturnPromptInteraction) -> ReviewReducer.Action {
        switch interaction {
        case .visited: .prompt(.visitedTapped)
        case .notVisited: .prompt(.notVisitedTapped)
        case .closed: .prompt(.closeTapped)
        }
    }
}
