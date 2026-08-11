import Foundation

struct ReviewReducer: Reducer {
    struct State {
        var presentation: ReviewPresentation = .hidden
        var flowGeneration = UUID()
        var target: ReviewTarget?
        var isSubmittingVisit = false
        var isSubmittingReview = false
        var isRecommended: Bool?
        var difficulty: ReviewDifficulty?
        var congestion: ReviewCongestion?
        var caution = ""
        var practiceMethod: ReviewPracticeMethod?
        var content = ""
        var skipReasonFormState: ReviewSkipReasonFormState = .idle
        var skipReasonFormRequestID = 0
        var selectedSkipReason: PracticeSkipReasonOption?
        var skipReasonDetail = ""
        var isSubmittingSkipReason = false
        var pageBeforeDiscard: ReviewPresentation?

        var canProceedToSecondPage: Bool {
            isRecommended != nil
                && difficulty != nil
                && congestion != nil
                && !caution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var canSubmit: Bool {
            practiceMethod != nil && !isSubmittingReview
        }

        var canSubmitSkipReason: Bool {
            guard let selectedSkipReason, !isSubmittingSkipReason else { return false }

            guard selectedSkipReason.requiresTextInput else { return true }
            return !skipReasonDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

    }

    enum Action {
        case debugPromptRequested
        case promptRequested(placeID: Int)
        case directWritingRequested(ReviewWriteRequest)
        case targetPrepared(ReviewTargetPreparationResult, generation: UUID)
        case visitedTapped
        case visitCompleted(ReviewVisitResult, generation: UUID)
        case notVisitedTapped
        case skipReasonFormLoaded(ReviewSkipReasonFormResult, generation: UUID, requestID: Int)
        case skipReasonFormRetryTapped
        case skipReasonSelected(PracticeSkipReasonOption)
        case skipReasonDetailChanged(String)
        case skipReasonSubmitTapped
        case skipReasonSubmissionCompleted(ReviewSkipReasonSubmissionResult, generation: UUID)
        case skipReasonCompletionConfirmed
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
        case reviewSubmissionCompleted(ReviewSubmissionResult, generation: UUID)
        case completionConfirmed
        case delegate(Delegate)
    }

    enum Delegate {
        case finished(returnToHome: Bool)
        case showSnackbar(String)
    }

    private enum EffectID {
        case preparation
        case visit
        case reviewSubmission
        case skipReasonFormLoading
        case skipReasonSubmission
    }

    private let reviewService: ReviewService

    init(
        reviewService: ReviewService
    ) {
        self.reviewService = reviewService
    }
}

// MARK: - Reduce
extension ReviewReducer {

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .debugPromptRequested:
            guard state.presentation == .hidden else { return .none }
            state.flowGeneration = UUID()
            state.presentation = .preparing
            return prepareTargetEffect(placeID: 120, generation: state.flowGeneration)

        case .promptRequested(let placeID):
            guard state.presentation == .hidden else { return .none }
            state.flowGeneration = UUID()
            state.presentation = .preparing
            return prepareTargetEffect(placeID: placeID, generation: state.flowGeneration)

        case .directWritingRequested(let request):
            guard state.presentation == .hidden else { return .none }
            state.flowGeneration = UUID()
            state.target = .init(
                placeID: request.placeID,
                practiceID: nil,
                placeName: request.placeName
            )
            state.presentation = .formPage1

        case .targetPrepared(let result, let generation):
            guard state.flowGeneration == generation,
                  state.presentation == .preparing
            else {
                return .none
            }
            switch result {
            case .success(let target):
                state.target = target
                state.presentation = .prompt
            case .failure(let message):
                clear(state: &state)
                return .send(.delegate(.showSnackbar(message)))
            }

        case .visitedTapped:
            guard let target = state.target,
                  let practiceID = target.practiceID,
                  !state.isSubmittingVisit
            else {
                return .none
            }
            state.isSubmittingVisit = true
            return visitEffect(practiceID: practiceID, generation: state.flowGeneration)

        case .visitCompleted(let result, let generation):
            guard state.flowGeneration == generation,
                  state.presentation == .prompt,
                  state.isSubmittingVisit
            else {
                return .none
            }
            state.isSubmittingVisit = false
            switch result {
            case .success:
                state.presentation = .formPage1
            case .failure(let message):
                return .send(.delegate(.showSnackbar(message)))
            }

        case .notVisitedTapped:
            guard state.target != nil, !state.isSubmittingVisit else { return .none }
            state.presentation = .skipReasonForm
            state.skipReasonFormState = .loading
            state.selectedSkipReason = nil
            state.skipReasonDetail = ""
            state.skipReasonFormRequestID += 1
            return fetchSkipReasonFormEffect(
                generation: state.flowGeneration,
                requestID: state.skipReasonFormRequestID
            )

        case .skipReasonFormLoaded(let result, let generation, let requestID):
            guard state.flowGeneration == generation,
                  state.presentation == .skipReasonForm,
                  state.skipReasonFormState == .loading,
                  state.skipReasonFormRequestID == requestID
            else {
                return .none
            }
            switch result {
            case .success(let form):
                state.skipReasonFormState = .loaded(form)
            case .failure(let message):
                state.skipReasonFormState = .failed
                return .send(.delegate(.showSnackbar(message)))
            }

        case .skipReasonFormRetryTapped:
            guard state.presentation == .skipReasonForm,
                  state.skipReasonFormState != .loading
            else {
                return .none
            }
            state.skipReasonFormState = .loading
            state.skipReasonFormRequestID += 1
            return fetchSkipReasonFormEffect(
                generation: state.flowGeneration,
                requestID: state.skipReasonFormRequestID
            )

        case .skipReasonSelected(let option):
            guard case let .loaded(form) = state.skipReasonFormState,
                  form.options.contains(where: { $0.code == option.code })
            else {
                return .none
            }
            state.selectedSkipReason = option
            if !option.requiresTextInput {
                state.skipReasonDetail = ""
            }

        case .skipReasonDetailChanged(let value):
            guard state.selectedSkipReason?.requiresTextInput == true,
                  state.selectedSkipReason?.textInputMaxLength.map({ value.count <= $0 }) ?? true
            else {
                return .none
            }
            state.skipReasonDetail = value

        case .skipReasonSubmitTapped:
            guard state.presentation == .skipReasonForm,
                  state.canSubmitSkipReason,
                  let target = state.target,
                  let practiceID = target.practiceID,
                  let selectedSkipReason = state.selectedSkipReason
            else {
                return .none
            }
            state.isSubmittingSkipReason = true
            return submitSkipReasonEffect(
                practiceID: practiceID,
                reasonCode: selectedSkipReason.code,
                detail: selectedSkipReason.requiresTextInput
                    ? normalizedOptionalText(state.skipReasonDetail)
                    : nil,
                generation: state.flowGeneration
            )

        case .skipReasonSubmissionCompleted(let result, let generation):
            guard state.flowGeneration == generation,
                  state.presentation == .skipReasonForm,
                  state.isSubmittingSkipReason
            else {
                return .none
            }
            state.isSubmittingSkipReason = false
            switch result {
            case .success:
                state.presentation = .skipReasonCompletion
            case .failure(let message):
                return .send(.delegate(.showSnackbar(message)))
            }

        case .skipReasonCompletionConfirmed:
            clear(state: &state)
            return .send(.delegate(.finished(returnToHome: true)))

        case .recommendationSelected(let value):
            state.isRecommended = value

        case .difficultySelected(let value):
            state.difficulty = value

        case .congestionSelected(let value):
            state.congestion = value

        case .cautionChanged(let value):
            state.caution = value

        case .nextTapped:
            guard state.presentation == .formPage1, state.canProceedToSecondPage else { return .none }
            state.presentation = .formPage2

        case .backTapped:
            guard state.presentation == .formPage2, !state.isSubmittingReview else { return .none }
            state.presentation = .formPage1

        case .practiceMethodSelected(let value):
            state.practiceMethod = value

        case .contentChanged(let value):
            guard value.count <= 150 else { return .none }
            state.content = value

        case .closeTapped:
            switch state.presentation {
            case .formPage1, .formPage2, .skipReasonForm:
                state.pageBeforeDiscard = state.presentation
                state.presentation = .discardConfirmation

            case .prompt:
                clear(state: &state)
                return .send(.delegate(.finished(returnToHome: true)))

            case .hidden, .preparing, .discardConfirmation, .completion, .skipReasonCompletion:
                break
            }

        case .discardConfirmed:
            clear(state: &state)
            return .send(.delegate(.finished(returnToHome: true)))

        case .discardCancelled:
            state.presentation = state.pageBeforeDiscard ?? .formPage1
            state.pageBeforeDiscard = nil

        case .submitTapped:
            guard state.presentation == .formPage2,
                  state.canSubmit,
                  let target = state.target,
                  let submission = submission(from: state)
            else {
                return .none
            }
            state.isSubmittingReview = true
            return createReviewEffect(
                placeID: target.placeID,
                submission: submission,
                generation: state.flowGeneration
            )

        case .reviewSubmissionCompleted(let result, let generation):
            guard state.flowGeneration == generation,
                  state.presentation == .formPage2,
                  state.isSubmittingReview
            else {
                return .none
            }
            state.isSubmittingReview = false
            switch result {
            case .success:
                state.presentation = .completion
            case .failure(let message):
                return .send(.delegate(.showSnackbar(message)))
            }

        case .completionConfirmed:
            clear(state: &state)
            return .send(.delegate(.finished(returnToHome: true)))

        case .delegate:
            return .none
        }

        return .none
    }
}

// MARK: - Effect
private extension ReviewReducer {

    func prepareTargetEffect(placeID: Int, generation: UUID) -> Effect<Action> {
        let reviewService = reviewService
        return .run { send in
            do {
                let target = try await reviewService.prepareTarget(placeID: placeID)
                await send(.targetPrepared(.success(target), generation: generation))
            } catch is CancellationError {
                return
            } catch let error as ReviewTargetPreparationError {
                logTargetPreparationFailure(
                    endpoint: error.endpoint,
                    error: error.underlyingError
                )
                await send(.targetPrepared(.failure("후기 등록 대상을 준비하지 못했어요."), generation: generation))
            } catch {
                logTargetPreparationFailure(
                    endpoint: "후기 등록 대상 준비",
                    error: error
                )
                await send(.targetPrepared(.failure("후기 등록 대상을 준비하지 못했어요."), generation: generation))
            }
        }
        .cancelTask(id: EffectID.preparation)
    }

    func visitEffect(practiceID: Int, generation: UUID) -> Effect<Action> {
        let reviewService = reviewService
        return .run { send in
            do {
                try await reviewService.recordVisit(practiceID: practiceID)
                await send(.visitCompleted(.success, generation: generation))
            } catch is CancellationError {
                return
            } catch let error as NetworkError {
                await send(.visitCompleted(.failure(error.localizedDescription), generation: generation))
            } catch {
                await send(.visitCompleted(.failure("방문 기록을 남기지 못했어요. 다시 시도해주세요."), generation: generation))
            }
        }
        .cancelTask(id: EffectID.visit)
    }

    func createReviewEffect(
        placeID: Int,
        submission: PlaceReviewSubmission,
        generation: UUID
    ) -> Effect<Action> {
        let reviewService = reviewService
        return .run { send in
            do {
                try await reviewService.submitReview(placeID: placeID, submission: submission)
                await send(.reviewSubmissionCompleted(.success, generation: generation))
            } catch is CancellationError {
                return
            } catch let error as NetworkError {
                await send(.reviewSubmissionCompleted(.failure(error.localizedDescription), generation: generation))
            } catch {
                await send(.reviewSubmissionCompleted(.failure("후기를 등록하지 못했어요. 다시 시도해주세요."), generation: generation))
            }
        }
        .cancelTask(id: EffectID.reviewSubmission)
    }

    func fetchSkipReasonFormEffect(
        generation: UUID,
        requestID: Int
    ) -> Effect<Action> {
        let reviewService = reviewService
        return .run { send in
            do {
                let form = try await reviewService.fetchSkipReasonForm()
                await send(.skipReasonFormLoaded(.success(form), generation: generation, requestID: requestID))
            } catch is CancellationError {
                return
            } catch let error as NetworkError {
                await send(.skipReasonFormLoaded(.failure(error.localizedDescription), generation: generation, requestID: requestID))
            } catch {
                await send(.skipReasonFormLoaded(.failure("미방문 사유를 불러오지 못했어요. 다시 시도해주세요."), generation: generation, requestID: requestID))
            }
        }
        .cancelTask(id: EffectID.skipReasonFormLoading)
    }

    func submitSkipReasonEffect(
        practiceID: Int,
        reasonCode: String,
        detail: String?,
        generation: UUID
    ) -> Effect<Action> {
        let reviewService = reviewService
        return .run { send in
            do {
                try await reviewService.submitSkipReason(
                    practiceID: practiceID,
                    reasonCode: reasonCode,
                    detail: detail
                )
                await send(.skipReasonSubmissionCompleted(.success, generation: generation))
            } catch is CancellationError {
                return
            } catch let error as NetworkError {
                await send(.skipReasonSubmissionCompleted(.failure(error.localizedDescription), generation: generation))
            } catch {
                await send(.skipReasonSubmissionCompleted(.failure("미방문 사유를 등록하지 못했어요. 다시 시도해주세요."), generation: generation))
            }
        }
        .cancelTask(id: EffectID.skipReasonSubmission)
    }
}

// MARK: - Logging
private extension ReviewReducer {

    func logTargetPreparationFailure(
        endpoint: String,
        error: Error
    ) {
        RodiLogger.error(
            "Review target preparation failed: endpoint=\(endpoint), error=\(error.localizedDescription)"
        )
    }
}

// MARK: - State
private extension ReviewReducer {

    func submission(from state: State) -> PlaceReviewSubmission? {
        guard let isRecommended = state.isRecommended,
              let difficulty = state.difficulty,
              let congestion = state.congestion,
              let practiceMethod = state.practiceMethod
        else {
            return nil
        }

        return .init(
            isRecommended: isRecommended,
            difficulty: difficulty,
            congestion: congestion,
            practiceMethod: practiceMethod,
            content: normalizedOptionalText(state.content),
            caution: normalizedOptionalText(state.caution)
        )
    }

    func clear(state: inout State) {
        state = .init()
    }

    func normalizedOptionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
