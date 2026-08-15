//
//  MyPostsReducer.swift
//  Rodi
//

import Foundation

@MainActor
struct MyPostsReducer: Reducer {
    struct State {
        var items: [MyReviewItem] = []
        var isInitialLoading = false
        var hasCompletedInitialLoad = false
        var isNextPageLoading = false
        var errorMessage: String?
        var nextCursor: String?
        var hasNextPage = false
        var requestID = 0
        var deleteTargetReviewID: Int?
        var isDeleting = false
        var deleteErrorMessage: String?
        var snackbarMessage: String?
        var practiceRecordsRefreshRequestID = 0
        var pendingEditReviewID: Int?
        var hasPracticeRecords = false
        var practiceAvailabilityRequestID = 0
    }

    enum Action {
        case appeared
        case retryTapped
        case reloadRequested
        case lastItemAppeared(MyReviewItem)
        case firstPageLoaded(PageLoadResult, requestID: Int)
        case nextPageLoaded(PageLoadResult, requestID: Int)
        case practiceAvailabilityLoaded(Bool, requestID: Int)
        case deleteRequested(reviewID: Int)
        case deleteCancelled
        case deleteConfirmed
        case deleteCompleted(DeleteResult, reviewID: Int)
        case editRequested(reviewID: Int)
        case editRequestHandled(reviewID: Int)
        case snackbarDismissed(String)
    }

    enum PageLoadResult {
        case success(MyReviewPage)
        case failure(String)
    }

    enum DeleteResult {
        case success
        case failure(String)
    }

    private enum EffectID {
        case firstPage
        case nextPage
        case delete
        case snackbar
    }

    private let reviewRepository: ReviewRepository
    private let practiceRepository: PracticeRepository

    init(
        reviewRepository: ReviewRepository,
        practiceRepository: PracticeRepository
    ) {
        self.reviewRepository = reviewRepository
        self.practiceRepository = practiceRepository
    }
}

// MARK: - Reduce
extension MyPostsReducer {

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .appeared:
            guard !state.isInitialLoading, !state.hasCompletedInitialLoad else { return .none }
            return loadInitialContent(state: &state)

        case .retryTapped:
            if state.items.isEmpty {
                guard !state.isInitialLoading else { return .none }
                return loadFirstPage(state: &state)
            }

            guard let lastItem = state.items.last else { return .none }
            return loadNextPage(after: lastItem, state: &state)

        case .reloadRequested:
            return loadFirstPage(state: &state)

        case .lastItemAppeared(let item):
            return loadNextPage(after: item, state: &state)

        case let .firstPageLoaded(result, requestID):
            guard requestID == state.requestID else { return .none }
            state.isInitialLoading = false
            state.hasCompletedInitialLoad = true

            switch result {
            case .success(let page):
                state.items = page.items
                state.hasNextPage = page.hasNext
                state.nextCursor = page.nextCursor
                state.errorMessage = nil
            case .failure(let message):
                state.errorMessage = message
            }

        case let .nextPageLoaded(result, requestID):
            guard requestID == state.requestID else { return .none }
            state.isNextPageLoading = false

            switch result {
            case .success(let page):
                var existingIDs = Set(state.items.map(\.id))
                state.items.append(contentsOf: page.items.filter { existingIDs.insert($0.id).inserted })
                state.hasNextPage = page.hasNext
                state.nextCursor = page.nextCursor
                state.errorMessage = nil
            case .failure(let message):
                state.errorMessage = message
            }

        case let .practiceAvailabilityLoaded(hasPracticeRecords, requestID):
            guard requestID == state.practiceAvailabilityRequestID else { return .none }
            state.hasPracticeRecords = hasPracticeRecords

        case .deleteRequested(let reviewID):
            guard !state.isDeleting, state.items.contains(where: { $0.id == reviewID }) else { return .none }
            state.deleteTargetReviewID = reviewID
            state.deleteErrorMessage = nil

        case .deleteCancelled:
            guard !state.isDeleting else { return .none }
            state.deleteTargetReviewID = nil
            state.deleteErrorMessage = nil

        case .deleteConfirmed:
            guard let reviewID = state.deleteTargetReviewID, !state.isDeleting else { return .none }
            state.isDeleting = true
            state.deleteErrorMessage = nil
            return deleteEffect(reviewID: reviewID)

        case let .deleteCompleted(result, reviewID):
            guard state.deleteTargetReviewID == reviewID, state.isDeleting else { return .none }
            state.isDeleting = false

            switch result {
            case .success:
                state.deleteTargetReviewID = nil
                state.deleteErrorMessage = nil
                state.practiceRecordsRefreshRequestID += 1
                return refreshAfterDelete(state: &state)
            case .failure(let message):
                state.deleteErrorMessage = message
            }

        case .editRequested(let reviewID):
            guard state.items.contains(where: { $0.id == reviewID }) else { return .none }
            state.pendingEditReviewID = reviewID

        case .editRequestHandled(let reviewID):
            guard state.pendingEditReviewID == reviewID else { return .none }
            state.pendingEditReviewID = nil

        case .snackbarDismissed(let message):
            guard state.snackbarMessage == message else { return .none }
            state.snackbarMessage = nil
        }

        return .none
    }
}

// MARK: - Effects
private extension MyPostsReducer {

    func loadInitialContent(state: inout State) -> Effect<Action> {
        state.items = []
        state.isInitialLoading = true
        state.isNextPageLoading = false
        state.errorMessage = nil
        state.nextCursor = nil
        state.hasNextPage = false
        state.requestID += 1
        state.practiceAvailabilityRequestID += 1
        let reviewRequestID = state.requestID
        let practiceAvailabilityRequestID = state.practiceAvailabilityRequestID
        let reviewRepository = reviewRepository
        let practiceRepository = practiceRepository

        return .run { send in
            do {
                let page = try await reviewRepository.fetchMyReviews(query: .init(size: 10))
                await send(.firstPageLoaded(.success(page), requestID: reviewRequestID))
            } catch {
                await send(.firstPageLoaded(.failure(Self.message(for: error)), requestID: reviewRequestID))
            }

            await send(.practiceAvailabilityLoaded(
                await Self.hasVisitedPractice(using: practiceRepository),
                requestID: practiceAvailabilityRequestID
            ))
        }
        .cancelTask(id: EffectID.firstPage)
    }

    func loadFirstPage(state: inout State) -> Effect<Action> {
        state.items = []
        state.isInitialLoading = true
        state.isNextPageLoading = false
        state.errorMessage = nil
        state.nextCursor = nil
        state.hasNextPage = false
        state.requestID += 1
        let requestID = state.requestID
        let reviewRepository = reviewRepository

        return .run { send in
            do {
                let page = try await reviewRepository.fetchMyReviews(query: .init(size: 10))
                await send(.firstPageLoaded(.success(page), requestID: requestID))
            } catch {
                await send(.firstPageLoaded(.failure(Self.message(for: error)), requestID: requestID))
            }
        }
        .cancelTask(id: EffectID.firstPage)
    }

    func loadNextPage(after item: MyReviewItem, state: inout State) -> Effect<Action> {
        guard item.id == state.items.last?.id,
              state.hasNextPage,
              let cursor = state.nextCursor,
              !state.isInitialLoading,
              !state.isNextPageLoading
        else {
            return .none
        }

        state.isNextPageLoading = true
        state.errorMessage = nil
        let requestID = state.requestID
        let reviewRepository = reviewRepository

        return .run { send in
            do {
                let page = try await reviewRepository.fetchMyReviews(query: .init(size: 10, cursor: cursor))
                await send(.nextPageLoaded(.success(page), requestID: requestID))
            } catch {
                await send(.nextPageLoaded(.failure(Self.message(for: error)), requestID: requestID))
            }
        }
        .cancelTask(id: EffectID.nextPage)
    }

    func deleteEffect(reviewID: Int) -> Effect<Action> {
        let reviewRepository = reviewRepository
        return .run { send in
            do {
                try await reviewRepository.delete(reviewID: reviewID)
                await send(.deleteCompleted(.success, reviewID: reviewID))
            } catch {
                await send(.deleteCompleted(.failure(Self.deleteMessage(for: error)), reviewID: reviewID))
            }
        }
        .cancelTask(id: EffectID.delete)
    }

    func refreshAfterDelete(state: inout State) -> Effect<Action> {
        let message = "후기를 삭제했습니다."
        state.snackbarMessage = message

        return .run { send in
            await send(.reloadRequested)
            try? await Task.sleep(for: .seconds(3))
            await send(.snackbarDismissed(message))
        }
        .cancelTask(id: EffectID.snackbar)
    }

    static func message(for error: Error) -> String {
        if case NetworkError.networkUnavailable = error {
            return "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
        }
        return "내 후기를 불러오지 못했어요."
    }

    static func deleteMessage(for error: Error) -> String {
        if case NetworkError.networkUnavailable = error {
            return "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
        }
        return "후기를 삭제하지 못했어요. 다시 시도해주세요."
    }

    static func hasVisitedPractice(using repository: PracticeRepository) async -> Bool {
        var cursor: String?

        while true {
            guard let page = try? await repository.fetchMyPractices(query: .init(size: 20, cursor: cursor))
            else {
                return false
            }
            if page.items.contains(where: { $0.status == .visited }) {
                return true
            }
            guard page.hasNext, let nextCursor = page.nextCursor, !nextCursor.isEmpty else {
                return false
            }
            cursor = nextCursor
        }
    }
}
