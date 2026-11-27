//
//  HomeMapReducer.swift
//  Rodi
//

import Foundation

@MainActor
struct HomeMapReducer: Reducer {
    typealias State = HomeMapState

    struct Dependencies {
        let placeRepository: PlaceRepository
        let hasActiveSession: () -> Bool
    }

    enum Action {
        case tabSelectionChanged(Bool)
        case activityChanged(Bool)
        case locationAuthorizationRefreshRequested
        case engineFailed
        case engineRetryRequested
        case userBeganExploring
        case becameReady
        case viewportChanged(center: RodiCoordinate, zoomLevel: Int, viewport: PlaceViewport, isUserInitiated: Bool)
        case markerTapped(String)
        case savedPlaceSelected(PlaceListItem)
        case cameraMoveFinished(Int, viewport: PlaceViewport?)
        case nationwideBrowseRequested
        case currentLocationRequested
        case markerRetryRequested
        case recommendationResearchButtonTapped
        case searchEntryTapped
        case searchSelectionClearTapped
        case initialLocationRequested
        case initialLocationWaitExpired
        case clusterQueryRequested(PlaceClusterQuery, listRevision: Int)
        case periodicLocationRefreshSchedulingRequested
        case periodicLocationRefreshTimerFired
        case serviceOutput(MapServiceOutAction)
        case markerRenderBatchUpdated([RodiMapMarker], generation: Int, isFinal: Bool)
        case placeResolved(PlaceDetail)
        case searchPlaceSelected(String)
        case regionSelected(name: String, center: RodiCoordinate)
        case routeOverlayChanged(RodiRouteOverlay?)
        case focusRequested(RodiCoordinate)
        case detailDismissed
        case currentLocationReady
        case researchButtonVisibilityChanged(Bool)
        case recommendationCollapsed
        case delegate(Delegate)
    }

    enum Delegate {
        case requestAuthentication
        case showLocationSettingsAlert(Bool)
        case showSnackbar(String)
        case bottomTabBarVisibilityChanged(Bool)
        case searchEntryRequested(origin: RodiCoordinate)
        case searchSelectionClearRequested
        case resolvePlace(Int)
        case resolveSavedPlace(PlaceListItem)
        case prepareForCurrentLocation
        case reloadCurrentViewport(origin: RodiCoordinate?)
        case viewportChanged(PlaceViewport, center: RodiCoordinate, isUserInitiated: Bool)
        case reloadAfterRegionViewport(viewport: PlaceViewport, origin: RodiCoordinate)
        case presentRecommendListForRegion(origin: RodiCoordinate)
        case initialNationwideRequested
    }

    private enum CancellationID: Hashable {
        case progressiveMarkerRendering
        case clusterLoading
        case userHeadingUpdates
        case periodicLocationRefresh
        case initialLocationWait
    }

    private static let periodicLocationRefreshNanoseconds: UInt64 = 60_000_000_000
    private static let prolongedLocationUnavailableInterval: TimeInterval = 60

    private let mapService: MapService
    private let markerRenderingService = MapMarkerRenderingService()
    private let hasActiveSession: () -> Bool

    init(dependencies: Dependencies) {
        mapService = MapService(
            placeRepository: dependencies.placeRepository,
            locationService: MapLocationService()
        )
        hasActiveSession = dependencies.hasActiveSession
    }

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .tabSelectionChanged(let isSelected):
            let wasInteractive = state.isMapInteractive
            state.isHomeTabSelected = isSelected
            if !isSelected { state.isCurrentLocationButtonActive = false }
            return updateVisibility(wasInteractive: wasInteractive, state: &state)

        case .activityChanged(let isActive):
            let wasInteractive = state.isMapInteractive
            state.isAppActive = isActive
            if !isActive { state.isCurrentLocationButtonActive = false }
            return updateVisibility(wasInteractive: wasInteractive, state: &state)

        case .locationAuthorizationRefreshRequested:
            let authorization = mapService.locationAuthorizationState
            state.locationAuthorizationState = authorization
            switch authorization {
            case .authorized:
                guard state.mapLifecycle == .ready, state.locationState != .requesting else {
                    return state.isMapInteractive ? .send(.periodicLocationRefreshSchedulingRequested) : .none
                }
                guard state.userLocation == nil else {
                    return state.isMapInteractive ? .send(.periodicLocationRefreshSchedulingRequested) : .none
                }
                state.locationState = .requesting
                let source: LocationRequestSource = state.hasCompletedInitialLocationResolution ? .foregroundRefresh : .initial
                return authorizationRefreshEffect(source: source)
            case .denied, .restricted:
                state.isWaitingForInitialLocation = false
                state.initialLocationCameraRequestID = nil
                state.locationState = .unavailable
                state.hasCompletedInitialLocationResolution = true
                state.userLocation = nil
                state.userHeadingDegrees = nil
                return .cancel(id: CancellationID.userHeadingUpdates)
            case .notDetermined:
                if state.userLocation == nil, state.locationState == .unavailable { state.locationState = .idle }
                return .none
            }

        case .engineFailed:
            state.isWaitingForInitialLocation = false
            state.initialLocationCameraRequestID = nil
            state.mapLifecycle = .failed
            return .none

        case .engineRetryRequested:
            guard state.mapLifecycle == .failed else { return .none }
            state.mapLifecycle = .activating
            return .none

        case .userBeganExploring:
            preserveExploration(&state)
            return .none

        case .becameReady:
            guard state.mapLifecycle == .activating else { return .none }
            let wasLoading = state.initialLoadingStage != nil
            state.isWaitingForInitialLocation = state.isMapInteractive && state.allowsInitialLocationFocus
                && !state.hasCompletedInitialLocationResolution && state.userLocation == nil
                && mapService.locationAuthorizationState == .authorized
            state.mapLifecycle = .ready
            focusInitialLocationIfPossible(&state, beforeReveal: wasLoading)
            if state.isWaitingForInitialLocation {
                // GPS와 지도·마커 준비를 병렬로 진행하고 첫 화면만 최대 1초 유예한다.
                return .run { send in
                    await send(.initialLocationRequested)
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                    guard !Task.isCancelled else { return }
                    await send(.initialLocationWaitExpired)
                }
                .cancelTask(id: CancellationID.initialLocationWait)
            }
            return state.isMapInteractive ? initialMapDataLoadEffect() : .none

        case let .viewportChanged(center, _, viewport, isUserInitiated):
            guard viewport.isValidForPlaceQuery else { return .none }
            let wasLoading = state.initialLoadingStage != nil
            if isUserInitiated {
                preserveExploration(&state)
                state.isCurrentLocationButtonActive = false
            }
            state.hasReceivedInitialViewport = true
            focusInitialLocationIfPossible(&state, beforeReveal: wasLoading)
            state.visibleLongitudeSpan = viewport.longitudeSpan
            if let span = state.visibleLongitudeSpan,
               let level = state.clusterResult?.levelIndex(for: span),
               state.displayedClusterLevel != level {
                state.displayedClusterLevel = level
                state.markerRenderingGeneration += 1
                rebuildMarkers(&state)
            }
            var delegates: [Action] = [.delegate(.viewportChanged(viewport, center: center, isUserInitiated: isUserInitiated))]
            if !isUserInitiated,
               state.cameraFocus != .koreaOverview,
               state.pendingRegionCameraRequestID == state.cameraRequestID,
               let origin = state.pendingRegionViewportReloadOrigin {
                state.pendingRegionCameraRequestID = nil
                state.pendingRegionViewportReloadOrigin = nil
                delegates.append(.delegate(.reloadAfterRegionViewport(viewport: viewport, origin: origin)))
            }
            return actions(delegates)

        case .markerTapped(let markerID):
            preserveExploration(&state)
            guard let marker = state.markers.first(where: { $0.id == markerID }) else { return .none }
            switch marker.kind {
            case .cluster:
                guard let bounds = state.clusterBoundsByMarkerID[markerID] else { return .none }
                state.isCurrentLocationButtonActive = false
                state.selectedMarkerID = nil
                state.routeOverlay = nil
                state.markerRenderingGeneration += 1
                rebuildMarkers(&state)
                state.cameraTarget = marker.coordinate
                state.cameraFocus = .cluster(coordinates: [
                    .init(latitude: bounds.southWestLatitude, longitude: bounds.southWestLongitude),
                    .init(latitude: bounds.northEastLatitude, longitude: bounds.northEastLongitude)
                ])
                requestCamera(&state)
                return .cancel(id: CancellationID.progressiveMarkerRendering)
            case .course, .parking:
                guard let placeID = Int(markerID.split(separator: "-").last ?? "") else { return .none }
                guard hasActiveSession() else {
                    return .send(.delegate(.requestAuthentication))
                }
                state.isCurrentLocationButtonActive = false
                state.routeOverlay = nil
                state.selectedSearchResultName = marker.title
                state.selectedMarkerID = markerID
                state.markerRenderingGeneration += 1
                state.cameraTarget = marker.coordinate
                state.cameraFocus = marker.kind == .course ? .courseMarker : .closeSingleLocation
                requestCamera(&state)
                rebuildMarkers(&state)
                return actions([.delegate(.bottomTabBarVisibilityChanged(false)), .delegate(.resolvePlace(placeID))])
            }

        case .savedPlaceSelected(let place):
            preserveExploration(&state)
            state.isCurrentLocationButtonActive = false
            state.routeOverlay = nil
            state.selectedSearchResultName = place.name
            selectMarker(id: markerID(for: place.type, id: place.id), coordinate: .init(latitude: place.latitude, longitude: place.longitude), focus: .closeSingleLocation, state: &state)
            return effects([.delegate(.bottomTabBarVisibilityChanged(false)), .delegate(.resolveSavedPlace(place))], cancellation: .progressiveMarkerRendering)

        case let .cameraMoveFinished(requestID, viewport):
            guard requestID == state.cameraRequestID else { return .none }
            if state.initialLocationCameraRequestID == requestID {
                state.initialLocationCameraRequestID = nil
                if let viewport, viewport.isValidForPlaceQuery {
                    return reduce(&state, with: .viewportChanged(center: state.cameraTarget, zoomLevel: 0,
                                                                 viewport: viewport, isUserInitiated: false))
                }
                return .none
            }
            if let viewport, viewport.isValidForPlaceQuery {
                if !state.hasReceivedInitialViewport, state.cameraFocus == .koreaOverview,
                   state.pendingRegionCameraRequestID == nil {
                    return reduce(&state, with: .viewportChanged(center: state.cameraTarget, zoomLevel: 0,
                                                                 viewport: viewport, isUserInitiated: false))
                }
            }
            guard state.animatedCameraRequestID == requestID else { return .none }
            state.animatedCameraRequestID = nil
            if state.cameraFocus == .koreaOverview,
               state.pendingRegionCameraRequestID == requestID,
               let origin = state.pendingRegionViewportReloadOrigin, let viewport, viewport.isValidForPlaceQuery {
                state.pendingRegionCameraRequestID = nil
                state.pendingRegionViewportReloadOrigin = nil
                state.visibleLongitudeSpan = viewport.longitudeSpan
                return .send(.delegate(.reloadAfterRegionViewport(viewport: viewport, origin: origin)))
            }
            return .none

        case .nationwideBrowseRequested:
            preserveExploration(&state)
            state.routeOverlay = nil
            state.selectedMarkerID = nil
            state.selectedSearchResultName = nil
            state.isCurrentLocationButtonActive = false
            state.isListResearchButtonVisible = false
            state.didClusterRefreshFail = false
            state.clusterRequestRevision += 1
            rebuildMarkers(&state)
            state.cameraTarget = .southKoreaCenter
            state.cameraFocus = .koreaOverview
            requestCamera(&state)
            state.pendingRegionViewportReloadOrigin = state.cameraTarget
            state.pendingRegionCameraRequestID = state.cameraRequestID
            return .cancel(id: CancellationID.clusterLoading)

        case .currentLocationRequested:
            guard state.mapLifecycle == .ready, state.locationState != .requesting else { return .none }
            state.isCurrentLocationButtonActive = true
            return .send(.delegate(.prepareForCurrentLocation))

        case .recommendationResearchButtonTapped:
            preserveExploration(&state)
            state.routeOverlay = nil
            state.selectedMarkerID = nil
            state.selectedSearchResultName = nil
            rebuildMarkers(&state)
            return .send(.delegate(.reloadCurrentViewport(origin: state.userLocation)))

        case .searchEntryTapped:
            preserveExploration(&state)
            guard hasActiveSession() else { return .send(.delegate(.requestAuthentication)) }
            state.isCurrentLocationButtonActive = false
            return .send(.delegate(.searchEntryRequested(origin: state.cameraTarget)))

        case .searchSelectionClearTapped:
            clearSelection(&state)
            return actions([.delegate(.bottomTabBarVisibilityChanged(true)), .delegate(.searchSelectionClearRequested)])

        case .markerRetryRequested:
            guard state.markerState == .failed, let query = state.clusterQuery else { return .none }
            return loadClusters(query, state: &state)

        case .initialLocationRequested:
            guard state.mapLifecycle == .ready, state.locationState == .idle else { return .none }
            state.locationAuthorizationState = mapService.locationAuthorizationState
            state.locationState = .requesting
            return mapServiceEffect(.requestCurrentLocation(source: .initial))

        case .initialLocationWaitExpired:
            state.isWaitingForInitialLocation = false
            return .none

        case let .clusterQueryRequested(query, listRevision):
            guard listRevision >= state.clusterListRevision else { return .none }
            state.clusterListRevision = listRevision
            return loadClusters(query, state: &state)

        case .periodicLocationRefreshSchedulingRequested:
            guard state.isMapInteractive, state.mapLifecycle == .ready, state.locationAuthorizationState == .authorized, state.locationState != .requesting else {
                return .cancel(id: CancellationID.periodicLocationRefresh)
            }
            return periodicLocationRefreshEffect()

        case .periodicLocationRefreshTimerFired:
            guard state.isMapInteractive, state.mapLifecycle == .ready, mapService.locationAuthorizationState == .authorized, state.locationState != .requesting else { return .none }
            state.locationAuthorizationState = .authorized
            state.locationState = .requesting
            return mapServiceEffect(.requestCurrentLocation(source: .periodicRefresh))

        case .serviceOutput(let output):
            return reduceServiceOutput(output, state: &state)

        case .markerRenderBatchUpdated(let markers, let generation, let isFinal):
            guard state.markerState == .loaded, state.markerRenderingGeneration == generation else { return .none }
            state.markers = markers.map { .init(id: $0.id, kind: $0.kind, title: $0.title, coordinate: $0.coordinate, isSelected: $0.id == state.selectedMarkerID) }
            if isFinal { state.hasFinishedInitialMarkerLoad = true }
            return .none

        case .placeResolved(let detail):
            selectMarker(id: markerID(for: detail.type, id: detail.id), coordinate: .init(latitude: detail.latitude, longitude: detail.longitude), focus: .closeSingleLocation, state: &state)
            return .send(.delegate(.bottomTabBarVisibilityChanged(false)))

        case .searchPlaceSelected(let name):
            preserveExploration(&state)
            state.selectedSearchResultName = name
            state.routeOverlay = nil
            state.isListResearchButtonVisible = false
            rebuildMarkers(&state)
            return .none

        case let .regionSelected(name, center):
            preserveExploration(&state)
            state.selectedSearchResultName = name
            state.routeOverlay = nil
            state.selectedMarkerID = nil
            state.isListResearchButtonVisible = false
            state.didClusterRefreshFail = false
            state.clusterRequestRevision += 1
            rebuildMarkers(&state)
            state.cameraTarget = center
            state.cameraFocus = .region
            requestCamera(&state)
            state.pendingRegionViewportReloadOrigin = center
            state.pendingRegionCameraRequestID = state.cameraRequestID
            return .send(.delegate(.presentRecommendListForRegion(origin: center)))

        case .routeOverlayChanged(let overlay):
            state.routeOverlay = overlay
            return .none

        case .focusRequested(let coordinate):
            preserveExploration(&state)
            state.cameraTarget = coordinate
            state.cameraFocus = .closeSingleLocation
            requestCamera(&state)
            return .none

        case .detailDismissed:
            clearSelection(&state)
            return .send(.delegate(.bottomTabBarVisibilityChanged(true)))

        case .currentLocationReady:
            guard state.mapLifecycle == .ready, state.locationState != .requesting else { return .none }
            state.locationState = .requesting
            return mapServiceEffect(.requestCurrentLocation(source: .userInitiated))

        case .researchButtonVisibilityChanged(let visible):
            state.isListResearchButtonVisible = visible
            return .none

        case .recommendationCollapsed:
            state.selectedSearchResultName = nil
            return .none

        case .delegate:
            return .none
        }
    }
}

private extension HomeMapReducer {
    func reduceServiceOutput(_ output: MapServiceOutAction, state: inout State) -> Effect<Action> {
        switch output {
        case let .currentLocationResolved(coordinate, source):
            guard state.locationState == .requesting else { return .none }
            state.locationAuthorizationState = .authorized
            state.locationState = .resolved
            state.hasCompletedInitialLocationResolution = true
            state.userLocation = coordinate
            state.lastLocationResolvedAt = Date()
            state.hasShownProlongedLocationUnavailableNotice = false
            if source == .userInitiated {
                preserveExploration(&state)
                state.cameraTarget = coordinate
                state.cameraFocus = .currentLocation
                state.cameraRequestID += 1
                state.animatedCameraRequestID = nil
            }
            focusInitialLocationIfPossible(&state)
            state.isWaitingForInitialLocation = false
            if source == .periodicRefresh { return .send(.periodicLocationRefreshSchedulingRequested) }
            return userHeadingUpdatesEffect()

        case .currentLocationUnavailable(let source):
            guard state.locationState == .requesting else { return .none }
            state.isWaitingForInitialLocation = false
            state.locationAuthorizationState = mapService.locationAuthorizationState
            state.locationState = .unavailable
            state.hasCompletedInitialLocationResolution = true
            var followUp: [Action] = []
            if source == .userInitiated {
                followUp.append(.delegate(.showSnackbar("현재 위치를 확인할 수 없어요. 다시 시도해주세요.")))
            } else if source == .periodicRefresh, shouldShowProlongedUnavailableNotice(for: state) {
                state.hasShownProlongedLocationUnavailableNotice = true
                followUp.append(.delegate(.showSnackbar("현재 위치를 확인할 수 없어요. 위치 신호가 안정되면 다시 갱신할게요.")))
            }
            if state.isMapInteractive, state.locationAuthorizationState == .authorized { followUp.append(.periodicLocationRefreshSchedulingRequested) }
            return actions(followUp)

        case let .currentLocationPermissionDenied(source, authorizationState):
            guard state.locationState == .requesting else { return .none }
            state.isWaitingForInitialLocation = false
            state.locationAuthorizationState = authorizationState
            state.locationState = .unavailable
            state.hasCompletedInitialLocationResolution = true
            state.userLocation = nil
            state.userHeadingDegrees = nil
            guard source == .userInitiated else { return .none }
            return .send(.delegate(.showLocationSettingsAlert(true)))

        case let .clustersLoaded(result, revision):
            guard revision == state.clusterRequestRevision else { return .none }
            guard let span = state.visibleLongitudeSpan ?? state.clusterQuery?.viewport.longitudeSpan,
                  let level = result.levelIndex(for: span) else {
                return reduceServiceOutput(.clusterLoadFailed(revision: revision), state: &state)
            }
            let isFirstResult = state.clusterResult == nil
            state.markerState = .loaded
            state.clusterResult = result
            state.displayedClusterLevel = level
            state.didClusterRefreshFail = false
            state.markerRenderingGeneration += 1
            let markers = serverMarkers(&state)
            if isFirstResult, state.isMapInteractive {
                return markerRenderingEffect(markers, generation: state.markerRenderingGeneration)
            }
            state.markers = markers
            state.hasFinishedInitialMarkerLoad = true
            return .none

        case .clusterLoadFailed(let revision):
            guard revision == state.clusterRequestRevision else { return .none }
            if state.clusterResult == nil {
                state.markerState = .failed
                state.hasFinishedInitialMarkerLoad = true
            } else {
                state.didClusterRefreshFail = true
            }
            return .none

        case .userHeadingUpdated(let degrees):
            state.userHeadingDegrees = degrees
            return .none
        }
    }

    func updateVisibility(wasInteractive: Bool, state: inout State) -> Effect<Action> {
        guard wasInteractive != state.isMapInteractive else { return .none }
        guard state.isMapInteractive else {
            state.markerRenderingGeneration += 1
            return .cancel(id: CancellationID.progressiveMarkerRendering)
        }
        switch state.mapLifecycle {
        case .inactive:
            state.mapLifecycle = .activating
            return .send(.delegate(.initialNationwideRequested))
        case .activating, .failed:
            return .none
        case .ready:
            focusInitialLocationIfPossible(&state)
            if state.markerState == .idle { return initialMapDataLoadEffect() }
            if state.markerState == .loaded {
                rebuildMarkers(&state)
            }
            return .send(.periodicLocationRefreshSchedulingRequested)
        }
    }

    func clearSelection(_ state: inout State) {
        state.selectedSearchResultName = nil
        state.routeOverlay = nil
        state.selectedMarkerID = nil
        state.isListResearchButtonVisible = false
        rebuildMarkers(&state)
    }

    func selectMarker(id: String, coordinate: RodiCoordinate, focus: RodiMapCameraFocus, state: inout State) {
        guard state.selectedMarkerID != id else { return }
        state.selectedMarkerID = id
        state.markerRenderingGeneration += 1
        rebuildMarkers(&state)
        state.cameraTarget = coordinate
        state.cameraFocus = focus
        requestCamera(&state)
    }

    func rebuildMarkers(_ state: inout State) {
        state.markers = serverMarkers(&state)
        if state.clusterResult != nil { state.hasFinishedInitialMarkerLoad = true }
    }

    func serverMarkers(_ state: inout State) -> [RodiMapMarker] {
        guard let result = state.clusterResult, let index = state.displayedClusterLevel else { return [] }
        let level = result.levels[index]
        let individualIDs = Set(level.placeIDs)
        let selectedID = state.selectedMarkerID
        state.clusterBoundsByMarkerID = [:]
        let clusters = level.clusters.enumerated().map { offset, cluster in
            let id = "server-cluster-\(index)-\(offset)"
            state.clusterBoundsByMarkerID[id] = cluster.bounds
            return RodiMapMarker(id: id, kind: .cluster, title: String(cluster.count),
                                 coordinate: .init(latitude: cluster.latitude, longitude: cluster.longitude))
        }
        let places = result.places.compactMap { place -> RodiMapMarker? in
            guard individualIDs.contains(place.id) else { return nil }
            let id = markerID(for: place.type, id: place.id)
            return .init(id: id, kind: place.type == .course ? .course : .parking, title: place.name,
                         coordinate: .init(latitude: place.latitude, longitude: place.longitude),
                         isSelected: selectedID == id)
        }
        return clusters + places
    }

    func loadClusters(_ query: PlaceClusterQuery, state: inout State) -> Effect<Action> {
        guard query.viewport.isValidForPlaceQuery else { return .none }
        state.clusterQuery = query
        state.clusterRequestRevision += 1
        state.didClusterRefreshFail = false
        if state.clusterResult == nil { state.markerState = .loading }
        return mapServiceEffect(.loadClusters(query, revision: state.clusterRequestRevision))
            .cancelTask(id: CancellationID.clusterLoading)
    }

    func preserveExploration(_ state: inout State) {
        state.allowsInitialLocationFocus = false
        state.isWaitingForInitialLocation = false
        state.initialLocationCameraRequestID = nil
    }

    func focusInitialLocationIfPossible(_ state: inout State, beforeReveal: Bool? = nil) {
        // 홈이 이미 표시된 뒤 받은 위치는 내 위치 점만 갱신한다.
        guard state.allowsInitialLocationFocus, beforeReveal ?? (state.initialLoadingStage != nil),
              state.hasReceivedInitialViewport,
              state.isMapInteractive, state.mapLifecycle == .ready, let location = state.userLocation else { return }
        state.allowsInitialLocationFocus = false
        state.cameraTarget = location
        state.cameraFocus = .currentLocation
        state.cameraRequestID += 1
        state.initialLocationCameraRequestID = state.cameraRequestID
        state.animatedCameraRequestID = nil
    }

    func requestCamera(_ state: inout State) {
        state.cameraRequestID += 1
        state.animatedCameraRequestID = state.cameraRequestID
    }

    func markerID(for type: PlaceType, id: Int) -> String {
        type == .course ? "course-\(id)" : "parking-\(id)"
    }

    func shouldShowProlongedUnavailableNotice(for state: State) -> Bool {
        guard !state.hasShownProlongedLocationUnavailableNotice, state.userLocation != nil, let date = state.lastLocationResolvedAt else { return false }
        return Date().timeIntervalSince(date) >= Self.prolongedLocationUnavailableInterval
    }

    func initialMapDataLoadEffect() -> Effect<Action> {
        .send(.initialLocationRequested)
    }

    func mapServiceEffect(_ input: MapServiceInAction) -> Effect<Action> {
        let mapService = mapService
        return .run { send in
            guard let output = await mapService.perform(input) else { return }
            await send(.serviceOutput(output))
        }
    }

    func userHeadingUpdatesEffect() -> Effect<Action> {
        let mapService = mapService
        return .run { send in
            await send(.periodicLocationRefreshSchedulingRequested)
            for await degrees in mapService.userHeadingUpdates() {
                guard !Task.isCancelled else { return }
                await send(.serviceOutput(.userHeadingUpdated(degrees)))
            }
        }
        .cancelTask(id: CancellationID.userHeadingUpdates)
    }

    func periodicLocationRefreshEffect() -> Effect<Action> {
        let delay = Self.periodicLocationRefreshNanoseconds
        return .run { send in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard !Task.isCancelled else { return }
            await send(.periodicLocationRefreshTimerFired)
        }
        .cancelTask(id: CancellationID.periodicLocationRefresh)
    }

    func markerRenderingEffect(_ markers: [RodiMapMarker], generation: Int) -> Effect<Action> {
        let snapshots = markerRenderingService.progressiveSnapshots(for: markers)
        return .run { send in
            for await snapshot in snapshots {
                guard !Task.isCancelled else { return }
                await send(.markerRenderBatchUpdated(snapshot, generation: generation, isFinal: snapshot.count == markers.count))
            }
        }
        .cancelTask(id: CancellationID.progressiveMarkerRendering)
    }

    func actions(_ actions: [Action]) -> Effect<Action> {
        .run { send in
            for action in actions { await send(action) }
        }
    }

    func authorizationRefreshEffect(source: LocationRequestSource) -> Effect<Action> {
        let mapService = mapService
        return .run { send in
            await send(.delegate(.showLocationSettingsAlert(false)))
            guard let output = await mapService.perform(.requestCurrentLocation(source: source)) else { return }
            await send(.serviceOutput(output))
        }
    }

    private func effects(_ actions: [Action], cancellation: CancellationID? = nil) -> Effect<Action> {
        let effect = self.actions(actions)
        guard let cancellation else { return effect }
        return effect.cancelTask(id: cancellation)
    }
}
