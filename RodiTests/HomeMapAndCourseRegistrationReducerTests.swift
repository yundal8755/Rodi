import XCTest
@testable import Rodi

@MainActor
final class HomeMapAndCourseRegistrationReducerTests: XCTestCase {
    // 동기 XCTest의 마지막 release에서 발생한 크래시이므로 async로 감싸지 않는다.
    func testMapServicesReleaseLocationOwnerSynchronously() {
        for _ in 0..<5 {
            weak var releasedLocation: MapLocationService?
            autoreleasepool {
                let location = MapLocationService()
                releasedLocation = location
                let home = MapService(placeRepository: HomeMapPlaceRepositoryStub(), locationService: location)
                let registration = CourseRegistrationMapService(locationService: location)
                withExtendedLifetime((home, registration)) {
                    XCTAssertNotNil(releasedLocation)
                }
            }
            XCTAssertNil(releasedLocation)
        }
    }

    func testInitialViewportLoadsListAndRendersMarkersWithoutGPS() async throws {
        let snapshot = PlaceClusterResult(
            places: [(.course, 1), (.parking, 2)].map { (type: PlaceType, id: Int) in
                .init(id: id, type: type, name: "장소", address: "", latitude: 37, longitude: 127)
            },
            levels: [.init(minLongitudeSpan: 0, maxLongitudeSpan: nil,
                           clusters: [.init(latitude: 37, longitude: 127, count: 3, bounds: clusterViewport)],
                           placeIDs: [1, 2])]
        )
        var listCalls = 0
        let repo = HomeMapPlaceRepositoryStub(onFetchPlaces: { _ in listCalls += 1 }, clusterResult: snapshot)
        let map = HomeMapReducer(dependencies: .init(placeRepository: repo, hasActiveSession: { false }))
        let list = RecommendListBottomSheetReducer(placeRepository: repo, hasActiveSession: { false })
        var state = HomeMapState()
        state.isHomeTabSelected = true
        state.mapLifecycle = .ready
        state.locationState = .requesting // 위치 콜백을 보내지 않는다.
        var sheet = RecommendListBottomSheetReducer.State()
        XCTAssertFalse(sheet.hasEmptyResult)

        XCTAssertEqual(state.initialLoadingStage, .map)
        let completion = map.reduce(&state, with: .cameraMoveFinished(0, viewport: clusterViewport))
        XCTAssertEqual(state.initialLoadingStage, .markers)
        guard case let .run(_, deliverViewport) = completion.caseOf else { return XCTFail("초기 viewport 누락") }
        var listEffect: Effect<RecommendListBottomSheetReducer.Action>?
        await deliverViewport { action in
            if case let .delegate(.viewportChanged(viewport, center, user)) = action {
                listEffect = list.reduce(&sheet, with: .viewportChanged(viewport: viewport, center: center, isUserInitiated: user))
            }
        }
        guard case let .run(_, loadPage) = try XCTUnwrap(listEffect).caseOf else { return XCTFail("페이지 요청 누락") }
        var clusterEffect: Effect<HomeMapReducer.Action>?
        await loadPage { action in
            if case let .delegate(.firstPageRequested(query, revision)) = action {
                clusterEffect = map.reduce(&state, with: .clusterQueryRequested(query, listRevision: revision))
            } else if case .pageLoaded = action {
                _ = list.reduce(&sheet, with: action)
            }
        }
        guard case let .run(_, fetch) = try XCTUnwrap(clusterEffect).caseOf else { return XCTFail("마커 요청 누락") }
        var batches: Effect<HomeMapReducer.Action>?
        await fetch { batches = map.reduce(&state, with: $0) }
        guard case let .run(_, render) = try XCTUnwrap(batches).caseOf else { return XCTFail("첫 배치 누락") }
        XCTAssertEqual(state.initialLoadingStage, .markers)
        await render { _ = map.reduce(&state, with: $0) }
        XCTAssertNil(state.initialLoadingStage)
        XCTAssertNil(state.userLocation)
        XCTAssertEqual(Set(state.markers.map(\.id)), ["course-1", "parking-2", "server-cluster-0-0"])
        XCTAssertEqual(listCalls, 1)
        XCTAssertTrue(sheet.hasEmptyResult) // 빈 목록 응답과 클러스터 응답은 독립적
        _ = list.reduce(&sheet, with: .viewportChanged(viewport: clusterViewport, center: .southKoreaCenter, isUserInitiated: false))
        XCTAssertEqual(sheet.firstPageRevision, 1)
        guard case .none = map.reduce(&state, with: .cameraMoveFinished(0, viewport: clusterViewport)).caseOf else {
            return XCTFail("첫 viewport 재전달")
        }
    }

    func testInitialMarkerOverlayWaitsForFinalCurrentBatchAndDoesNotBlockRetry() {
        let map = HomeMapReducer(dependencies: .init(placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { false }))
        var state = HomeMapState()
        state.mapLifecycle = .ready
        state.hasReceivedInitialViewport = true
        state.markerState = .loaded
        _ = map.reduce(&state, with: .markerRenderBatchUpdated([], generation: 0, isFinal: false))
        _ = map.reduce(&state, with: .markerRenderBatchUpdated([], generation: -1, isFinal: true))
        XCTAssertEqual(state.initialLoadingStage, .markers)
        var failing = state
        _ = map.reduce(&state, with: .markerRenderBatchUpdated([], generation: 0, isFinal: true))
        XCTAssertNil(state.initialLoadingStage) // 정상 0건
        _ = map.reduce(&failing, with: .serviceOutput(.clusterLoadFailed(revision: 0)))
        XCTAssertEqual(failing.markerState, .failed)
        XCTAssertNil(failing.initialLoadingStage)
        _ = map.reduce(&failing, with: .clusterQueryRequested(.init(viewport: clusterViewport, practiceTypes: []), listRevision: 1))
        XCTAssertNil(failing.initialLoadingStage)
    }

    func testFirstUsableFixFollowsOnceUnlessExplorationHasStarted() {
        let map = HomeMapReducer(dependencies: .init(placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { true }))
        let fix = RodiCoordinate(latitude: 37.5, longitude: 127)
        for interaction: HomeMapReducer.Action? in [nil, .userBeganExploring, .searchEntryTapped, .searchPlaceSelected("선택")] {
            var state = HomeMapState()
            state.isHomeTabSelected = true
            state.mapLifecycle = .ready
            state.hasReceivedInitialViewport = true
            state.locationState = .requesting
            if let interaction { _ = map.reduce(&state, with: interaction) }
            _ = map.reduce(&state, with: .serviceOutput(.currentLocationResolved(fix, source: .periodicRefresh)))
            XCTAssertEqual(state.userLocation, fix)
            XCTAssertEqual(state.cameraTarget, interaction == nil ? fix : .southKoreaCenter)
            let requestID = state.cameraRequestID
            state.locationState = .requesting
            _ = map.reduce(&state, with: .serviceOutput(.currentLocationResolved(.southKoreaCenter, source: .periodicRefresh)))
            XCTAssertEqual(state.cameraRequestID, requestID)
            if interaction == nil {
                guard case .none = map.reduce(&state, with: .cameraMoveFinished(requestID, viewport: nil)).caseOf else {
                    return XCTFail("GPS 자동 이동이 전국 결과를 주변 조회로 바꾸면 안 됩니다.")
                }
            }
        }
    }

    func testFirstRevealWaitsForKnownLocationCameraButNotForGPS() {
        let map = HomeMapReducer(dependencies: .init(placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { true }))
        var state = HomeMapState()
        state.isHomeTabSelected = true
        state.mapLifecycle = .ready
        state.locationState = .requesting
        state.hasFinishedInitialMarkerLoad = true
        var withoutFix = state
        let viewport = HomeMapReducer.Action.viewportChanged(center: .southKoreaCenter, zoomLevel: 6, viewport: .nationwide, isUserInitiated: false)
        _ = map.reduce(&state, with: .serviceOutput(.currentLocationResolved(.seoulCityHall, source: .initial)))
        _ = map.reduce(&state, with: viewport)
        XCTAssertEqual(state.cameraFocus, .currentLocation)
        XCTAssertEqual(state.initialLoadingStage, .map)
        _ = map.reduce(&state, with: .cameraMoveFinished(state.cameraRequestID - 1, viewport: nil))
        XCTAssertEqual(state.initialLoadingStage, .map)
        _ = map.reduce(&state, with: .cameraMoveFinished(state.cameraRequestID, viewport: clusterViewport))
        XCTAssertNil(state.initialLoadingStage)

        _ = map.reduce(&withoutFix, with: viewport)
        XCTAssertNil(withoutFix.initialLoadingStage)
        _ = map.reduce(&withoutFix, with: .serviceOutput(.currentLocationResolved(.seoulCityHall, source: .initial)))
        XCTAssertEqual(withoutFix.userLocation, .seoulCityHall)
        XCTAssertEqual(withoutFix.cameraFocus, .koreaOverview)
        XCTAssertNil(withoutFix.initialLoadingStage)
    }

    func testInitialLocationGraceKeepsNationwideMapHiddenUntilCameraSettles() {
        let map = HomeMapReducer(dependencies: .init(placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { true }))
        var state = HomeMapState()
        state.isHomeTabSelected = true
        state.mapLifecycle = .ready
        state.hasReceivedInitialViewport = true
        state.hasFinishedInitialMarkerLoad = true
        state.locationState = .requesting
        state.isWaitingForInitialLocation = true
        XCTAssertEqual(state.initialLoadingStage, .location)

        var timedOut = state
        _ = map.reduce(&timedOut, with: .initialLocationWaitExpired)
        XCTAssertNil(timedOut.initialLoadingStage)
        _ = map.reduce(&timedOut, with: .serviceOutput(.currentLocationResolved(.seoulCityHall, source: .initial)))
        XCTAssertEqual(timedOut.cameraFocus, .koreaOverview)
        XCTAssertEqual(timedOut.userLocation, .seoulCityHall)

        _ = map.reduce(&state, with: .serviceOutput(.currentLocationResolved(.seoulCityHall, source: .initial)))
        XCTAssertEqual(state.cameraFocus, .currentLocation)
        _ = map.reduce(&state, with: .initialLocationWaitExpired)
        XCTAssertEqual(state.initialLoadingStage, .map)
        _ = map.reduce(&state, with: .cameraMoveFinished(state.cameraRequestID, viewport: clusterViewport))
        XCTAssertNil(state.initialLoadingStage)
    }

    func testGPSAndZoomKeepNationwideQueryUntilExplicitResearch() {
        let list = RecommendListBottomSheetReducer(placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { true })
        var state = RecommendListBottomSheetReducer.State()
        _ = list.reduce(&state, with: .initialNationwideRequested)
        let old = state.requestRevision
        _ = list.reduce(&state, with: .viewportChanged(viewport: .nationwide, center: .southKoreaCenter, isUserInitiated: false))
        _ = list.reduce(&state, with: .viewportChanged(viewport: clusterViewport, center: .seoulCityHall, isUserInitiated: true))
        XCTAssertEqual(state.requestedViewport, .nationwide)
        XCTAssertEqual(state.requestRevision, old)
        XCTAssertTrue(state.isInitialLoading)
        _ = list.reduce(&state, with: .pageLoaded(page: .init(items: [], hasNext: true, nextCursor: "next", totalCount: 21),
                                                  viewport: .nationwide, revision: old, isAppending: false, isManualResearch: false))
        XCTAssertTrue(state.needsResearch)
        _ = list.reduce(&state, with: .loadNextPage)
        XCTAssertTrue(state.isNextPageLoading)
        _ = list.reduce(&state, with: .pageLoaded(page: .init(items: [], hasNext: false, nextCursor: nil, totalCount: 21),
                                                  viewport: .nationwide, revision: state.requestRevision, isAppending: true, isManualResearch: false))
        _ = list.reduce(&state, with: .reloadCurrentViewport(origin: nil))
        XCTAssertEqual(state.requestedViewport, clusterViewport)
    }

    func testMapEngineRetryDoesNotClearPlaceDataOrTreatGPSFailureAsEngineFailure() {
        let map = HomeMapReducer(dependencies: .init(placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { false }))
        var state = HomeMapState()
        state.mapLifecycle = .ready
        state.markerState = .loaded
        state.locationState = .requesting
        _ = map.reduce(&state, with: .serviceOutput(.currentLocationPermissionDenied(source: .initial, authorizationState: .denied)))
        XCTAssertEqual(state.mapLifecycle, .ready)
        _ = map.reduce(&state, with: .engineFailed)
        XCTAssertEqual(state.mapLifecycle, .failed)
        _ = map.reduce(&state, with: .engineRetryRequested)
        XCTAssertEqual(state.mapLifecycle, .activating)
        XCTAssertEqual(state.markerState, .loaded)
    }

    func testNationwideBrowseWaitsForMatchingCameraCompletion() {
        let reducer = HomeMapReducer(dependencies: .init(
            placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { true }
        ))
        var state = HomeMapState()
        let location = RodiCoordinate(latitude: 37.5, longitude: 126.5)
        state.userLocation = location
        _ = reducer.reduce(&state, with: .nationwideBrowseRequested)
        let requestID = state.cameraRequestID
        XCTAssertEqual(state.cameraFocus, .koreaOverview)
        XCTAssertEqual(state.userLocation, location)
        _ = reducer.reduce(&state, with: .viewportChanged(
            center: location, zoomLevel: 12, viewport: clusterViewport, isUserInitiated: false
        ))
        _ = reducer.reduce(&state, with: .cameraMoveFinished(requestID - 1, viewport: clusterViewport))
        XCTAssertEqual(state.pendingRegionCameraRequestID, requestID)
        let nationwide = PlaceViewport(southWestLatitude: 32, southWestLongitude: 124,
                                       northEastLatitude: 39, northEastLongitude: 132)
        let effect = reducer.reduce(&state, with: .cameraMoveFinished(requestID, viewport: nationwide))
        guard case .send(.delegate(.reloadAfterRegionViewport(let viewport, let origin))) = effect.caseOf else {
            return XCTFail("전국 카메라 이동 완료 후 조회가 필요합니다.")
        }
        XCTAssertEqual(viewport, nationwide)
        XCTAssertEqual(origin, .southKoreaCenter)
        XCTAssertNil(state.pendingRegionCameraRequestID)
    }

    func testEmptyRecommendationRetainsFilterActions() {
        let reducer = RecommendListBottomSheetReducer(
            placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { true }
        )
        var state = RecommendListBottomSheetReducer.State()
        XCTAssertTrue(state.items.isEmpty)
        guard case .send(.delegate(.presentFilter)) = reducer.reduce(&state, with: .openFilter).caseOf else {
            return XCTFail("빈 목록에서도 필터를 열 수 있어야 합니다.")
        }
        guard case .send(.delegate(.resetFilter)) = reducer.reduce(&state, with: .resetFilter).caseOf else {
            return XCTFail("빈 목록에서 필터 초기화 의도를 전달해야 합니다.")
        }
    }

    func testFilterResetResearchesLatestViewportForBothMarkersAndList() async throws {
        let items: [PlaceListItem] = [PlaceType.course, .parking].enumerated().map { index, type in
            .init(id: index + 1, type: type, name: "테스트 장소", address: "테스트 주소",
                  latitude: 37.5, longitude: 126.5, distanceFromMeMeters: nil, practiceTypes: [],
                  summary: nil, distanceMeters: nil, capacity: nil, openTime: nil, isDeleted: false)
        }
        var listQuery: PlaceListQuery?
        let reducer = RecommendListBottomSheetReducer(
            placeRepository: HomeMapPlaceRepositoryStub(
                listPage: .init(items: items, hasNext: false, nextCursor: nil, totalCount: items.count),
                onFetchPlaces: { listQuery = $0 }
            ),
            hasActiveSession: { true }
        )
        var state = RecommendListBottomSheetReducer.State()
        state.latestViewport = clusterViewport
        state.latestViewportCenter = .init(latitude: 37.5, longitude: 126.5)
        state.requestOrigin = .init(latitude: 35, longitude: 129)
        state.practiceTypes = []
        state.requestedPracticeTypes = [.merging]
        state.isInitialLoading = true
        state.isRegionSearchResult = true
        state.nextCursor = "old-cursor"

        let effect = reducer.reduce(&state, with: .reloadAfterFilter)
        XCTAssertTrue(state.isManualResearchLoading)
        XCTAssertFalse(state.isRegionSearchResult)
        XCTAssertTrue(state.requestedPracticeTypes.isEmpty)
        XCTAssertNil(state.nextCursor)
        guard case let .run(_, task) = effect.caseOf else { return XCTFail("재검색 요청이 필요합니다.") }
        var clusterQuery: PlaceClusterQuery?
        var response: RecommendListBottomSheetReducer.Action?
        await task { action in
            if case let .delegate(.firstPageRequested(query, _)) = action { clusterQuery = query }
            if case .pageLoaded = action { response = action }
        }
        XCTAssertEqual(clusterQuery, .init(viewport: clusterViewport, practiceTypes: []))
        XCTAssertEqual(listQuery?.viewport, clusterViewport)
        XCTAssertEqual(listQuery?.practiceTypes, [])
        XCTAssertEqual(listQuery?.currentLatitude, 37.5)
        XCTAssertNil(listQuery?.cursor)
        _ = reducer.reduce(&state, with: try XCTUnwrap(response))
        XCTAssertEqual(state.items, items)

        let mapReducer = HomeMapReducer(dependencies: .init(
            placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { true }
        ))
        var mapState = HomeMapState()
        _ = mapReducer.reduce(&mapState, with: .clusterQueryRequested(
            try XCTUnwrap(clusterQuery), listRevision: state.firstPageRevision
        ))
        let clusterResult = PlaceClusterResult(
            places: items.map { .init(id: $0.id, type: $0.type, name: $0.name, address: $0.address,
                                     latitude: $0.latitude, longitude: $0.longitude) },
            levels: [.init(minLongitudeSpan: 0, maxLongitudeSpan: nil, clusters: [], placeIDs: items.map(\.id))]
        )
        _ = mapReducer.reduce(&mapState, with: .serviceOutput(.clustersLoaded(clusterResult, revision: mapState.clusterRequestRevision)))
        XCTAssertEqual(Set(mapState.markers.map(\.id)), ["course-1", "parking-2"])

        _ = reducer.reduce(&state, with: .pageLoaded(
            page: .init(items: [], hasNext: false, nextCursor: nil, totalCount: 0),
            viewport: clusterViewport, revision: state.requestRevision - 1,
            isAppending: false, isManualResearch: false
        ))
        XCTAssertEqual(state.items, items)
    }

    private let clusterViewport = PlaceViewport(
        southWestLatitude: 37, southWestLongitude: 126,
        northEastLatitude: 38, northEastLongitude: 127
    )

    func testClusterAndSortTagRequestContracts() throws {
        let filtered = PlaceAPI.clusters(PlaceMapper.clusterQuery(from: .init(
            viewport: clusterViewport, practiceTypes: [.parking]
        )))
        XCTAssertEqual(filtered.path, "/api/v1/places/clusters")
        XCTAssertFalse(filtered.requiresAuthentication)
        XCTAssertEqual(filtered.parameters?["practiceTypes"] as? String, "PARKING")
        let unfiltered = PlaceAPI.clusters(PlaceMapper.clusterQuery(from: .init(
            viewport: clusterViewport, practiceTypes: []
        )))
        XCTAssertNil(unfiltered.parameters?["practiceTypes"])

        for tags: [PlacePracticeType] in [[.parking], []] {
            let api = MemberAPI.updateSortTags(MemberMapper.sortTagsRequest(from: tags))
            XCTAssertEqual(api.path, "/api/v1/members/me/sort-tags")
            XCTAssertEqual(api.method.rawValue, "PUT")
            XCTAssertTrue(api.requiresAuthentication)
            let json = try JSONDecoder().decode([String: [String]].self, from: XCTUnwrap(api.body))
            XCTAssertEqual(json, ["sortTags": tags.map(\.rawValue)])
        }
    }

    func testServerMarkerLevelsBoundsAndStaleResponses() {
        let reducer = HomeMapReducer(dependencies: .init(
            placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { false }
        ))
        var state = HomeMapState()
        let result = PlaceClusterResult(
            places: [.init(id: 7, type: .parking, name: "주차장", address: "서울", latitude: 37.5, longitude: 126.5)],
            levels: [
                .init(minLongitudeSpan: 0, maxLongitudeSpan: 1, clusters: [], placeIDs: [7]),
                .init(minLongitudeSpan: 1, maxLongitudeSpan: nil, clusters: [
                    .init(latitude: 37.5, longitude: 126.5, count: 2, bounds: clusterViewport)
                ], placeIDs: [])
            ]
        )
        XCTAssertEqual(result.levelIndex(for: 0.999), 0)
        XCTAssertEqual(result.levelIndex(for: 1), 1)
        XCTAssertEqual(result.levelIndex(for: 100), 1)
        let query = PlaceClusterQuery(viewport: clusterViewport, practiceTypes: [.parking])
        _ = reducer.reduce(&state, with: .clusterQueryRequested(query, listRevision: 1))
        _ = reducer.reduce(&state, with: .clusterQueryRequested(query, listRevision: 2))
        _ = reducer.reduce(&state, with: .serviceOutput(.clustersLoaded(result, revision: 1)))
        XCTAssertTrue(state.markers.isEmpty)
        _ = reducer.reduce(&state, with: .serviceOutput(.clustersLoaded(result, revision: 2)))
        XCTAssertEqual(state.markers.map(\.kind), [.cluster])
        guard let markerID = state.markers.first?.id else { return XCTFail("서버 클러스터가 필요합니다.") }
        _ = reducer.reduce(&state, with: .markerTapped(markerID))
        guard case let .cluster(coordinates) = state.cameraFocus else { return XCTFail("범위 맞춤이 필요합니다.") }
        XCTAssertEqual(coordinates, [
            .init(latitude: 37, longitude: 126), .init(latitude: 38, longitude: 127)
        ])
        let closer = PlaceViewport(southWestLatitude: 37.4, southWestLongitude: 126.4,
                                   northEastLatitude: 37.6, northEastLongitude: 126.6)
        _ = reducer.reduce(&state, with: .viewportChanged(center: coordinates[0], zoomLevel: 12,
                                                         viewport: closer, isUserInitiated: true))
        XCTAssertEqual(state.clusterRequestRevision, 2)
        XCTAssertEqual(state.markers.map(\.id), ["parking-7"])
        _ = reducer.reduce(&state, with: .clusterQueryRequested(query, listRevision: 3))
        _ = reducer.reduce(&state, with: .serviceOutput(.clusterLoadFailed(revision: 3)))
        XCTAssertEqual(state.markers.map(\.id), ["parking-7"])
        XCTAssertTrue(state.isResearchButtonVisible)
    }

    func testFirstValidViewportUsesSameFilterForMapAndList() async {
        let reducer = RecommendListBottomSheetReducer(
            placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { false }
        )
        var state = RecommendListBottomSheetReducer.State()
        state.practiceTypes = [.parking]
        let center = RodiCoordinate(latitude: 37.5, longitude: 126.5)
        let invalid = PlaceViewport(southWestLatitude: 38, southWestLongitude: 126,
                                    northEastLatitude: 37, northEastLongitude: 127)
        _ = reducer.reduce(&state, with: .viewportChanged(viewport: invalid, center: center, isUserInitiated: false))
        XCTAssertEqual(state.requestRevision, 0)
        let effect = reducer.reduce(&state, with: .viewportChanged(
            viewport: clusterViewport, center: center, isUserInitiated: false
        ))
        XCTAssertEqual(state.requestedPracticeTypes, [.parking])
        guard case let .run(_, task) = effect.caseOf else { return XCTFail("첫 페이지 요청이 필요합니다.") }
        var query: PlaceClusterQuery?
        await task { action in
            if case let .delegate(.firstPageRequested(snapshot, _)) = action { query = snapshot }
        }
        XCTAssertEqual(query, .init(viewport: .nationwide, practiceTypes: [.parking]))
    }

    func testRegionReloadUsesSettledViewportRatherThanPreviousViewport() async {
        let reducer = RecommendListBottomSheetReducer(
            placeRepository: HomeMapPlaceRepositoryStub(), hasActiveSession: { false }
        )
        var state = RecommendListBottomSheetReducer.State()
        let origin = RodiCoordinate(latitude: 37.5, longitude: 126.5)
        state.latestViewport = .init(southWestLatitude: 34, southWestLongitude: 128,
                                     northEastLatitude: 35, northEastLongitude: 129)
        _ = reducer.reduce(&state, with: .regionViewportReloadStarted(origin: origin))
        XCTAssertEqual(state.firstPageRevision, 0)
        let effect = reducer.reduce(&state, with: .reloadAfterRegionViewport(
            viewport: clusterViewport, origin: origin
        ))
        guard case let .run(_, task) = effect.caseOf else { return XCTFail("이동 완료 후 조회가 필요합니다.") }
        var query: PlaceClusterQuery?
        await task { action in
            if case let .delegate(.firstPageRequested(snapshot, _)) = action { query = snapshot }
        }
        XCTAssertEqual(query?.viewport, clusterViewport)
        guard case .none = reducer.reduce(&state, with: .reloadAfterRegionViewport(
            viewport: clusterViewport, origin: origin
        )).caseOf else { return XCTFail("같은 이동 완료 신호를 중복 처리하면 안 됩니다.") }
    }

    func testUserViewportChangeDuringInitialLoadingShowsResearchButtonBeforeCancelling() async {
        let reducer = RecommendListBottomSheetReducer(
            placeRepository: HomeMapPlaceRepositoryStub(),
            hasActiveSession: { false }
        )
        var state = RecommendListBottomSheetReducer.State()
        state.activeViewport = PlaceViewport(
            southWestLatitude: 37.4,
            southWestLongitude: 126.9,
            northEastLatitude: 37.6,
            northEastLongitude: 127.1
        )
        state.requestRevision = 1
        state.isInitialLoading = true

        let effect = reducer.reduce(
            &state,
            with: .viewportChanged(
                viewport: PlaceViewport(
                    southWestLatitude: 37.5,
                    southWestLongitude: 127.0,
                    northEastLatitude: 37.7,
                    northEastLongitude: 127.2
                ),
                center: .init(latitude: 37.6, longitude: 127.1),
                isUserInitiated: true
            )
        )

        XCTAssertTrue(state.needsResearch)
        XCTAssertFalse(state.isInitialLoading)
        guard case let .run(_, task) = effect.caseOf else {
            return XCTFail("로딩 중 지도 이동은 버튼 상태 전달 뒤 기존 목록 요청을 취소해야 합니다.")
        }

        var emittedActions: [RecommendListBottomSheetReducer.Action] = []
        await task { action in
            emittedActions.append(action)
        }

        XCTAssertEqual(emittedActions.count, 2)
        guard emittedActions.count == 2 else { return }
        guard case let .delegate(.displayStateChanged(_, showsResearchButton)) = emittedActions[0] else {
            return XCTFail("먼저 재검색 버튼 표시 상태를 전달해야 합니다.")
        }
        XCTAssertTrue(showsResearchButton)
        guard case .placeListLoadingCancellationRequested = emittedActions[1] else {
            return XCTFail("표시 상태 전달 뒤 기존 목록 요청을 취소해야 합니다.")
        }
    }

    func testGuestPlaceMarkerTapRequestsAuthenticationWithoutChangingMapSelection() {
        let reducer = HomeMapReducer(
            dependencies: .init(
                placeRepository: HomeMapPlaceRepositoryStub(),
                hasActiveSession: { false }
            )
        )
        let place = PlaceCoordinate(
            id: 1,
            type: .course,
            name: "테스트 코스",
            address: "서울",
            latitude: 37.5,
            longitude: 127.0
        )
        let item = RodiCourseItem(placeCoordinate: place)
        let marker = try! XCTUnwrap(item.mapMarker)
        var state = HomeMapState()
        state.markers = [marker]
        state.cameraTarget = .southKoreaCenter
        state.cameraFocus = .koreaOverview
        state.isCurrentLocationButtonActive = true

        let effect = reducer.reduce(&state, with: .markerTapped(marker.id))

        guard case let .send(action) = effect.caseOf,
              case .delegate(.requestAuthentication) = action
        else {
            return XCTFail("비로그인 단일 마커 탭은 인증 요청만 전달해야 합니다.")
        }
        XCTAssertEqual(state.cameraTarget, .southKoreaCenter)
        XCTAssertEqual(state.cameraFocus, .koreaOverview)
        XCTAssertNil(state.selectedMarkerID)
        XCTAssertTrue(state.isCurrentLocationButtonActive)
    }

    func testRegistrationDefaultsToFirstCategoryAndKeepsItClean() {
        let reducer = CourseRegistrationDetailsReducer(courseRepository: CourseRepositoryStub())
        var state = CourseRegistrationDetailsReducer.State()
        let requestID = UUID()
        state.activeRequestID = requestID

        _ = reducer.reduce(&state, with: .formLoaded(requestID, .success(registrationForm)))

        XCTAssertEqual(state.draft.selectedCategoryCodes, ["BASIC"])
        XCTAssertTrue(state.draft.selectedPracticeTypeCodes.isEmpty)
        XCTAssertFalse(state.isDirty)
    }

    func testRegistrationCategorySwitchKeepsPreviousPracticeTypes() {
        let reducer = CourseRegistrationDetailsReducer(courseRepository: CourseRepositoryStub())
        var state = CourseRegistrationDetailsReducer.State()
        let requestID = UUID()
        state.activeRequestID = requestID
        _ = reducer.reduce(&state, with: .formLoaded(requestID, .success(registrationForm)))
        state.draft.selectedPracticeTypeCodes = ["STRAIGHT"]

        _ = reducer.reduce(&state, with: .categoryTapped("URBAN"))

        XCTAssertEqual(state.draft.selectedCategoryCodes, ["URBAN"])
        XCTAssertEqual(state.draft.selectedPracticeTypeCodes, ["STRAIGHT"])
    }

    func testHomeFilterKeepsTypesAcrossCategoryChanges() {
        var selection = HomePracticeFilterSelection()

        selection.selectCategory(.basicDriving)
        selection.toggleType(.straight)
        selection.selectCategory(.urbanBasics)
        selection.toggleType(.intersection)
        selection.selectCategory(.trafficFlow)
        selection.toggleType(.merging)
        selection.selectCategory(.urbanBasics)

        XCTAssertEqual(selection.category, .urbanBasics)
        XCTAssertEqual(selection.filterTags, [.straight, .intersection, .merging])
        XCTAssertTrue(selection.selectedTypes.contains(.intersection))
    }

    func testHomeFilterTappingActiveCategoryHidesPracticeTypes() {
        var selection = HomePracticeFilterSelection()

        selection.selectCategory(.basicDriving)
        selection.toggleType(.straight)
        selection.selectCategory(.basicDriving)

        XCTAssertNil(selection.category)
        XCTAssertFalse(selection.showsPracticeTypeOptions)
        XCTAssertEqual(selection.filterTags, [.straight])
    }

    func testHomeFilterParkingAddsAndRemovesParkingTagWithoutPracticeTypes() {
        var selection = HomePracticeFilterSelection()

        selection.selectCategory(.parking)

        XCTAssertEqual(selection.category, .parking)
        XCTAssertFalse(selection.showsPracticeTypeOptions)
        XCTAssertEqual(selection.filterTags, [.parking])

        selection.selectCategory(.parking)

        XCTAssertNil(selection.category)
        XCTAssertTrue(selection.filterTags.isEmpty)
    }

    func testPinEditingCompletionWithoutConfirmedPlaceDoesNothing() {
        let reducer = CourseRegistrationPinEditingReducer()
        let place = CourseRegistrationSelectedPlace(
            name: "기존 출발지",
            coordinate: .init(latitude: 37.5, longitude: 127.0)
        )
        var state = CourseRegistrationPinEditingReducer.State(target: .start, originalPlace: place)

        let effect = reducer.reduce(&state, with: .completionTapped([]))

        guard case .none = effect.caseOf else {
            return XCTFail("확정 전 완료 요청은 종료나 저장을 시작하면 안 됩니다.")
        }
        XCTAssertFalse(state.isSaving)
        XCTAssertNil(state.temporaryPlace)
    }
}

private extension HomeMapAndCourseRegistrationReducerTests {
    var registrationForm: CourseRegistrationForm {
        .init(
            maxWaypoints: 3,
            sections: .init(
                basicInfo: "기본 정보",
                practiceCategory: "연습유형 카테고리",
                practiceType: "연습유형",
                caution: "주의사항",
                description: "한줄 소개"
            ),
            practiceType: .init(
                maxSelect: 3,
                maxSelectExceededMessage: "최대 선택 수를 초과했어요.",
                categories: [
                    .init(
                        code: "BASIC",
                        label: "기초 주행",
                        order: 1,
                        practiceTypes: [
                            .init(code: "STRAIGHT", label: "직선주행", order: 1),
                            .init(code: "TURN", label: "좌우회전", order: 2)
                        ]
                    ),
                    .init(
                        code: "URBAN",
                        label: "도심 기본",
                        order: 2,
                        practiceTypes: [
                            .init(code: "INTERSECTION", label: "교차로", order: 1),
                            .init(code: "UTURN", label: "유턴", order: 2)
                        ]
                    )
                ]
            ),
            inputs: .init(
                caution: .init(required: false, minLength: nil, maxLength: 100, placeholder: "주의사항"),
                description: .init(required: true, minLength: 10, maxLength: 30, placeholder: "한줄 소개")
            )
        )
    }
}

private struct HomeMapPlaceRepositoryStub: PlaceRepository {
    var listPage = PlaceCursorPage(items: [], hasNext: false, nextCursor: nil, totalCount: 0)
    var onFetchPlaces: ((PlaceListQuery) -> Void)?
    var clusterResult = PlaceClusterResult(places: [], levels: [])
    func fetchClusters(query: PlaceClusterQuery) async throws(NetworkError) -> PlaceClusterResult {
        clusterResult
    }
    func fetchCoordinates() async throws(NetworkError) -> [PlaceCoordinate] { [] }
    func fetchPlaces(query: PlaceListQuery, access: PlaceListAccess) async throws(NetworkError) -> PlaceCursorPage {
        onFetchPlaces?(query)
        return listPage
    }
    func searchPlaces(query: PlaceSearchQuery) async throws(NetworkError) -> PlaceCursorPage { .init(items: [], hasNext: false, nextCursor: nil, totalCount: 0) }
    func fetchRelatedSearches(query: PlaceRelatedSearchQuery) async throws(NetworkError) -> PlaceRelatedSearchResult { .init(regions: [], places: .init(items: [], hasNext: false, nextCursor: nil, totalCount: 0)) }
    func fetchBookmarkedPlaces(query: PlaceBookmarkListQuery) async throws(NetworkError) -> PlaceCursorPage { .init(items: [], hasNext: false, nextCursor: nil, totalCount: 0) }
    func fetchPlaceDetail(id: Int) async throws(NetworkError) -> PlaceDetail { fatalError() }
    func bookmark(placeID: Int) async throws(NetworkError) {}
    func unbookmark(placeID: Int) async throws(NetworkError) {}
}

private struct CourseRepositoryStub: CourseRepository {
    func fetchRegistrationForm() async throws(NetworkError) -> CourseRegistrationForm { fatalError() }
    func register(_ submission: CourseRegistrationSubmission) async throws(NetworkError) -> CourseRegistrationResult { fatalError() }
    func fetchMyCourses(query: MyCourseQuery) async throws(NetworkError) -> MyCoursePage { fatalError() }
    func deleteMyCourse(courseID: Int64) async throws(NetworkError) {}
    func fetchReportForm() async throws(NetworkError) -> CourseReportForm { throw .decodingFail }
    func report(courseID: Int64, submission: CourseReportSubmission) async throws(NetworkError) { throw .encodingFail }
}
