//
//  HomeReducer.swift
//  Rodi
//

import Foundation

@MainActor
struct HomeReducer: Reducer {
    typealias State = HomeState
    typealias MapState = HomeMapState
    typealias PresentationState = HomePresentationState

    struct Dependencies {
        let tokenStore: TokenStoring
        let placeRepository: PlaceRepository
        let practiceRepository: PracticeRepository
        let recentSearchRepository: RecentSearchRepository
        let reviewRepository: ReviewRepository
        let memberRepository: MemberRepository
        let practiceMeasurementStore: PracticeMeasurementStoring
        let practiceTrackingService: PracticeTrackingService
    }

    // MARK: Action
    enum Action {
        case map(MapAction)
        case bottomSheet(HomeBottomSheetReducer.Action)
        case search(HomeSearchReducer.Action)
        case presentation(PresentationAction)
        case delegate(Delegate)
        #if DEBUG
        case debugReviewTestRequested
        #endif
    }

    enum Delegate {
        case requestAuthentication
        case reviewWritingRequested(ReviewWriteRequest)
        case reviewEditingRequested(Int)
        #if DEBUG
        case reviewTestRequested
        #endif
    }

    enum MapAction {
        case tabSelectionChanged(Bool)
        case activityChanged(Bool)
        case locationAuthorizationRefreshRequested
        case becameReady
        case viewportChanged(
            center: RodiCoordinate,
            zoomLevel: Int,
            viewport: PlaceViewport,
            isUserInitiated: Bool
        )
        case markerTapped(String)
        case savedPlaceSelected(PlaceListItem)
        case cameraMoveFinished(Int)
        case currentLocationRequested
        case markerRetryRequested
        case recommendationResearchButtonTapped
        case searchEntryTapped
        case searchSelectionClearTapped
        case initialLocationRequested
        case initialMarkersLoadRequested
        case periodicLocationRefreshSchedulingRequested
        case periodicLocationRefreshTimerFired
        case serviceOutput(MapServiceOutAction)
        case markerRenderBatchUpdated([RodiMapMarker], generation: Int)
        case initialMarkerRenderingFinished(generation: Int)
    }

    enum PresentationAction {
        case setLocationSettingsAlertPresented(Bool)
        case snackbarRequestHandled
    }

    private let mapService: MapService
    private let markerRenderingService: MapMarkerRenderingService
    private let bottomSheetReducer: HomeBottomSheetReducer
    private let searchReducer: HomeSearchReducer
    private let hasActiveSession: () -> Bool
    private let delegateHandler: (Delegate) -> Void
    private let markerTierResolver = MapMarkerTierResolver()
    private let markerInteractionResolver = MapMarkerInteractionResolver()

    private enum CancellationID: Hashable {
        case progressiveMarkerRendering
        case userHeadingUpdates
        case periodicLocationRefresh
    }

    private static let periodicLocationRefreshNanoseconds: UInt64 = 60_000_000_000
    private static let prolongedLocationUnavailableInterval: TimeInterval = 60

    init(
        dependencies: Dependencies,
        delegateHandler: @escaping (Delegate) -> Void = { _ in }
    ) {
        mapService = MapService(
            placeRepository: dependencies.placeRepository,
            locationService: MapLocationService()
        )
        markerRenderingService = MapMarkerRenderingService()
        bottomSheetReducer = HomeBottomSheetReducer(
            dependencies: .init(
                tokenStore: dependencies.tokenStore,
                placeRepository: dependencies.placeRepository,
                practiceRepository: dependencies.practiceRepository,
                reviewRepository: dependencies.reviewRepository,
                memberRepository: dependencies.memberRepository,
                practiceMeasurementStore: dependencies.practiceMeasurementStore,
                practiceTrackingService: dependencies.practiceTrackingService,
                routeGuidanceService: .init()
            )
        )
        searchReducer = HomeSearchReducer(
            placeRepository: dependencies.placeRepository,
            recentSearchRepository: dependencies.recentSearchRepository
        )
        hasActiveSession = {
            [dependencies.tokenStore.accessToken, dependencies.tokenStore.refreshToken]
                .contains { $0?.isEmpty == false }
        }
        self.delegateHandler = delegateHandler
    }
}


// MARK: - Reduce

extension HomeReducer {

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .map(let action):
            return reduceMap(&state, action: action)

        case .bottomSheet(let action):
            return reduceBottomSheet(&state, action: action)

        case .search(let action):
            return reduceSearch(&state, action: action)

        case .presentation(let action):
            return reducePresentation(&state, action: action)

        case .delegate(let delegate):
            delegateHandler(delegate)
            return .none

        #if DEBUG
        case .debugReviewTestRequested:
            return .send(.delegate(.reviewTestRequested))
        #endif
        }
    }

    private func reduceMap(_ state: inout State, action: MapAction) -> Effect<Action> {
        var map = state.map
        defer { state.map = map }

        switch action {
        case .tabSelectionChanged(let isSelected):
            let wasMapInteractive = map.isMapInteractive
            map.isHomeTabSelected = isSelected
            if !isSelected {
                map.isCurrentLocationButtonActive = false
            }
            return updateMapVisibility(wasMapInteractive: wasMapInteractive, state: &map)

        case .activityChanged(let isActive):
            let wasMapInteractive = map.isMapInteractive
            map.isAppActive = isActive
            if !isActive {
                map.isCurrentLocationButtonActive = false
            }
            return updateMapVisibility(wasMapInteractive: wasMapInteractive, state: &map)

        case .locationAuthorizationRefreshRequested:
            let authorizationState = mapService.locationAuthorizationState
            map.locationAuthorizationState = authorizationState

            switch authorizationState {
            case .authorized:
                state.presentation.isLocationSettingsAlertPresented = false
                guard map.mapLifecycle == .ready,
                      map.locationState != .requesting
                else {
                    return map.isMapInteractive
                        ? .send(.map(.periodicLocationRefreshSchedulingRequested))
                        : .none
                }
                guard map.userLocation == nil else {
                    return map.isMapInteractive
                        ? .send(.map(.periodicLocationRefreshSchedulingRequested))
                        : .none
                }
                map.locationState = .requesting
                let source: LocationRequestSource = map.hasCompletedInitialLocationResolution
                    ? .foregroundRefresh
                    : .initial
                return mapServiceEffect(.requestCurrentLocation(source: source))

            case .denied, .restricted:
                map.locationState = .unavailable
                map.hasCompletedInitialLocationResolution = true
                map.userLocation = nil
                map.userHeadingDegrees = nil
                return .cancel(id: CancellationID.userHeadingUpdates)

            case .notDetermined:
                if map.userLocation == nil, map.locationState == .unavailable {
                    map.locationState = .idle
                }
                return .none
            }

        case .becameReady:
            guard map.mapLifecycle == .activating else { return .none }
            map.mapLifecycle = .ready
            return map.isMapInteractive ? initialMapDataLoadEffect() : .none

        case let .viewportChanged(center, zoomLevel, viewport, isUserInitiated):
            map.mapZoomLevel = zoomLevel
            if isUserInitiated {
                map.isCurrentLocationButtonActive = false
            }
            let tierResolution = markerTierResolver.resolve(
                zoomLevel: zoomLevel,
                forcedTier: map.forcedMarkerTier,
                forcedTierZoomLevel: map.forcedMarkerTierZoomLevel
            )
            map.forcedMarkerTier = tierResolution.forcedTier
            map.forcedMarkerTierZoomLevel = tierResolution.forcedTierZoomLevel
            let tier = tierResolution.tier

            if map.markerState == .loaded,
               map.displayedMarkerTier != tier {
                map.displayedMarkerTier = tier
                if tier != .individual, isUserInitiated {
                    map.selectedMarkerID = nil
                }
                map.markers = RodiHomeMarkerClusterIndex.markers(
                    for: map.mapItems,
                    tier: tier,
                    selectedMarkerID: map.selectedMarkerID
                )
            }

            var followUpActions: [Action] = [
                .bottomSheet(.recommendList(.viewportChanged(
                    viewport: viewport,
                    center: center,
                    isUserInitiated: isUserInitiated
                )))
            ]

            if !isUserInitiated,
               map.pendingRegionCameraRequestID != nil,
               let origin = map.pendingRegionViewportReloadOrigin {
                map.pendingRegionCameraRequestID = nil
                map.pendingRegionViewportReloadOrigin = nil
                followUpActions.append(.bottomSheet(.recommendList(.reloadAfterRegionViewport(origin: origin))))
            }

            return actions(followUpActions)

        case .markerTapped(let markerID):
            guard let interaction = markerInteractionResolver.resolve(
                markerID: markerID,
                markers: map.markers,
                items: map.mapItems
            ) else {
                return .none
            }
            map.isCurrentLocationButtonActive = false

            switch interaction {
            case .cluster(let marker, let target):
                map.selectedMarkerID = nil
                map.routeOverlay = nil
                map.markerRenderingGeneration += 1
                map.forcedMarkerTier = target.nextTier
                map.forcedMarkerTierZoomLevel = nil
                map.cameraTarget = marker.coordinate
                map.cameraFocus = .cluster(coordinates: target.coordinates)
                map.cameraRequestID += 1
                map.animatedCameraRequestID = map.cameraRequestID
                return .cancel(id: CancellationID.progressiveMarkerRendering)

            case .course(let marker, let placeID):
                state.presentation.isBottomTabBarVisible = false
                map.routeOverlay = nil
                map.selectedSearchResultName = marker.title
                map.selectedMarkerID = markerID
                map.markerRenderingGeneration += 1
                map.cameraTarget = marker.coordinate
                map.cameraFocus = .courseMarker
                map.cameraRequestID += 1
                map.animatedCameraRequestID = map.cameraRequestID
                map.markers = RodiHomeMarkerClusterIndex.markers(
                    for: map.mapItems,
                    tier: map.displayedMarkerTier
                        ?? RodiHomeMarkerClusterIndex.Tier(zoomLevel: map.mapZoomLevel),
                    selectedMarkerID: markerID
                )
                return .send(.bottomSheet(.resolvePlace(id: placeID)))

            case .parking(let marker, let placeID):
                state.presentation.isBottomTabBarVisible = false
                map.routeOverlay = nil
                map.selectedSearchResultName = marker.title
                map.selectedMarkerID = markerID
                map.markerRenderingGeneration += 1
                map.cameraTarget = marker.coordinate
                map.cameraFocus = .closeSingleLocation
                map.cameraRequestID += 1
                map.animatedCameraRequestID = map.cameraRequestID
                map.markers = RodiHomeMarkerClusterIndex.markers(
                    for: map.mapItems,
                    tier: map.displayedMarkerTier
                        ?? RodiHomeMarkerClusterIndex.Tier(zoomLevel: map.mapZoomLevel),
                    selectedMarkerID: markerID
                )
                return .send(.bottomSheet(.resolvePlace(id: placeID)))
            }

        case .savedPlaceSelected(let place):
            let markerID = place.type == .course
                ? "course-\(place.id)"
                : "parking-\(place.id)"

            state.presentation.isBottomTabBarVisible = false
            map.isCurrentLocationButtonActive = false
            map.routeOverlay = nil
            map.selectedSearchResultName = nil
            map.selectedMarkerID = markerID
            map.markerRenderingGeneration += 1
            map.forcedMarkerTier = .individual
            map.forcedMarkerTierZoomLevel = nil
            map.displayedMarkerTier = .individual
            map.cameraTarget = RodiCoordinate(latitude: place.latitude, longitude: place.longitude)
            map.cameraFocus = .closeSingleLocation
            map.cameraRequestID += 1
            map.animatedCameraRequestID = map.cameraRequestID
            map.markers = RodiHomeMarkerClusterIndex.markers(
                for: map.mapItems,
                tier: .individual,
                selectedMarkerID: map.selectedMarkerID
            )
            if map.markerState == .loaded {
                map.hasCompletedInitialMarkerRendering = true
            }
            return .run { send in
                await send(.bottomSheet(.resolveSavedPlace(place)))
            }
            .cancelTask(id: CancellationID.progressiveMarkerRendering)

        case .cameraMoveFinished(let requestID):
            guard map.animatedCameraRequestID == requestID else { return .none }
            map.animatedCameraRequestID = nil
            // Kakao의 camera completion은 viewport 갱신보다 먼저 올 수 있습니다.
            // 지역 검색 목록은 새 viewport 이벤트에서만 다시 조회합니다.
            return .none

        case .currentLocationRequested:
            guard map.mapLifecycle == .ready,
                  map.locationState != .requesting
            else {
                return .none
            }
            map.isCurrentLocationButtonActive = true
            return .send(.bottomSheet(.prepareForCurrentLocation))

        case .recommendationResearchButtonTapped:
            map.routeOverlay = nil
            map.selectedMarkerID = nil
            map.selectedSearchResultName = nil
            map.markers = RodiHomeMarkerClusterIndex.markers(
                for: map.mapItems,
                tier: map.displayedMarkerTier
                    ?? RodiHomeMarkerClusterIndex.Tier(zoomLevel: map.mapZoomLevel)
            )

            let origin = map.userLocation
            return .send(.bottomSheet(.recommendList(.reloadCurrentViewport(origin: origin))))

        case .searchEntryTapped:
            guard hasActiveSession() else {
                return .send(.delegate(.requestAuthentication))
            }
            map.isCurrentLocationButtonActive = false
            state.search = .init()
            state.presentation.searchOrigin = map.cameraTarget
            state.presentation.isSearchPresented = true
            return .none

        case .searchSelectionClearTapped:
            state.search = .init()
            map.selectedSearchResultName = nil
            map.routeOverlay = nil
            map.selectedMarkerID = nil
            map.isResearchButtonVisible = false
            map.markers = RodiHomeMarkerClusterIndex.markers(
                for: map.mapItems,
                tier: map.displayedMarkerTier
                    ?? RodiHomeMarkerClusterIndex.Tier(zoomLevel: map.mapZoomLevel)
            )
            state.presentation.isBottomTabBarVisible = true
            return .send(.bottomSheet(.clearSearchSelection))

        case .markerRetryRequested:
            guard map.markerState == .failed else { return .none }
            map.hasCompletedInitialMarkerRendering = false
            map.markerState = .loading
            return mapServiceEffect(.loadPlaceCoordinates)

        case .initialLocationRequested:
            guard map.mapLifecycle == .ready,
                  map.locationState == .idle
            else {
                return .none
            }
            map.locationAuthorizationState = mapService.locationAuthorizationState
            map.locationState = .requesting
            return mapServiceEffect(.requestCurrentLocation(source: .initial))

        case .initialMarkersLoadRequested:
            guard map.mapLifecycle == .ready,
                  map.markerState == .idle
            else {
                return .none
            }
            map.hasCompletedInitialMarkerRendering = false
            map.markerState = .loading
            return mapServiceEffect(.loadPlaceCoordinates)

        case .periodicLocationRefreshSchedulingRequested:
            guard map.isMapInteractive,
                  map.mapLifecycle == .ready,
                  map.locationAuthorizationState == .authorized,
                  map.locationState != .requesting
            else {
                return .cancel(id: CancellationID.periodicLocationRefresh)
            }
            return periodicLocationRefreshEffect()

        case .periodicLocationRefreshTimerFired:
            guard map.isMapInteractive,
                  map.mapLifecycle == .ready,
                  mapService.locationAuthorizationState == .authorized,
                  map.locationState != .requesting
            else {
                return .none
            }
            map.locationAuthorizationState = .authorized
            map.locationState = .requesting
            return mapServiceEffect(.requestCurrentLocation(source: .periodicRefresh))

        case .serviceOutput(let output):
            return reduceMapServiceOutput(
                output,
                map: &map,
                presentation: &state.presentation
            )

        case .markerRenderBatchUpdated(let markers, let generation):
            guard map.markerState == .loaded,
                  map.markerRenderingGeneration == generation
            else {
                return .none
            }
            map.markers = markers.map { marker in
                RodiMapMarker(
                    id: marker.id,
                    kind: marker.kind,
                    title: marker.title,
                    coordinate: marker.coordinate,
                    isSelected: marker.id == map.selectedMarkerID
                )
            }
            return .none

        case .initialMarkerRenderingFinished(let generation):
            guard map.markerState == .loaded,
                  map.markerRenderingGeneration == generation
            else {
                return .none
            }
            map.hasCompletedInitialMarkerRendering = true
            return .none
        }
    }

    private func reduceBottomSheet(
        _ state: inout State, action: HomeBottomSheetReducer.Action) -> Effect<Action> {
    guard case .delegate(let delegate) = action else {
        return bottomSheetReducer
            .reduce(&state.bottomSheet, with: action)
            .map(Action.bottomSheet)
    }

    switch delegate {
    case .mapPlaceResolved(let detail):
        state.presentation.isBottomTabBarVisible = false
        selectResolvedPlaceMarker(detail, state: &state.map)

    case .mapSearchSelectionRequested(let name):
        // 추천 목록의 행을 탭한 즉시 검색창을 선택 상태로 바꿉니다.
        // 상세 조회 성공 시에는 `mapPlaceResolved`가 active marker를 확정합니다.
        state.presentation.isBottomTabBarVisible = false
        state.map.selectedSearchResultName = name
        state.map.routeOverlay = nil
        state.map.isResearchButtonVisible = false

    case .mapRouteOverlayChanged(let overlay):
        state.map.routeOverlay = overlay

    case .mapFocusRequested(let coordinate):
        state.map.cameraTarget = coordinate
        state.map.cameraFocus = .closeSingleLocation
        state.map.cameraRequestID += 1
        state.map.animatedCameraRequestID = state.map.cameraRequestID

    case .mapDetailDismissed:
        state.map.routeOverlay = nil
        state.map.selectedMarkerID = nil
        state.map.selectedSearchResultName = nil
        state.map.isResearchButtonVisible = false
        state.map.markers = RodiHomeMarkerClusterIndex.markers(
            for: state.map.mapItems,
            tier: state.map.displayedMarkerTier
                ?? RodiHomeMarkerClusterIndex.Tier(zoomLevel: state.map.mapZoomLevel)
        )
        state.presentation.isBottomTabBarVisible = true

    case .currentLocationReady:
        guard state.map.mapLifecycle == .ready,
              state.map.locationState != .requesting
        else {
            return .none
        }
        state.map.locationState = .requesting
        return mapServiceEffect(.requestCurrentLocation(source: .userInitiated))

    case let .recommendationPresentationChanged(isBottomTabBarVisible, isResearchButtonVisible):
        state.presentation.isBottomTabBarVisible = isBottomTabBarVisible
        state.map.isResearchButtonVisible = isResearchButtonVisible

    case .recommendationCollapsed:
        state.map.selectedSearchResultName = nil

    case .requestAuthentication:
        return .send(.delegate(.requestAuthentication))

    case .showSnackbar(let message):
        state.presentation.pendingSnackbar = ToastStruct(message: message, state: .error)

    case .reviewWritingRequested(let request):
        return .send(.delegate(.reviewWritingRequested(request)))

    case .reviewEditingRequested(let reviewID):
        return .send(.delegate(.reviewEditingRequested(reviewID)))
    }

    return .none
}

    private func reduceSearch(
        _ state: inout State, action: HomeSearchReducer.Action) -> Effect<Action> {
        guard case .delegate(let delegate) = action else {
            return searchReducer
                .reduce(&state.search, with: action)
                .map(Action.search)
        }

        switch delegate {
        case let .placeSelected(id, name):
            state.presentation.isSearchPresented = false
            state.presentation.searchOrigin = nil
            state.search = .init()
            state.map.selectedSearchResultName = name
            state.map.routeOverlay = nil
            state.map.selectedMarkerID = nil
            state.map.isResearchButtonVisible = false
            state.map.markers = RodiHomeMarkerClusterIndex.markers(
                for: state.map.mapItems,
                tier: state.map.displayedMarkerTier
                    ?? RodiHomeMarkerClusterIndex.Tier(zoomLevel: state.map.mapZoomLevel)
            )
            return .send(.bottomSheet(.resolvePlace(id: id)))

        case let .regionSelected(name, center):
            state.presentation.isSearchPresented = false
            state.presentation.searchOrigin = nil
            state.presentation.isBottomTabBarVisible = true
            state.search = .init()
            state.map.selectedSearchResultName = name
            state.map.routeOverlay = nil
            state.map.selectedMarkerID = nil
            state.map.isResearchButtonVisible = false
            state.map.markers = RodiHomeMarkerClusterIndex.markers(
                for: state.map.mapItems,
                tier: state.map.displayedMarkerTier
                    ?? RodiHomeMarkerClusterIndex.Tier(zoomLevel: state.map.mapZoomLevel)
            )
            state.map.cameraTarget = center
            state.map.cameraFocus = .region
            state.map.cameraRequestID += 1
            state.map.animatedCameraRequestID = state.map.cameraRequestID
            state.map.pendingRegionViewportReloadOrigin = center
            state.map.pendingRegionCameraRequestID = state.map.cameraRequestID
            return .send(.bottomSheet(.presentRecommendListForRegion(origin: center)))

        case .dismissed:
            state.presentation.isSearchPresented = false
            state.presentation.searchOrigin = nil

        case .showSnackbar(let message):
            state.presentation.pendingSnackbar = ToastStruct(message: message, state: .error)
        }

        return .none
    }

    private func reducePresentation(
        _ state: inout State, action: PresentationAction) -> Effect<Action> {
        switch action {
        case .setLocationSettingsAlertPresented(let isPresented):
            state.presentation.isLocationSettingsAlertPresented = isPresented

        case .snackbarRequestHandled:
            state.presentation.pendingSnackbar = nil
        }
        return .none
    }

    private func reduceMapServiceOutput(
        _ output: MapServiceOutAction, map: inout MapState, presentation: inout PresentationState
    ) -> Effect<Action> {
        switch output {
        case let .currentLocationResolved(coordinate, source):
            guard map.locationState == .requesting else { return .none }
            map.locationAuthorizationState = .authorized
            map.locationState = .resolved
            map.hasCompletedInitialLocationResolution = true
            map.userLocation = coordinate
            map.lastLocationResolvedAt = Date()
            map.hasShownProlongedLocationUnavailableNotice = false

            if source != .foregroundRefresh, source != .periodicRefresh {
                map.cameraTarget = coordinate
                map.cameraFocus = .currentLocation
                map.cameraRequestID += 1
                map.animatedCameraRequestID = nil
            }
            if source == .periodicRefresh {
                return .send(.map(.periodicLocationRefreshSchedulingRequested))
            }
            return userHeadingUpdatesEffect(origin: coordinate)

        case .currentLocationUnavailable(let source):
            guard map.locationState == .requesting else { return .none }
            map.locationAuthorizationState = mapService.locationAuthorizationState
            map.locationState = .unavailable
            map.hasCompletedInitialLocationResolution = true
            if source == .userInitiated {
                presentation.pendingSnackbar = ToastStruct(
                    message: "현재 위치를 확인할 수 없어요. 다시 시도해주세요.",
                    state: .error
                )
            } else if source == .periodicRefresh,
                      shouldShowProlongedLocationUnavailableNotice(for: map) {
                map.hasShownProlongedLocationUnavailableNotice = true
                presentation.pendingSnackbar = ToastStruct(
                    message: "현재 위치를 확인할 수 없어요. 위치 신호가 안정되면 다시 갱신할게요.",
                    state: .error
                )
            }
            if map.isMapInteractive,
               map.locationAuthorizationState == .authorized {
                return .send(.map(.periodicLocationRefreshSchedulingRequested))
            }
            return .none

        case let .currentLocationPermissionDenied(source, authorizationState):
            guard map.locationState == .requesting else { return .none }
            map.locationAuthorizationState = authorizationState
            map.locationState = .unavailable
            map.hasCompletedInitialLocationResolution = true
            map.userLocation = nil
            map.userHeadingDegrees = nil
            if source == .userInitiated {
                resetToKoreaOverview(&map)
                presentation.isLocationSettingsAlertPresented = true
            }
            return .none

        case .placeCoordinatesLoaded(let coordinates):
            guard map.markerState == .loading else { return .none }
            map.markerState = .loaded
            map.mapItems = coordinates.map(RodiCourseItem.init(placeCoordinate:))
            map.markerRenderingGeneration += 1

            let tierResolution = markerTierResolver.resolve(
                zoomLevel: map.mapZoomLevel,
                forcedTier: map.forcedMarkerTier,
                forcedTierZoomLevel: map.forcedMarkerTierZoomLevel
            )
            map.forcedMarkerTier = tierResolution.forcedTier
            map.forcedMarkerTierZoomLevel = tierResolution.forcedTierZoomLevel
            map.displayedMarkerTier = tierResolution.tier

            return markerRenderingEffect(
                RodiHomeMarkerClusterIndex.markers(
                    for: map.mapItems,
                    tier: tierResolution.tier,
                    selectedMarkerID: map.selectedMarkerID
                ),
                generation: map.markerRenderingGeneration,
                reportsInitialCompletion: true
            )

        case .placeCoordinatesLoadFailed:
            guard map.markerState == .loading else { return .none }
            map.markerState = .failed
            return .none

        case .userHeadingUpdated(let degrees):
            map.userHeadingDegrees = degrees
            return .none
        }
    }
}


// MARK: - Effect

extension HomeReducer {

    private func actions(_ actions: [Action]) -> Effect<Action> {
        .run { send in
            for action in actions {
                await send(action)
            }
        }
    }

    private func updateMapVisibility(
        wasMapInteractive: Bool, state: inout MapState) -> Effect<Action> {
        guard wasMapInteractive != state.isMapInteractive else { return .none }

        guard state.isMapInteractive else {
            state.markerRenderingGeneration += 1
            return .cancel(id: CancellationID.progressiveMarkerRendering)
        }

        switch state.mapLifecycle {
        case .inactive:
            state.mapLifecycle = .activating
            return .none

        case .activating:
            return .none

        case .ready:
            if state.markerState == .idle {
                return initialMapDataLoadEffect()
            }

            if state.markerState == .loaded,
               let tier = state.displayedMarkerTier {
                state.markers = RodiHomeMarkerClusterIndex.markers(
                    for: state.mapItems,
                    tier: tier,
                    selectedMarkerID: state.selectedMarkerID
                )
                state.hasCompletedInitialMarkerRendering = true
            }
            return .send(.map(.periodicLocationRefreshSchedulingRequested))
        }
    }

    private func focusMap(on detail: PlaceDetail, state: inout MapState) {
        state.cameraTarget = RodiCoordinate(latitude: detail.latitude, longitude: detail.longitude)
        state.cameraFocus = .closeSingleLocation
        state.cameraRequestID += 1
        state.animatedCameraRequestID = state.cameraRequestID
    }

    private func selectResolvedPlaceMarker(_ detail: PlaceDetail, state: inout MapState) {
        let markerID = detail.type == .course
            ? "course-\(detail.id)"
            : "parking-\(detail.id)"

        if state.selectedMarkerID != markerID {
            state.selectedMarkerID = markerID
            state.markerRenderingGeneration += 1
            state.forcedMarkerTier = .individual
            state.forcedMarkerTierZoomLevel = nil
            state.displayedMarkerTier = .individual
            state.markers = RodiHomeMarkerClusterIndex.markers(
                for: state.mapItems,
                tier: .individual,
                selectedMarkerID: markerID
            )
            if state.markerState == .loaded {
                state.hasCompletedInitialMarkerRendering = true
            }
            focusMap(on: detail, state: &state)
        }
    }

    private func resetToKoreaOverview(_ state: inout MapState) {
        state.userLocation = nil
        state.cameraTarget = .southKoreaCenter
        state.cameraFocus = .koreaOverview
        state.cameraRequestID += 1
        state.animatedCameraRequestID = nil
    }

    private func shouldShowProlongedLocationUnavailableNotice(for map: MapState) -> Bool {
        guard !map.hasShownProlongedLocationUnavailableNotice,
              map.userLocation != nil,
              let lastLocationResolvedAt = map.lastLocationResolvedAt
        else {
            return false
        }

        return Date().timeIntervalSince(lastLocationResolvedAt)
            >= Self.prolongedLocationUnavailableInterval
    }

    private func initialMapDataLoadEffect() -> Effect<Action> {
        .run { send in
            await send(.map(.initialLocationRequested))
            await send(.map(.initialMarkersLoadRequested))
        }
    }

    private func mapServiceEffect(_ input: MapServiceInAction) -> Effect<Action> {
        let mapService = mapService
        return .run { send in
            guard let output = await mapService.perform(input) else { return }
            await send(.map(.serviceOutput(output)))
        }
    }

    private func userHeadingUpdatesEffect(origin: RodiCoordinate) -> Effect<Action> {
        let mapService = mapService
        return .run { send in
            await send(.bottomSheet(.recommendList(.prepareInitialSearch(origin: origin))))
            await send(.map(.periodicLocationRefreshSchedulingRequested))

            let updates = mapService.userHeadingUpdates()
            for await degrees in updates {
                guard !Task.isCancelled else { return }
                await send(.map(.serviceOutput(.userHeadingUpdated(degrees))))
            }
        }
        .cancelTask(id: CancellationID.userHeadingUpdates)
    }

    private func periodicLocationRefreshEffect() -> Effect<Action> {
        let delay = Self.periodicLocationRefreshNanoseconds
        return .run { send in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await send(.map(.periodicLocationRefreshTimerFired))
        }
        .cancelTask(id: CancellationID.periodicLocationRefresh)
    }

    private func markerRenderingEffect(
        _ markers: [RodiMapMarker],
        generation: Int,
        reportsInitialCompletion: Bool = false
    ) -> Effect<Action> {
        let snapshots = markerRenderingService.progressiveSnapshots(for: markers)
        return .run { send in
            for await snapshot in snapshots {
                guard !Task.isCancelled else { return }
                await send(.map(.markerRenderBatchUpdated(snapshot, generation: generation)))
            }

            guard reportsInitialCompletion, !Task.isCancelled else { return }

            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await send(.map(.initialMarkerRenderingFinished(generation: generation)))
        }
        .cancelTask(id: CancellationID.progressiveMarkerRendering)
    }
}
