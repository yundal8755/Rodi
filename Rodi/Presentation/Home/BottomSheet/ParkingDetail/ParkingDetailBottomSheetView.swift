import SwiftUI

struct ParkingDetailBottomSheetView: View {
    let state: ParkingDetailBottomSheetReducer.State
    let send: (ParkingDetailBottomSheetReducer.Action) -> Void
    let userLocation: RodiCoordinate?
    let hasLocationPermission: Bool
    let requestLocationPermission: () -> Void

    var body: some View {
        Group {
            if let detail = state.detail {
                ParkingSelectedDetailPanel(
                    detail: detail,
                    isBookmarkUpdating: state.isBookmarkUpdating,
                    isRouteLoading: state.isRouteGuidanceLaunching,
                    isRouteGuidanceEnabled: true,
                    closeAction: { send(.dismiss) },
                    bookmarkAction: { send(.toggleBookmark) },
                    routeGuidanceAction: requestRouteGuidance
                )
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func requestRouteGuidance() {
        guard hasLocationPermission else {
            requestLocationPermission()
            return
        }
        send(.routeGuidanceTapped(userLocation: userLocation, hasLocationPermission: hasLocationPermission))
    }
}
