//
//  KakaoLocalSearchTestReducer.swift
//  Rodi
//

import Foundation

@MainActor
struct KakaoLocalSearchTestReducer: Reducer {
    struct State {
        var query = "서울"
        var regions: [KakaoLocalRegionSuggestion] = []
        var places: [KakaoLocalSearchItem] = []
        var isPlaceLoading = false
        var hasSearchedPlaces = false
        var placeErrorMessage: String?
        var requestID = 0
    }

    enum Action {
        case appeared
        case queryChanged(String)
        case regionTapped(KakaoLocalRegionSuggestion)
        case sampleSearchTapped(String)
        case searchTapped
        case placeSearchCompleted(SearchResult, requestID: Int)
    }

    enum SearchResult {
        case success(KakaoLocalSearchPage)
        case failure(String)
    }

    private enum EffectID: Hashable {
        case placeSearch
    }

    private let regionService: KakaoAdministrativeRegionService
    private let searchService: KakaoLocalSearchService

    init(
        regionService: KakaoAdministrativeRegionService,
        searchService: KakaoLocalSearchService
    ) {
        self.regionService = regionService
        self.searchService = searchService
    }

    init() {
        regionService = KakaoAdministrativeRegionService()
        searchService = KakaoLocalSearchService()
    }
}

// MARK: - Reduce
extension KakaoLocalSearchTestReducer {
    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .appeared:
            guard !state.hasSearchedPlaces, !state.isPlaceLoading else { return .none }
            updateRegions(state: &state)
            return searchPlaces(state: &state, debounce: false)

        case .queryChanged(let query):
            state.query = query
            updateRegions(state: &state)
            return searchPlaces(state: &state, debounce: true)

        case .regionTapped(let region):
            state.query = region.searchQuery
            updateRegions(state: &state)
            return searchPlaces(state: &state, debounce: false)

        case .sampleSearchTapped(let query):
            state.query = query
            updateRegions(state: &state)
            return searchPlaces(state: &state, debounce: false)

        case .searchTapped:
            updateRegions(state: &state)
            return searchPlaces(state: &state, debounce: false)

        case let .placeSearchCompleted(result, requestID):
            guard requestID == state.requestID else { return .none }
            state.isPlaceLoading = false
            state.hasSearchedPlaces = true

            switch result {
            case .success(let page):
                state.places = page.items
                state.placeErrorMessage = nil
            case .failure(let message):
                state.places = []
                state.placeErrorMessage = message
            }
        }

        return .none
    }
}

// MARK: - State Mutation
private extension KakaoLocalSearchTestReducer {
    func updateRegions(state: inout State) {
        state.regions = regionService.suggestions(for: state.query, limit: 4)
    }
}

// MARK: - Effect
private extension KakaoLocalSearchTestReducer {
    func searchPlaces(
        state: inout State,
        debounce: Bool
    ) -> Effect<Action> {
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        state.requestID += 1

        guard query.count >= 2 else {
            state.places = []
            state.isPlaceLoading = false
            state.hasSearchedPlaces = false
            state.placeErrorMessage = nil
            return .cancel(id: EffectID.placeSearch)
        }

        state.places = []
        state.isPlaceLoading = true
        state.hasSearchedPlaces = false
        state.placeErrorMessage = nil

        let requestID = state.requestID
        let searchService = searchService

        return .run { send in
            if debounce {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    return
                }
            }

            do {
                let page = try await searchService.searchPlaces(query: query)
                await send(.placeSearchCompleted(.success(page), requestID: requestID))
            } catch is CancellationError {
                return
            } catch let error as KakaoLocalSearchError {
                await send(.placeSearchCompleted(.failure(error.userMessage), requestID: requestID))
            } catch {
                await send(
                    .placeSearchCompleted(
                        .failure("검색 중 알 수 없는 오류가 발생했어요."),
                        requestID: requestID
                    )
                )
            }
        }
        .cancelTask(id: EffectID.placeSearch)
    }
}
