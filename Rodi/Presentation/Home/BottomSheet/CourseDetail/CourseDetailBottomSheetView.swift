//
//  CourseDetailBottomSheetView.swift
//  Rodi
//

import SwiftUI

struct CourseDetailBottomSheetView: View {
    enum RenderingMode {
        case sheet
        case expanded
    }

    let state: CourseDetailBottomSheetReducer.State
    let send: (CourseDetailBottomSheetReducer.Action) -> Void
    let userLocation: RodiCoordinate?
    let hasLocationPermission: Bool
    let requestLocationPermission: () -> Void
    let renderingMode: RenderingMode
    let expandedBackAction: () -> Void

    @State private var isGuidanceDialogPresented = false

    init(
        state: CourseDetailBottomSheetReducer.State,
        send: @escaping (CourseDetailBottomSheetReducer.Action) -> Void,
        userLocation: RodiCoordinate?,
        hasLocationPermission: Bool,
        requestLocationPermission: @escaping () -> Void,
        renderingMode: RenderingMode = .sheet,
        expandedBackAction: @escaping () -> Void = {}
    ) {
        self.state = state
        self.send = send
        self.userLocation = userLocation
        self.hasLocationPermission = hasLocationPermission
        self.requestLocationPermission = requestLocationPermission
        self.renderingMode = renderingMode
        self.expandedBackAction = expandedBackAction
    }

    var body: some View {
        if let detail = state.detail {
            if renderingMode == .sheet {
                sheet(detail: detail)
            } else {
                CourseDetailExpandedPage(
                    state: state,
                    send: send,
                    bookmarkAction: { send(.toggleBookmark) },
                    routeGuidanceAction: requestRouteGuidance,
                    expandedBackAction: expandedBackAction
                )
                .confirmationDialog("경로 안내 앱 선택", isPresented: $isGuidanceDialogPresented, titleVisibility: .visible) {
                    Button("카카오맵으로 보기") { startRouteGuidance(.kakaoMap, detail: detail) }
                    Button("카카오내비로 안내") { startRouteGuidance(.kakaoNavi, detail: detail) }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("출발지, 경유지, 도착지를 함께 전달해요.")
                }
            }
        }
    }
}


// MARK: - Layout
extension CourseDetailBottomSheetView {

    private func sheet(detail: PlaceDetail) -> some View {
        VStack(spacing: 0) {
            CourseSelectedDetailPanel(
                detail: detail,
                isBookmarkUpdating: state.isBookmarkUpdating,
                isRouteLoading: state.isRouteLoading,
                isRouteGuidanceEnabled: detail.course?.waypoints.count ?? 0 >= 2,
                closeAction: { send(.dismiss) },
                bookmarkAction: { send(.toggleBookmark) },
                routeGuidanceAction: requestRouteGuidance
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .confirmationDialog("경로 안내 앱 선택", isPresented: $isGuidanceDialogPresented, titleVisibility: .visible) {
            Button("카카오맵으로 보기") { startRouteGuidance(.kakaoMap, detail: detail) }
            Button("카카오내비로 안내") { startRouteGuidance(.kakaoNavi, detail: detail) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("출발지, 경유지, 도착지를 함께 전달해요.")
        }
    }

    private func requestRouteGuidance() {
        guard hasLocationPermission else {
            requestLocationPermission()
            return
        }
        guard userLocation != nil else {
            send(.delegate(.showSnackbar("현재 위치를 확인한 뒤 다시 시도해주세요.")))
            return
        }
        isGuidanceDialogPresented = true
    }

    private func startRouteGuidance(_ app: RouteGuidanceApp, detail: PlaceDetail) {
        Task {
            let course = RodiCourseItem(placeDetail: detail)
            let routePath = await practiceRoutePath(for: course)
            let startResult = PracticeTrackingService.shared.start(course: course, routePath: routePath)

            switch startResult {
            case .started:
                await openRouteGuidance(app, detail: detail, cancelTrackingOnFailure: true)

            case .authorizationRequested:
                send(.delegate(.showSnackbar("위치 권한을 허용한 뒤 다시 연습하러 가기를 눌러주세요.")))

            case .reducedAccuracyRequested:
                await openRouteGuidance(app, detail: detail)
                send(.delegate(.showSnackbar("정확한 위치를 허용하면 다음 길안내부터 연습 기록을 시작할 수 있어요.")))

            case .unavailable(let message):
                await openRouteGuidance(app, detail: detail)
                send(.delegate(.showSnackbar(message)))
            }
        }
    }

    private func practiceRoutePath(for course: RodiCourseItem) async -> [RodiCoordinate] {
        if let roadPath = try? await KakaoDirectionsService().fetchRoute(points: course.routeOverlayPoints), roadPath.count >= 2 {
            return roadPath
        }
        return course.routeOverlayPoints.map(\.coordinate)
    }

    private func openRouteGuidance(
        _ app: RouteGuidanceApp,
        detail: PlaceDetail,
        cancelTrackingOnFailure: Bool = false
    ) async {
        let result = await RouteGuidanceService.shared.open(
            app,
            for: RodiCourseItem(placeDetail: detail),
            userLocation: userLocation
        )
        if cancelTrackingOnFailure, case .openedApp = result {
            // The tracking session belongs to the successfully opened external guidance flow.
        } else if cancelTrackingOnFailure {
            PracticeTrackingService.shared.cancel()
        }
        if case .openedApp = result {
            send(.externalRouteGuidanceOpened(placeID: detail.id))
        }
        if let message = result.userMessage {
            send(.delegate(.showSnackbar(message)))
        }
    }
}
