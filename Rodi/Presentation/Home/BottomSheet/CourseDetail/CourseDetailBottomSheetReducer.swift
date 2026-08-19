import Foundation

struct CourseDetailBottomSheetReducer: Reducer {
    enum Presentation: Equatable { case sheet, expandedDetail }

    struct State {
        var detail: PlaceDetail?
        var routeOverlay: RodiRouteOverlay?
        var isRouteLoading = false
        var routeStatusMessage: String?
        var isBookmarkUpdating = false
        var presentation: Presentation = .sheet
        var isRouteTimelineExpanded = false
        var reviews = CourseReviewReducer.State()
        var routeGuidancePresentation: RouteGuidanceFlowPresentation?
        var routeGuidanceRequest: RouteGuidanceFlowRequest?
        var routeGuidanceRequestID = 0
        var isRouteGuidanceLaunching = false
    }

    enum Action {
        case present(PlaceDetail, source: String)
        case dismiss
        case reset
        case cancelRoadRouteLoading
        case toggleBookmark
        case bookmarkUpdated(placeID: Int, isBookmarked: Bool, source: String)
        case bookmarkFailed(previousDetail: PlaceDetail, message: String)
        case roadRouteLoaded(courseID: Int, path: [RodiCoordinate])
        case roadRouteFailed(courseID: Int, message: String?)
        case routeGuidanceTapped(userLocation: RodiCoordinate?, hasLocationPermission: Bool)
        case routeGuidanceAppSelected(RouteGuidanceApp, rememberSelection: Bool)
        case routeGuidanceInstallSelected(RouteGuidanceApp)
        case routeGuidanceActiveMeasurementEnded
        case routeGuidanceRouteOnlySelected
        case routeGuidanceSettingsReturned
        case routeGuidanceDismissed
        case routeGuidanceTrackingPrepared(
            RouteGuidanceTrackingPreparation,
            request: RouteGuidanceFlowRequest,
            requestID: Int
        )
        case routeGuidanceWillOpen(
            request: RouteGuidanceFlowRequest,
            mode: PracticeMeasurementMode,
            measurementID: UUID,
            requestID: Int
        )
        case routeGuidanceOpenFinished(
            RouteGuidanceResult,
            request: RouteGuidanceFlowRequest,
            measurementID: UUID,
            cancelTrackingOnFailure: Bool,
            requestID: Int
        )
        case routeGuidanceInstallFinished(RouteGuidanceResult, requestID: Int)
        case activeMeasurementEnded
        case expandRequested
        case collapseRequested
        case routeTimelineToggled
        case reviews(CourseReviewReducer.Action)
        case delegate(Delegate)
    }
    enum Delegate { case dismissed, routeOverlayChanged(RodiRouteOverlay?), requestAuthentication, showSnackbar(String), reviewWritingRequested(ReviewWriteRequest), reviewEditingRequested(Int) }
    private let placeRepository: PlaceRepository
    private let practiceMeasurementStore: PracticeMeasurementStoring
    private let practiceTrackingService: PracticeTrackingService
    private let hasActiveSession: () -> Bool
    private let directionsService: KakaoDirectionsService
    private let routeGuidanceFlowService: RouteGuidanceFlowService
    private let reviewsReducer: CourseReviewReducer
    private let onDelegate: (Delegate) -> Void

    init(
        placeRepository: PlaceRepository,
        memberRepository: MemberRepository,
        practiceRepository: PracticeRepository,
        reviewRepository: ReviewRepository,
        practiceMeasurementStore: PracticeMeasurementStoring,
        practiceTrackingService: PracticeTrackingService,
        hasActiveSession: @escaping () -> Bool,
        directionsService: KakaoDirectionsService = .init(),
        onDelegate: @escaping (Delegate) -> Void = { _ in }
    ) {
        self.placeRepository = placeRepository
        self.practiceMeasurementStore = practiceMeasurementStore
        self.practiceTrackingService = practiceTrackingService
        self.hasActiveSession = hasActiveSession
        self.directionsService = directionsService
        routeGuidanceFlowService = .init(
            memberRepository: memberRepository,
            practiceTrackingService: practiceTrackingService,
            directionsService: directionsService
        )
        self.onDelegate = onDelegate
        reviewsReducer = .init(repository: reviewRepository, memberRepository: memberRepository, hasActiveSession: hasActiveSession)
    }
}

// MARK: - Reduce
extension CourseDetailBottomSheetReducer {
    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .present(let detail, _):
            guard detail.type == .course else { return .none }
            state = .init(detail: detail)
            RodiAnalytics.track(.placeDetailOpened(source: "home", placeType: detail.type.rawValue))
            return configureRoute(for: .init(placeDetail: detail), state: &state)
        case .dismiss:
            guard state.detail != nil else { return .none }
            state = .init()
            return .run { send in
                await send(.cancelRoadRouteLoading)
                await send(.routeGuidanceDismissed)
                await send(.reviews(.report(.reset)))
                await send(.reviews(.block(.reset)))
                await send(.reviews(.reset))
                await send(.delegate(.dismissed))
            }
        case .reset:
            state = .init()
            return .run { send in
                await send(.cancelRoadRouteLoading)
                await send(.routeGuidanceDismissed)
                await send(.reviews(.report(.reset)))
                await send(.reviews(.block(.reset)))
                await send(.reviews(.reset))
            }
        case .cancelRoadRouteLoading: return .cancel(id: BottomSheetEffectID.routeLoading)
        case .toggleBookmark:
            guard let detail = state.detail, !state.isBookmarkUpdating else { return .none }
            guard hasActiveSession() else { return .send(.delegate(.requestAuthentication)) }
            let previous = detail; let bookmarked = !detail.isBookmarked
            state.detail = detail.updatingBookmark(isBookmarked: bookmarked); state.isBookmarkUpdating = true
            return bookmarkEffect(placeID: detail.id, isBookmarked: bookmarked, previous: previous)
        case let .bookmarkUpdated(placeID, bookmarked, source):
            guard state.detail?.id == placeID else { return .none }
            state.detail = state.detail?.updatingBookmark(isBookmarked: bookmarked); state.isBookmarkUpdating = false
            RodiAnalytics.track(.bookmarkUpdated(isBookmarked: bookmarked, source: source, placeType: PlaceType.course.rawValue))
            return .none
        case .bookmarkFailed(let previous, let message):
            guard state.detail?.id == previous.id else { return .none }; state.detail = previous; state.isBookmarkUpdating = false
            return .send(.delegate(.showSnackbar(message)))
        case .roadRouteLoaded(let courseID, let path):
            guard let overlay = state.routeOverlay, overlay.courseID == courseID else { return .none }
            state.routeOverlay = .init(courseID: courseID, points: overlay.points, path: path, isRoadRoute: true); state.isRouteLoading = false; state.routeStatusMessage = nil
            return .send(.delegate(.routeOverlayChanged(state.routeOverlay)))
        case .roadRouteFailed(let courseID, let message):
            guard state.routeOverlay?.courseID == courseID else { return .none }; state.isRouteLoading = false; state.routeStatusMessage = message
            return .send(.delegate(.routeOverlayChanged(state.routeOverlay)))
        case .routeGuidanceTapped(let userLocation, let hasLocationPermission):
            return startRouteGuidance(
                userLocation: userLocation,
                hasLocationPermission: hasLocationPermission,
                state: &state
            )
        case .routeGuidanceAppSelected(let app, let rememberSelection):
            guard let request = state.routeGuidanceRequest else { return .none }
            if rememberSelection {
                routeGuidanceFlowService.savePreferredApp(app)
            }
            return continueRouteGuidance(
                .init(app: app, detail: request.detail, userLocation: request.userLocation),
                state: &state
            )
        case .routeGuidanceInstallSelected(let app):
            state.routeGuidancePresentation = nil
            state.routeGuidanceRequestID += 1
            let requestID = state.routeGuidanceRequestID
            return openInstallEffect(app: app, requestID: requestID)
        case .routeGuidanceActiveMeasurementEnded:
            guard let request = state.routeGuidanceRequest else { return .none }
            routeGuidanceFlowService.cancelActiveMeasurement()
            state.routeGuidancePresentation = nil
            state.routeGuidanceRequest = nil
            return .run { send in
                await send(.activeMeasurementEnded)
                await send(.routeGuidanceTapped(userLocation: request.userLocation, hasLocationPermission: true))
            }
        case .routeGuidanceRouteOnlySelected:
            guard let request = state.routeGuidanceRequest else { return .none }
            state.routeGuidancePresentation = nil
            return openRouteEffect(
                request: request,
                mode: .routeOnly,
                measurementID: UUID(),
                cancelTrackingOnFailure: false,
                state: &state
            )
        case .routeGuidanceSettingsReturned:
            guard let request = state.routeGuidanceRequest else { return .none }
            state.routeGuidancePresentation = nil
            if routeGuidanceFlowService.areLiveActivitiesEnabled {
                return continueRouteGuidance(request, state: &state)
            }
            return openRouteEffect(
                request: request,
                mode: .routeOnly,
                measurementID: UUID(),
                cancelTrackingOnFailure: false,
                state: &state
            )
        case .routeGuidanceDismissed:
            state.routeGuidancePresentation = nil
            state.routeGuidanceRequest = nil
            state.isRouteGuidanceLaunching = false
            return .cancel(id: BottomSheetEffectID.courseRouteGuidance)
        case .routeGuidanceTrackingPrepared(let preparation, let request, let requestID):
            guard requestID == state.routeGuidanceRequestID,
                  state.detail?.id == request.detail.id else { return .none }
            state.isRouteGuidanceLaunching = false
            switch preparation {
            case .started(let measurementID):
                return openRouteEffect(
                    request: request,
                    mode: .gpsTracking,
                    measurementID: measurementID,
                    cancelTrackingOnFailure: true,
                    state: &state
                )
            case .authorizationRequested:
                return finishRouteGuidance(
                    "위치 권한을 허용한 뒤 다시 연습하러 가기를 눌러주세요.",
                    state: &state
                )
            case .reducedAccuracyRequested:
                return openRouteOnlyWithMessage(
                    request,
                    message: "정확한 위치를 허용하면 다음 길안내부터 연습 기록을 시작할 수 있어요.",
                    state: &state
                )
            case .unavailable(let message):
                return openRouteOnlyWithMessage(request, message: message, state: &state)
            }
        case .routeGuidanceWillOpen(let request, let mode, let measurementID, let requestID):
            guard requestID == state.routeGuidanceRequestID,
                  state.detail?.id == request.detail.id else { return .none }
            let measurement = PracticeMeasurement(
                id: measurementID,
                placeID: request.detail.id,
                placeName: request.detail.name,
                mode: mode,
                externalHandoffAt: .now,
                status: mode == .gpsTracking ? .tracking : .awaitingReturn
            )
            practiceMeasurementStore.save(measurement)
            practiceTrackingService.synchronizeCompletedSessionCertificationIfNeeded()
            return .none
        case .routeGuidanceOpenFinished(let result, let request, let measurementID, let cancelTrackingOnFailure, let requestID):
            guard requestID == state.routeGuidanceRequestID,
                  state.detail?.id == request.detail.id else { return .none }
            state.isRouteGuidanceLaunching = false
            state.routeGuidanceRequest = nil
            if cancelTrackingOnFailure, case .openedApp = result {
                // 성공한 외부 길안내만 측정 세션을 유지한다.
            } else if cancelTrackingOnFailure {
                routeGuidanceFlowService.cancelActiveMeasurement()
            }
            if case .openedApp = result {
                // 측정 후보는 외부 앱 전환 전에 저장했다.
            } else if practiceMeasurementStore.load()?.id == measurementID {
                practiceMeasurementStore.clear()
            }
            return result.userMessage.map { .send(.delegate(.showSnackbar($0))) } ?? .none
        case .routeGuidanceInstallFinished(let result, let requestID):
            guard requestID == state.routeGuidanceRequestID else { return .none }
            return result.userMessage.map { .send(.delegate(.showSnackbar($0))) } ?? .none
        case .activeMeasurementEnded:
            practiceMeasurementStore.clear()
        case .expandRequested:
            guard let placeID = state.detail?.id, state.presentation == .sheet else { return .none }
            state.presentation = .expandedDetail
            return reviewsReducer.reduce(&state.reviews, with: .start(placeID: placeID)).map(Action.reviews)
        case .collapseRequested:
            guard state.presentation == .expandedDetail else { return .none }; state.presentation = .sheet
        case .routeTimelineToggled:
            guard state.presentation == .expandedDetail else { return .none }; state.isRouteTimelineExpanded.toggle()
        case .reviews(let child):
            if case .delegate(let delegate) = child { return reduceReviewsDelegate(delegate, state: &state) }
            return reviewsReducer.reduce(&state.reviews, with: child).map(Action.reviews)
        case .delegate(let delegate): onDelegate(delegate)
        }
        return .none
    }
}

// MARK: - Child Delegate
private extension CourseDetailBottomSheetReducer {
    func startRouteGuidance(
        userLocation: RodiCoordinate?,
        hasLocationPermission: Bool,
        state: inout State
    ) -> Effect<Action> {
        guard hasLocationPermission else {
            return .send(.delegate(.showSnackbar("위치 권한을 허용한 뒤 다시 시도해주세요.")))
        }
        guard let detail = state.detail, let userLocation else {
            return .send(.delegate(.showSnackbar("현재 위치를 확인한 뒤 다시 시도해주세요.")))
        }

        switch routeGuidanceFlowService.launchOption {
        case .open(let app):
            return continueRouteGuidance(
                .init(app: app, detail: detail, userLocation: userLocation),
                state: &state
            )
        case .choose:
            state.routeGuidanceRequest = .init(app: .kakaoMap, detail: detail, userLocation: userLocation)
            state.routeGuidancePresentation = .chooseApp
            return .none
        case .install:
            state.routeGuidanceRequest = .init(app: .kakaoMap, detail: detail, userLocation: userLocation)
            state.routeGuidancePresentation = .installApp
            return .none
        }
    }

    func continueRouteGuidance(
        _ request: RouteGuidanceFlowRequest,
        state: inout State
    ) -> Effect<Action> {
        state.routeGuidanceRequest = request

        guard !routeGuidanceFlowService.hasActiveMeasurement else {
            state.routeGuidancePresentation = .activeMeasurement(
                courseName: routeGuidanceFlowService.activeMeasurementName ?? "현재 코스"
            )
            return .none
        }

        guard routeGuidanceFlowService.areLiveActivitiesEnabled else {
            state.routeGuidancePresentation = .liveActivityPermission
            return .none
        }

        state.routeGuidancePresentation = nil
        state.isRouteGuidanceLaunching = true
        state.routeGuidanceRequestID += 1
        let requestID = state.routeGuidanceRequestID
        let service = routeGuidanceFlowService
        return .run { send in
            await send(
                .routeGuidanceTrackingPrepared(
                    await service.prepareTracking(for: request),
                    request: request,
                    requestID: requestID
                )
            )
        }
        .cancelTask(id: BottomSheetEffectID.courseRouteGuidance)
    }

    func openRouteOnlyWithMessage(
        _ request: RouteGuidanceFlowRequest,
        message: String,
        state: inout State
    ) -> Effect<Action> {
        let openEffect = openRouteEffect(
            request: request,
            mode: .routeOnly,
            measurementID: UUID(),
            cancelTrackingOnFailure: false,
            initialSnackbarMessage: message,
            state: &state
        )
        return openEffect
    }

    func openRouteEffect(
        request: RouteGuidanceFlowRequest,
        mode: PracticeMeasurementMode,
        measurementID: UUID,
        cancelTrackingOnFailure: Bool,
        initialSnackbarMessage: String? = nil,
        state: inout State
    ) -> Effect<Action> {
        state.isRouteGuidanceLaunching = true
        state.routeGuidanceRequest = request
        state.routeGuidanceRequestID += 1
        let requestID = state.routeGuidanceRequestID
        let service = routeGuidanceFlowService

        return .run { send in
            if let initialSnackbarMessage {
                await send(.delegate(.showSnackbar(initialSnackbarMessage)))
            }
            await send(
                .routeGuidanceWillOpen(
                    request: request,
                    mode: mode,
                    measurementID: measurementID,
                    requestID: requestID
                )
            )
            let result = await service.open(request)
            await send(
                .routeGuidanceOpenFinished(
                    result,
                    request: request,
                    measurementID: measurementID,
                    cancelTrackingOnFailure: cancelTrackingOnFailure,
                    requestID: requestID
                )
            )
        }
        .cancelTask(id: BottomSheetEffectID.courseRouteGuidance)
    }

    func openInstallEffect(app: RouteGuidanceApp, requestID: Int) -> Effect<Action> {
        let service = routeGuidanceFlowService
        return .run { send in
            await send(.routeGuidanceInstallFinished(await service.openInstallPage(for: app), requestID: requestID))
        }
        .cancelTask(id: BottomSheetEffectID.courseRouteGuidance)
    }

    func finishRouteGuidance(_ message: String, state: inout State) -> Effect<Action> {
        state.routeGuidanceRequest = nil
        state.routeGuidancePresentation = nil
        state.isRouteGuidanceLaunching = false
        return .send(.delegate(.showSnackbar(message)))
    }

    func reduceReviewsDelegate(_ delegate: CourseReviewReducer.Delegate, state: inout State) -> Effect<Action> {
        switch delegate {
        case .writingRequested:
            guard let detail = state.detail else { return .none }
            return .send(.delegate(.reviewWritingRequested(.init(placeID: detail.id, placeName: detail.name))))
        case .editingRequested(let reviewID):
            return .send(.delegate(.reviewEditingRequested(reviewID)))
        case .requestAuthentication: return .send(.delegate(.requestAuthentication))
        case .showSnackbar(let message): return .send(.delegate(.showSnackbar(message)))
        }
    }
}

// MARK: - Effect
private extension CourseDetailBottomSheetReducer {
    func configureRoute(for item: RodiCourseItem, state: inout State) -> Effect<Action> {
        let points = item.routeOverlayPoints
        guard points.count >= 2 else { state.routeOverlay = nil; state.routeStatusMessage = "경로 좌표가 아직 준비되지 않았어요."; return .cancel(id: BottomSheetEffectID.routeLoading) }
        state.routeOverlay = .init(courseID: item.id, points: points, path: points.map(\.coordinate), isRoadRoute: false); state.isRouteLoading = true
        let directionsService = directionsService
        return .run { send in
            do { await send(.roadRouteLoaded(courseID: item.id, path: try await directionsService.fetchRoute(points: points))) }
            catch is CancellationError { }
            catch let error as KakaoDirectionsError { await send(.roadRouteFailed(courseID: item.id, message: error.fallbackMessage)) }
            catch { await send(.roadRouteFailed(courseID: item.id, message: "도로 경로를 불러오지 못해 대체 경로로 표시 중이에요.")) }
        }.cancelTask(id: BottomSheetEffectID.routeLoading)
    }
    func bookmarkEffect(placeID: Int, isBookmarked: Bool, previous: PlaceDetail) -> Effect<Action> {
        let repository = placeRepository
        return .run { send in do { if isBookmarked { try await repository.bookmark(placeID: placeID) } else { try await repository.unbookmark(placeID: placeID) }; await send(.bookmarkUpdated(placeID: placeID, isBookmarked: isBookmarked, source: "home")) } catch is CancellationError {} catch { await send(.bookmarkFailed(previousDetail: previous, message: "북마크를 \(isBookmarked ? "저장" : "해제")하지 못했어요.")) } }.cancelTask(id: BottomSheetEffectID.bookmarkUpdating)
    }
}
