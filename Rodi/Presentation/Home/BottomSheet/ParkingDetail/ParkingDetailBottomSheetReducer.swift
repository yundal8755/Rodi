//
//  ParkingDetailBottomSheetReducer.swift
//  Rodi
//

import Foundation

struct ParkingDetailBottomSheetReducer: Reducer {
    struct State {
        var detail: PlaceDetail?
        var isBookmarkUpdating = false
        var routeGuidancePresentation: RouteGuidanceFlowPresentation?
        var routeGuidanceRequest: RouteGuidanceFlowRequest?
        var routeGuidanceRequestID = 0
        var isRouteGuidanceLaunching = false
    }

    enum Action {
        case present(PlaceDetail, source: String)
        case dismiss
        case reset
        case toggleBookmark
        case bookmarkUpdated(placeID: Int, isBookmarked: Bool, source: String)
        case bookmarkFailed(previousDetail: PlaceDetail, message: String)
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
        case delegate(Delegate)
    }

    enum Delegate {
        case dismissed
        case focusMap(RodiCoordinate)
        case requestAuthentication
        case showSnackbar(String)
    }

    private let placeRepository: PlaceRepository
    private let practiceMeasurementStore: PracticeMeasurementStoring
    private let practiceTrackingService: PracticeTrackingService
    private let hasActiveSession: () -> Bool
    private let routeGuidanceFlowService: RouteGuidanceFlowService
    private let onDelegate: (Delegate) -> Void

    init(placeRepository: PlaceRepository,
         memberRepository: MemberRepository,
         practiceMeasurementStore: PracticeMeasurementStoring,
         practiceTrackingService: PracticeTrackingService,
         hasActiveSession: @escaping () -> Bool,
         onDelegate: @escaping (Delegate) -> Void = { _ in }) {
        self.placeRepository = placeRepository
        self.practiceMeasurementStore = practiceMeasurementStore
        self.practiceTrackingService = practiceTrackingService
        self.hasActiveSession = hasActiveSession
        routeGuidanceFlowService = .init(
            memberRepository: memberRepository,
            practiceTrackingService: practiceTrackingService
        )
        self.onDelegate = onDelegate
    }
}


// MARK: - Core Logics
extension ParkingDetailBottomSheetReducer {

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .present(let detail, _):
            guard detail.type == .parking else { return .none }
            state.detail = detail
            state.isBookmarkUpdating = false
            RodiAnalytics.track(.placeDetailOpened(source: "home", placeType: detail.type.rawValue))
            return .send(.delegate(.focusMap(RodiCoordinate(latitude: detail.latitude, longitude: detail.longitude))))

        case .dismiss:
            guard state.detail != nil else { return .none }
            state = State()
            return .run { send in
                await send(.routeGuidanceDismissed)
                await send(.delegate(.dismissed))
            }

        case .reset:
            state = .init()
            return .send(.routeGuidanceDismissed)

        case .toggleBookmark:
            guard let detail = state.detail, !state.isBookmarkUpdating else { return .none }
            guard hasActiveSession() else { return .send(.delegate(.requestAuthentication)) }
            let previousDetail = detail
            let isBookmarked = !detail.isBookmarked
            state.detail = detail.updatingBookmark(isBookmarked: isBookmarked)
            state.isBookmarkUpdating = true
            return updateBookmarkEffect(placeID: detail.id, isBookmarked: isBookmarked, previousDetail: previousDetail)

        case .bookmarkUpdated(let id, let isBookmarked, let source):
            guard state.detail?.id == id else { return .none }
            state.detail = state.detail?.updatingBookmark(isBookmarked: isBookmarked)
            state.isBookmarkUpdating = false
            RodiAnalytics.track(.bookmarkUpdated(isBookmarked: isBookmarked, source: source, placeType: PlaceType.parking.rawValue))
            return .none

        case .bookmarkFailed(let previousDetail, let message):
            guard state.detail?.id == previousDetail.id else { return .none }
            state.detail = previousDetail
            state.isBookmarkUpdating = false
            return .send(.delegate(.showSnackbar(message)))

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
            return openInstallEffect(app: app, requestID: state.routeGuidanceRequestID)

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
            return .cancel(id: BottomSheetEffectID.parkingRouteGuidance)

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
            practiceMeasurementStore.save(.init(
                id: measurementID,
                placeID: request.detail.id,
                placeName: request.detail.name,
                placeType: .parking,
                mode: mode,
                externalHandoffAt: .now,
                status: mode == .gpsTracking ? .tracking : .awaitingReturn
            ))
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

        case .delegate(let delegate):
            onDelegate(delegate)
        }
        return .none
    }

    private func updateBookmarkEffect(placeID: Int, isBookmarked: Bool, previousDetail: PlaceDetail) -> Effect<Action> {
        let repository = placeRepository
        return .run { send in
            do {
                if isBookmarked { try await repository.bookmark(placeID: placeID) }
                else { try await repository.unbookmark(placeID: placeID) }
                await send(.bookmarkUpdated(placeID: placeID, isBookmarked: isBookmarked, source: "home"))
            } catch is CancellationError {
                return
            } catch {
                if requiresAuthentication(error) { await send(.delegate(.requestAuthentication)) }
                else { await send(.bookmarkFailed(previousDetail: previousDetail, message: "북마크를 \(isBookmarked ? "저장" : "해제")하지 못했어요.")) }
            }
        }
        .cancelTask(id: BottomSheetEffectID.bookmarkUpdating)
    }

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
                courseName: routeGuidanceFlowService.activeMeasurementName ?? "현재 연습 장소"
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
        .cancelTask(id: BottomSheetEffectID.parkingRouteGuidance)
    }

    func openRouteOnlyWithMessage(
        _ request: RouteGuidanceFlowRequest,
        message: String,
        state: inout State
    ) -> Effect<Action> {
        openRouteEffect(
            request: request,
            mode: .routeOnly,
            measurementID: UUID(),
            cancelTrackingOnFailure: false,
            initialSnackbarMessage: message,
            state: &state
        )
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
        .cancelTask(id: BottomSheetEffectID.parkingRouteGuidance)
    }

    func openInstallEffect(app: RouteGuidanceApp, requestID: Int) -> Effect<Action> {
        let service = routeGuidanceFlowService
        return .run { send in
            await send(.routeGuidanceInstallFinished(await service.openInstallPage(for: app), requestID: requestID))
        }
        .cancelTask(id: BottomSheetEffectID.parkingRouteGuidance)
    }

    func finishRouteGuidance(_ message: String, state: inout State) -> Effect<Action> {
        state.routeGuidanceRequest = nil
        state.routeGuidancePresentation = nil
        state.isRouteGuidanceLaunching = false
        return .send(.delegate(.showSnackbar(message)))
    }

    private func requiresAuthentication(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkError else { return false }
        return switch networkError {
        case .refreshFailGoRoot, .httpStatusCode(401): true
        case .apiError(let code, _, _): code.hasPrefix("AUTH_401") || code == "AUTH_400_1"
        default: false
        }
    }
}
