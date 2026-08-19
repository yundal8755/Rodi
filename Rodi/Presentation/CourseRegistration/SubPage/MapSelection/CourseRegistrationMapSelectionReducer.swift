import Foundation

struct CourseRegistrationMapSelectionReducer: Reducer {
    struct State: Equatable {
        var waypoints: [CourseRegistrationWaypoint] = []
        var selectedPlaces: [CourseRegistrationInputTarget: CourseRegistrationSelectedPlace] = [:]
        var routePath: [RodiCoordinate] = []
        var isRouteLoading = false
        var routeRequestRevision = 0
        var map = CourseRegistrationMapState()
        var hasTrackedRegistrationOpened = false

        init(isCourseTutorialCompleted: Bool = false) {
            if isCourseTutorialCompleted {
                map.selectionTarget = .start
            }
        }

        var hasInput: Bool {
            !waypoints.isEmpty || !selectedPlaces.isEmpty || !routePath.isEmpty
        }

        func routePoints(
            replacing replacement: (CourseRegistrationInputTarget, CourseRegistrationSelectedPlace)? = nil
        ) -> [RodiRouteOverlayPoint] {
            orderedTargets.enumerated().compactMap { index, target in
                let place = replacement?.0 == target ? replacement?.1 : selectedPlaces[target]
                guard let place else { return nil }
                return .init(
                    id: index,
                    sequence: index,
                    role: target.routePointRole,
                    name: place.name,
                    coordinate: place.coordinate
                )
            }
        }

        func target(at pointID: Int) -> CourseRegistrationInputTarget? {
            guard orderedTargets.indices.contains(pointID) else { return nil }
            return orderedTargets[pointID]
        }

        private var orderedTargets: [CourseRegistrationInputTarget] {
            var targets: [CourseRegistrationInputTarget] = []
            if selectedPlaces[.start] != nil {
                targets.append(.start)
            }
            targets += waypoints.compactMap { waypoint in
                selectedPlaces[.waypoint(waypoint.id)] == nil ? nil : .waypoint(waypoint.id)
            }
            if selectedPlaces[.destination] != nil {
                targets.append(.destination)
            }
            return targets
        }
    }

    enum Action {
        case prepareStartSelection
        case appeared
        case deactivated
        case closeTapped
        case reset
        case waypointAddTapped
        case waypointRemoveTapped(UUID)
        case currentLocationTapped
        case currentLocationResolved(LocationRequest, CourseRegistrationMapService.CurrentLocationResult)
        case viewportChanged(RodiCoordinate, isUserInitiated: Bool)
        case placeSelectionTapped
        case reverseGeocodingFinished(AddressRequest, Result<String, CourseRegistrationAddressLookupError>)
        case selectionCompletionTapped
        case registrationCompletionTapped
        case inputTargetTapped(CourseRegistrationInputTarget)
        case searchResultSelected(CourseRegistrationInputTarget, CourseRegistrationPlaceSearchItem)
        case routePointTapped(Int)
        case pinEditApplied(CourseRegistrationInputTarget, CourseRegistrationSelectedPlace, [RodiCoordinate]?)
        case initialRouteFinished(Int, Result<[RodiCoordinate], KakaoDirectionsError>)
        case delegate(Delegate)
    }

    enum Delegate {
        case openSearch(CourseRegistrationInputTarget)
        case openPinEdit(CourseRegistrationInputTarget, CourseRegistrationSelectedPlace)
        case openDetails(CourseRegistrationDetailsContext)
        case closeRequested(hasInput: Bool)
        case showError(String)
    }

    private enum EffectID: Hashable {
        case work
    }

    struct LocationRequest: Equatable {
        enum Source: Equatable {
            case initial
            case userAction
        }

        let revision: Int
        let source: Source
    }

    struct AddressRequest: Equatable {
        let revision: Int
        let target: CourseRegistrationInputTarget
        let coordinate: RodiCoordinate
    }

    private let mapService: CourseRegistrationMapService
    private let directionsService: KakaoDirectionsService

    init(
        mapService: CourseRegistrationMapService? = nil,
        directionsService: KakaoDirectionsService = .init()
    ) {
        self.mapService = mapService ?? CourseRegistrationMapService()
        self.directionsService = directionsService
    }

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .prepareStartSelection:
            beginSelection(.start, state: &state)

        case .appeared:
            guard !state.map.hasRequestedInitialLocation else { return .none }
            if !state.hasTrackedRegistrationOpened {
                state.hasTrackedRegistrationOpened = true
                RodiAnalytics.track(.courseRegistrationOpened)
            }
            state.map.hasRequestedInitialLocation = true
            state.map.locationRequestRevision += 1
            return requestCurrentLocation(.init(
                revision: state.map.locationRequestRevision,
                source: .initial
            ))

        case .deactivated:
            state.map.locationRequestRevision += 1
            state.map.addressRequestRevision += 1
            state.routeRequestRevision += 1
            state.map.isCurrentLocationActive = false
            state.map.isAddressResolving = false
            state.isRouteLoading = false
            return .cancel(id: EffectID.work)

        case .closeTapped:
            return .send(.delegate(.closeRequested(hasInput: state.hasInput)))

        case .reset:
            state = .init()

        case .waypointAddTapped:
            guard state.map.selectionTarget == nil, state.waypoints.count < 3 else { return .none }
            let waypoint = CourseRegistrationWaypoint()
            state.waypoints.append(waypoint)
            state.routePath = []
            RodiAnalytics.track(
                .courseRegistrationWaypointChanged(action: "added", waypointCount: state.waypoints.count)
            )
            beginSelection(.waypoint(waypoint.id), state: &state)

        case .waypointRemoveTapped(let id):
            guard state.waypoints.contains(where: { $0.id == id }) else { return .none }
            state.waypoints.removeAll { $0.id == id }
            state.selectedPlaces[.waypoint(id)] = nil
            state.routePath = []
            RodiAnalytics.track(
                .courseRegistrationWaypointChanged(action: "removed", waypointCount: state.waypoints.count)
            )

            if state.map.selectionTarget == .waypoint(id) {
                state.map.selectionTarget = nil
                state.map.candidateCoordinate = nil
                state.map.hasSelectedCurrentTarget = false
                state.map.isAddressResolving = false
                state.map.addressRequestRevision += 1
            }

        case .currentLocationTapped:
            state.map.locationRequestRevision += 1
            state.map.isCurrentLocationActive = true
            return requestCurrentLocation(.init(
                revision: state.map.locationRequestRevision,
                source: .userAction
            ))

        case .currentLocationResolved(let request, let result):
            guard request.revision == state.map.locationRequestRevision else { return .none }
            if case let .resolved(coordinate) = result {
                state.map.cameraTarget = coordinate
                state.map.cameraRequestID += 1
            }
            if request.source == .userAction {
                state.map.isCurrentLocationActive = false
                if let message = currentLocationFailureMessage(for: result) {
                    RodiAnalytics.track(.courseRegistrationFailed(stage: "current_location"))
                    return .send(.delegate(.showError(message)))
                }
            } else {
                state.map.isCurrentLocationActive = false
            }

        case .viewportChanged(let center, let isUserInitiated):
            guard isUserInitiated else { return .none }
            state.map.isCurrentLocationActive = false
            guard state.map.selectionTarget != nil else { return .none }
            state.map.candidateCoordinate = center

        case .placeSelectionTapped:
            guard let target = state.map.selectionTarget,
                  let coordinate = state.map.candidateCoordinate,
                  !state.map.isAddressResolving
            else {
                return .none
            }
            state.map.addressRequestRevision += 1
            state.map.isAddressResolving = true
            let request = AddressRequest(
                revision: state.map.addressRequestRevision,
                target: target,
                coordinate: coordinate
            )
            return reverseGeocode(request)

        case .reverseGeocodingFinished(let request, let result):
            guard request.revision == state.map.addressRequestRevision,
                  request.target == state.map.selectionTarget
            else {
                return .none
            }
            state.map.isAddressResolving = false
            switch result {
            case .success(let address):
                state.selectedPlaces[request.target] = .init(name: address, coordinate: request.coordinate)
                state.map.hasSelectedCurrentTarget = true
                RodiAnalytics.track(
                    .courseRegistrationPointSelected(
                        inputType: request.target.analyticsInputType,
                        source: "map"
                    )
                )
            case .failure(let error):
                return .send(.delegate(.showError(error.userMessage)))
            }

        case .selectionCompletionTapped:
            guard let target = state.map.selectionTarget,
                  state.map.hasSelectedCurrentTarget,
                  !state.map.isAddressResolving
            else {
                return .none
            }
            switch target {
            case .start:
                beginSelection(.destination, cameraTarget: state.selectedPlaces[.start]?.coordinate, state: &state)
            case .destination, .waypoint:
                state.map.selectionTarget = nil
                state.map.candidateCoordinate = nil
                state.map.hasSelectedCurrentTarget = false
                let points = state.routePoints()
                guard points.count >= 2 else { return .none }
                state.isRouteLoading = true
                state.routeRequestRevision += 1
                return requestInitialRoute(points: points, revision: state.routeRequestRevision)
            }

        case .registrationCompletionTapped:
            guard state.map.selectionTarget == nil,
                  state.selectedPlaces[.start] != nil,
                  state.selectedPlaces[.destination] != nil,
                  !state.isRouteLoading,
                  state.routePath.count >= 2
            else {
                if !state.isRouteLoading {
                    return .send(.delegate(.showError("도로 경로를 불러오지 못했어요. 잠시 후 다시 시도해주세요.")))
                }
                return .none
            }
            RodiAnalytics.track(.courseRegistrationDetailsOpened)
            return .send(.delegate(.openDetails(.init(
                waypoints: state.waypoints,
                selectedPlaces: state.selectedPlaces,
                routePath: state.routePath
            ))))

        case .inputTargetTapped(let target):
            guard !state.map.isAddressResolving else { return .none }
            return .send(.delegate(.openSearch(target)))

        case .searchResultSelected(let target, let result):
            guard let coordinate = result.coordinate else {
                return .send(.delegate(.showError("선택한 장소의 위치를 불러오지 못했어요.")))
            }
            // 검색 중 시작된 위치 요청이 늦게 끝나도, 검색 결과 카메라 이동을 덮어쓰지 않게 한다.
            state.map.locationRequestRevision += 1
            beginSelection(target, cameraTarget: coordinate, state: &state)
            state.map.candidateCoordinate = coordinate
            state.selectedPlaces[target] = .init(
                name: result.address.isEmpty ? result.title : result.address,
                coordinate: coordinate
            )
            state.map.hasSelectedCurrentTarget = true
            state.map.isCurrentLocationActive = false
            state.routePath = []
            RodiAnalytics.track(
                .courseRegistrationPointSelected(
                    inputType: target.analyticsInputType,
                    source: "search"
                )
            )

        case .routePointTapped(let pointID):
            guard let target = state.target(at: pointID),
                  target != state.map.selectionTarget,
                  let original = state.selectedPlaces[target]
            else {
                return .none
            }
            return .send(.delegate(.openPinEdit(target, original)))

        case .pinEditApplied(let target, let replacement, let routePath):
            state.selectedPlaces[target] = replacement
            if let routePath {
                state.routePath = routePath
            }

        case .initialRouteFinished(let revision, let result):
            guard state.routeRequestRevision == revision, state.isRouteLoading else { return .none }
            state.isRouteLoading = false
            switch result {
            case .success(let path):
                state.routePath = path
                RodiAnalytics.track(.courseRegistrationRoutePrepared(waypointCount: state.waypoints.count))
            case .failure:
                RodiAnalytics.track(.courseRegistrationFailed(stage: "route"))
                return .send(.delegate(.showError("도로 경로를 불러오지 못했어요. 잠시 후 다시 시도해주세요.")))
            }

        case .delegate:
            return .none
        }

        return .none
    }

    private func beginSelection(
        _ target: CourseRegistrationInputTarget,
        cameraTarget: RodiCoordinate? = nil,
        state: inout State
    ) {
        state.map.selectionTarget = target
        state.map.candidateCoordinate = nil
        state.map.hasSelectedCurrentTarget = false
        state.map.isAddressResolving = false
        if let cameraTarget {
            state.map.cameraTarget = cameraTarget
            state.map.cameraRequestID += 1
        }
    }

    private func requestCurrentLocation(_ request: LocationRequest) -> Effect<Action> {
        .run { send in
            await send(.currentLocationResolved(request, await mapService.requestCurrentLocation()))
        }
        .cancelTask(id: EffectID.work)
    }

    private func currentLocationFailureMessage(
        for result: CourseRegistrationMapService.CurrentLocationResult
    ) -> String? {
        switch result {
        case .resolved:
            nil
        case .permissionDenied:
            "현재 위치를 확인할 수 없어요. 위치 권한을 허용한 뒤 다시 시도해주세요."
        case .unavailable:
            "현재 위치를 확인할 수 없어요. 위치 서비스와 네트워크 상태를 확인한 뒤 다시 시도해주세요."
        }
    }

    private func reverseGeocode(_ request: AddressRequest) -> Effect<Action> {
        .run { send in
            do {
                await send(.reverseGeocodingFinished(request, .success(try await mapService.reverseGeocode(request.coordinate))))
            } catch is CancellationError {
                return
            } catch let error as CourseRegistrationAddressLookupError {
                await send(.reverseGeocodingFinished(request, .failure(error)))
            } catch {
                await send(.reverseGeocodingFinished(request, .failure(.networkFailed)))
            }
        }
        .cancelTask(id: EffectID.work)
    }

    private func requestInitialRoute(
        points: [RodiRouteOverlayPoint],
        revision: Int
    ) -> Effect<Action> {
        .run { send in
            do {
                await send(.initialRouteFinished(revision, .success(try await directionsService.fetchRoute(points: points))))
            } catch is CancellationError {
                return
            } catch let error as KakaoDirectionsError {
                await send(.initialRouteFinished(revision, .failure(error)))
            } catch {
                await send(.initialRouteFinished(revision, .failure(.networkFailed("unknown"))))
            }
        }
        .cancelTask(id: EffectID.work)
    }
}

struct CourseRegistrationMapState: Equatable {
    var selectionTarget: CourseRegistrationInputTarget?
    var cameraTarget: RodiCoordinate = .seoulCityHall
    var cameraRequestID = 0
    var locationRequestRevision = 0
    var hasRequestedInitialLocation = false
    var addressRequestRevision = 0
    var candidateCoordinate: RodiCoordinate?
    var hasSelectedCurrentTarget = false
    var isAddressResolving = false
    var isCurrentLocationActive = false
}
