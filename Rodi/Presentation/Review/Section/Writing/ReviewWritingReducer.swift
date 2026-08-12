import Foundation

struct ReviewWritingReducer: Reducer {
    struct State {
        enum Page: Equatable {
            case hidden
            case first
            case second
        }

        var page: Page = .hidden
        var target: ReviewWriteRequest?
        var draft = ReviewDraft()
        var isSubmitting = false
        var isDiscardConfirmationPresented = false
        var isCompletionPresented = false
        var isCompletionDismissing = false
        var flowID = UUID()
        var requestID = 0

        var canSubmit: Bool {
            draft.practiceMethod != nil && !isSubmitting
        }
    }

    enum Action {
        case start(ReviewWriteRequest)
        case recommendationSelected(Bool)
        case difficultySelected(ReviewDifficulty)
        case congestionSelected(ReviewCongestion)
        case cautionChanged(String)
        case nextTapped
        case backTapped
        case practiceMethodSelected(ReviewPracticeMethod)
        case contentChanged(String)
        case closeTapped
        case discardConfirmed
        case discardCancelled
        case submitTapped
        case submissionCompleted(ReviewRequestResult<Void>, flowID: UUID, requestID: Int)
        case completionConfirmed
        case completionDismissed(flowID: UUID, requestID: Int)
        case reset
        case delegate(Delegate)
    }

    enum Delegate {
        case finished
        case showSnackbar(String)
    }

    private enum EffectID {
        case submission
        case completionDismissal
    }

    private let service: any ReviewWritingServicing

    init(service: any ReviewWritingServicing) {
        self.service = service
    }
}

// MARK: - Reduce
extension ReviewWritingReducer {

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .start(let request):
            state = .init(page: .first, target: request, requestID: state.requestID + 1)

        case .recommendationSelected(let value):
            guard state.page == .first else { return .none }
            state.draft.isRecommended = value

        case .difficultySelected(let value):
            guard state.page == .first else { return .none }
            state.draft.difficulty = value

        case .congestionSelected(let value):
            guard state.page == .first else { return .none }
            state.draft.congestion = value

        case .cautionChanged(let value):
            guard state.page == .first else { return .none }
            state.draft.caution = value

        case .nextTapped:
            guard state.page == .first, state.draft.canProceedToSecondPage else { return .none }
            state.page = .second

        case .backTapped:
            guard state.page == .second, !state.isSubmitting else { return .none }
            state.page = .first

        case .practiceMethodSelected(let value):
            guard state.page == .second else { return .none }
            state.draft.practiceMethod = value

        case .contentChanged(let value):
            guard state.page == .second, value.count <= 150 else { return .none }
            state.draft.content = value

        case .closeTapped:
            guard state.page != .hidden,
                  !state.isSubmitting,
                  !state.isCompletionPresented
            else {
                return .none
            }
            state.isDiscardConfirmationPresented = true

        case .discardConfirmed:
            guard state.isDiscardConfirmationPresented else { return .none }
            return .send(.delegate(.finished))

        case .discardCancelled:
            state.isDiscardConfirmationPresented = false

        case .submitTapped:
            guard state.page == .second,
                  state.canSubmit,
                  let target = state.target,
                  let submission = state.draft.submission()
            else {
                return .none
            }
            state.isSubmitting = true
            state.requestID += 1
            return submitEffect(placeID: target.placeID, submission: submission, flowID: state.flowID, requestID: state.requestID)

        case .submissionCompleted(let result, let flowID, let requestID):
            guard state.page == .second,
                  state.isSubmitting,
                  state.flowID == flowID,
                  state.requestID == requestID
            else {
                return .none
            }
            state.isSubmitting = false
            switch result {
            case .success:
                state.isCompletionPresented = true
            case .failure(let message):
                return .send(.delegate(.showSnackbar(message)))
            }

        case .completionConfirmed:
            guard state.isCompletionPresented, !state.isCompletionDismissing else { return .none }
            state.isCompletionPresented = false
            state.isCompletionDismissing = true
            state.requestID += 1
            return completionDismissalEffect(flowID: state.flowID, requestID: state.requestID)

        case .completionDismissed(let flowID, let requestID):
            guard state.isCompletionDismissing,
                  state.flowID == flowID,
                  state.requestID == requestID
            else {
                return .none
            }
            return .send(.delegate(.finished))

        case .reset:
            state = .init()
            return .cancel(id: EffectID.submission)

        case .delegate:
            return .none
        }

        return .none
    }
}

// MARK: - Effect
private extension ReviewWritingReducer {

    func submitEffect(
        placeID: Int,
        submission: PlaceReviewSubmission,
        flowID: UUID,
        requestID: Int
    ) -> Effect<Action> {
        let service = service
        return .run { send in
            do {
                try await service.submitReview(placeID: placeID, submission: submission)
                await send(.submissionCompleted(.success(()), flowID: flowID, requestID: requestID))
            } catch is CancellationError {
                return
            } catch let error as NetworkError {
                await send(.submissionCompleted(.failure(error.localizedDescription), flowID: flowID, requestID: requestID))
            } catch {
                await send(.submissionCompleted(.failure("후기를 등록하지 못했어요. 다시 시도해주세요."), flowID: flowID, requestID: requestID))
            }
        }
        .cancelTask(id: EffectID.submission)
    }

    func completionDismissalEffect(flowID: UUID, requestID: Int) -> Effect<Action> {
        .run { send in
            do {
                try await Task.sleep(for: .milliseconds(200))
                await send(.completionDismissed(flowID: flowID, requestID: requestID))
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        .cancelTask(id: EffectID.completionDismissal)
    }
}
