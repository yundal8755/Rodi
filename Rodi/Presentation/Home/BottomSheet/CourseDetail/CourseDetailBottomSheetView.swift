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
                    Button("카카오맵으로 보기") { openRouteGuidance(.kakaoMap, detail: detail) }
                    Button("카카오내비로 안내") { openRouteGuidance(.kakaoNavi, detail: detail) }
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
            Button("카카오맵으로 보기") { openRouteGuidance(.kakaoMap, detail: detail) }
            Button("카카오내비로 안내") { openRouteGuidance(.kakaoNavi, detail: detail) }
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

    private func openRouteGuidance(_ app: RouteGuidanceApp, detail: PlaceDetail) {
        Task {
            let result = await RouteGuidanceService.shared.open(app, for: RodiCourseItem(placeDetail: detail), userLocation: userLocation)
            if case .openedApp = result {
                send(.externalRouteGuidanceOpened(placeID: detail.id))
            }
            if let message = result.userMessage { send(.delegate(.showSnackbar(message))) }
        }
    }
}
