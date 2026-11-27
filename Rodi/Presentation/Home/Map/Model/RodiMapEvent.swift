//
//  RodiMapEvent.swift
//  Rodi
//

import Foundation

enum RodiMapEvent {
    case ready
    case userCameraGesture
    case markerTap(String)
    case routePointTap(Int)
    case viewportChanged(
        center: RodiCoordinate,
        zoomLevel: Int,
        viewport: PlaceViewport,
        isUserInitiated: Bool
    )
    case cameraMoveFinished(requestID: Int, viewport: PlaceViewport?)
    case failed(String)
}
