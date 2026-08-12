import Foundation

struct ReviewPromptReducer: Reducer {
    struct State {
        enum Presentation: Equatable {
            case hidden
            case preparing
            case prompt
        }

        var presentation: Presentation = .hidden
        var target: ReviewTarget?
        var requestedPlaceName: String?
        var isSubmittingVisit = false
        var flowID = UUID()
        var requestID = 0
    }

    enum Action {
        case start(placeID: Int, placeName: String)
        case targetPrepared(ReviewRequestResult<ReviewTarget>, flowID: UUID, requestID: Int)
        case visitedTapped
        case visitCompleted(ReviewRequestResult<Void>, flowID: UUID, requestID: Int)
        case notVisitedTapped
        case closeTapped
        case reset
        case delegate(Delegate)
    }

    enum Delegate {
        case writingRequested(ReviewWriteRequest)
        case skipReasonRequested(ReviewTarget)
        case dismissed
        case preparationFailed(String)
        case showSnackbar(String)
    }

    private enum EffectID {
        case preparation
        case visit
    }

    private let service: any ReviewPromptServicing

    init(service: any ReviewPromptServicing) {
        self.service = service
    }
}

// MARK: - Reduce
extension ReviewPromptReducer {

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .start(let placeID, let placeName):
            state = .init(
                presentation: .preparing,
                requestedPlaceName: placeName,
                requestID: state.requestID + 1
            )
            return prepareTargetEffect(placeID: placeID, flowID: state.flowID, requestID: state.requestID)

        case .targetPrepared(let result, let flowID, let requestID):
            guard state.presentation == .preparing,
                  state.flowID == flowID,
                  state.requestID == requestID
            else {
                return .none
            }

            switch result {
            case .success(let preparedTarget):
                state.target = .init(
                    placeID: preparedTarget.placeID,
                    practiceID: preparedTarget.practiceID,
                    placeName: state.requestedPlaceName ?? preparedTarget.placeName
                )
                state.presentation = .prompt

            case .failure(let message):
                state = .init()
                return .send(.delegate(.preparationFailed(message)))
            }

        case .visitedTapped:
            guard state.presentation == .prompt,
                  let practiceID = state.target?.practiceID,
                  !state.isSubmittingVisit
            else {
                return .none
            }
            state.isSubmittingVisit = true
            state.requestID += 1
            return visitEffect(practiceID: practiceID, flowID: state.flowID, requestID: state.requestID)

        case .visitCompleted(let result, let flowID, let requestID):
            guard state.presentation == .prompt,
                  state.isSubmittingVisit,
                  state.flowID == flowID,
                  state.requestID == requestID
            else {
                return .none
            }
            state.isSubmittingVisit = false

            switch result {
            case .success:
                guard let target = state.target else { return .none }
                return .send(.delegate(.writingRequested(.init(
                    placeID: target.placeID,
                    placeName: target.placeName
                ))))

            case .failure(let message):
                return .send(.delegate(.showSnackbar(message)))
            }

        case .notVisitedTapped:
            guard state.presentation == .prompt,
                  !state.isSubmittingVisit,
                  let target = state.target
            else {
                return .none
            }
            return .send(.delegate(.skipReasonRequested(target)))

        case .closeTapped:
            guard state.presentation == .prompt else { return .none }
            return .send(.delegate(.dismissed))

        case .reset:
            state = .init()
            return .cancel(id: EffectID.preparation)

        case .delegate:
            return .none
        }

        return .none
    }
}

// MARK: - Effect
private extension ReviewPromptReducer {

    func prepareTargetEffect(placeID: Int, flowID: UUID, requestID: Int) -> Effect<Action> {
        let service = service
        return .run { send in
            do {
                let target = try await service.prepareTarget(placeID: placeID)
                await send(.targetPrepared(.success(target), flowID: flowID, requestID: requestID))
            } catch is CancellationError {
                return
            } catch let error as ReviewTargetPreparationError {
                RodiLogger.error(
                    "Review target preparation failed: endpoint=\(error.endpoint), error=\(error.underlyingError.localizedDescription)"
                )
                await send(.targetPrepared(.failure("후기 등록 대상을 준비하지 못했어요."), flowID: flowID, requestID: requestID))
            } catch {
                RodiLogger.error("Review target preparation failed: error=\(error.localizedDescription)")
                await send(.targetPrepared(.failure("후기 등록 대상을 준비하지 못했어요."), flowID: flowID, requestID: requestID))
            }
        }
        .cancelTask(id: EffectID.preparation)
    }

    func visitEffect(practiceID: Int, flowID: UUID, requestID: Int) -> Effect<Action> {
        let service = service
        return .run { send in
            do {
                try await service.recordVisit(practiceID: practiceID)
                await send(.visitCompleted(.success(()), flowID: flowID, requestID: requestID))
            } catch is CancellationError {
                return
            } catch let error as NetworkError {
                await send(.visitCompleted(.failure(error.localizedDescription), flowID: flowID, requestID: requestID))
            } catch {
                await send(.visitCompleted(.failure("방문 기록을 남기지 못했어요. 다시 시도해주세요."), flowID: flowID, requestID: requestID))
            }
        }
        .cancelTask(id: EffectID.visit)
    }
}
