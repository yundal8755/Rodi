//
//  RootReducer.swift
//  Rodi
//
//  Created by mac on 7/28/26.
//

import Foundation

@MainActor
struct RootReducer: Reducer {

    struct State {
        var pendingUpdate: AppVersionUpdate?
        var hasCheckedAppVersion = false
        var isRestoringSession = false
        var review = ReviewReducer.State()
        var reviewSnackbarMessage: String?
        var reviewReturnToHomeRequestID = 0
        var pendingPracticeReturnPrompt: PracticeReturnPrompt?
    }

    enum Action {
        case launched
        case sceneBecameActive
        case appVersionCheckCompleted(AppVersionUpdate?)
        case appVersionUpdateDismissed
        case sessionRestoreCompleted(SessionRestoreResult)
        case debugReviewTestRequested
        case reviewRequested(ReviewWriteRequest)
        case review(ReviewReducer.Action)
        case reviewSnackbarDismissed(String)
    }

    enum SessionRestoreResult {
        case refreshed
        case invalidated
        case deferred(String)
    }

    private enum EffectID {
        case appVersionCheck
        case sessionRestore
        case reviewSnackbar
    }

    private let tokenStore: TokenStoring
    private let authRepository: AuthRepository
    private let reviewReducer: ReviewReducer
    private let practiceReturnPromptStore: PracticeReturnPromptStoring

    init(
        tokenStore: TokenStoring,
        authRepository: AuthRepository,
        placeRepository: PlaceRepository,
        practiceRepository: PracticeRepository,
        reviewRepository: ReviewRepository,
        practiceReturnPromptStore: PracticeReturnPromptStoring
    ) {
        self.tokenStore = tokenStore
        self.authRepository = authRepository
        self.practiceReturnPromptStore = practiceReturnPromptStore
        reviewReducer = ReviewReducer(
            reviewService: ReviewService(
                placeRepository: placeRepository,
                practiceRepository: practiceRepository,
                reviewRepository: reviewRepository
            )
        )
    }
}

// MARK: Core Logic
extension RootReducer {

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .launched:
            return checkAppVersionIfNeeded(state: &state)

        case .sceneBecameActive:
            let promptAction = preparePracticeReturnPromptIfNeeded(state: &state)
            return restoreSessionIfNeeded(state: &state, after: promptAction)

        case .appVersionCheckCompleted(let update):
            state.pendingUpdate = update

        case .appVersionUpdateDismissed:
            state.pendingUpdate = nil

        case .sessionRestoreCompleted(let result):
            state.isRestoringSession = false

            switch result {
            case .refreshed:
                RodiLogger.info("Auth session restored")
            case .invalidated:
                authRepository.clearSession()
                RodiLogger.info("Auth session cleared after refresh rejection")
            case .deferred(let message):
                RodiLogger.warning("Auth session restore deferred: \(message)")
            }

        case .debugReviewTestRequested:
            #if DEBUG
            return .send(.review(.debugPromptRequested))
            #else
            return .none
            #endif

        case .reviewRequested(let request):
            return .send(.review(.directWritingRequested(request)))

        case .review(let action):
            removePracticeReturnPromptIfNeeded(for: action, state: &state)
            if case .delegate(let delegate) = action {
                return reduceReviewDelegate(delegate, state: &state)
            }
            return reviewReducer.reduce(&state.review, with: action).map(Action.review)

        case .reviewSnackbarDismissed(let message):
            guard state.reviewSnackbarMessage == message else { return .none }
            state.reviewSnackbarMessage = nil
        }

        return .none
    }

    private func checkAppVersionIfNeeded(state: inout State) -> Effect<Action> {
        guard AppEnvironment.current.isProduction else { return .none }
        guard !state.hasCheckedAppVersion else { return .none }

        state.hasCheckedAppVersion = true

        return .run { send in
            let update = await AppVersionUpdateChecker.checkForOptionalUpdate()
            await send(.appVersionCheckCompleted(update))
        }
        .cancelTask(id: EffectID.appVersionCheck)
    }

    private func restoreSessionIfNeeded(
        state: inout State,
        after action: Action?
    ) -> Effect<Action> {
        guard !state.isRestoringSession,
              let refreshToken = tokenStore.refreshToken,
              !refreshToken.isEmpty
        else {
            return action.map(Effect.send) ?? .none
        }

        let needsRefresh = tokenStore.accessToken.map { AccessTokenExpiry.needsRefresh($0) } ?? true
        guard needsRefresh else { return action.map(Effect.send) ?? .none }

        state.isRestoringSession = true
        return .run { send in

            do {
                _ = try await authRepository.refreshToken()
                await send(.sessionRestoreCompleted(.refreshed))
            } catch let error as NetworkError {
                if error.invalidatesAuthSession {
                    await send(.sessionRestoreCompleted(.invalidated))
                } else {
                    await send(.sessionRestoreCompleted(.deferred(error.localizedDescription)))
                }
            } catch {
                await send(.sessionRestoreCompleted(.deferred(error.localizedDescription)))
            }
            if let action {
                await send(action)
            }
        }
        .cancelTask(id: EffectID.sessionRestore)
    }

    private var hasActiveSession: Bool {
        [tokenStore.accessToken, tokenStore.refreshToken].contains { $0?.isEmpty == false }
    }

    private func preparePracticeReturnPromptIfNeeded(state: inout State) -> Action? {
        guard state.review.presentation == .hidden,
              state.pendingPracticeReturnPrompt == nil,
              let prompt = practiceReturnPromptStore.load()
        else {
            return nil
        }

        state.pendingPracticeReturnPrompt = prompt
        return .review(.promptRequested(placeID: prompt.placeID, placeName: prompt.placeName))
    }

    private func removePracticeReturnPromptIfNeeded(
        for action: ReviewReducer.Action,
        state: inout State
    ) {
        guard state.review.presentation == .prompt,
              let prompt = state.pendingPracticeReturnPrompt
        else {
            return
        }

        switch action {
        case .closeTapped, .notVisitedTapped, .visitedTapped:
            practiceReturnPromptStore.remove(prompt)
            state.pendingPracticeReturnPrompt = nil
        default:
            break
        }
    }

    private func reduceReviewDelegate(
        _ delegate: ReviewReducer.Delegate,
        state: inout State
    ) -> Effect<Action> {
        switch delegate {
        case .finished(let returnToHome):
            state.review = .init()
            if returnToHome {
                state.reviewReturnToHomeRequestID += 1
            }
            return .none

        case .showSnackbar(let message):
            state.reviewSnackbarMessage = message
            return .run { send in
                try? await Task.sleep(for: .seconds(3))
                await send(.reviewSnackbarDismissed(message))
            }
            .cancelTask(id: EffectID.reviewSnackbar)
        }
    }
}
