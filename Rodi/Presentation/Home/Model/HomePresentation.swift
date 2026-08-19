import Foundation

/// MainTab이 Home에 전달하는 외부 화면 입력과 상위 flow callback입니다.
struct HomePresentation {
    let isHomeTabSelected: Bool
    let listPresentationRequestID: Int
    let placeSelectionRequest: HomePlaceSelectionRequest?
    let reviewFlowFinishedRequestID: Int
    let courseDetailReviewPresentation: CourseDetailReviewPresentation
    let requestAuthentication: () -> Void
    let reviewTestRequested: () -> Void
    let bottomTabBarVisibilityChanged: (Bool) -> Void
    let placeSelectionHandled: (Int) -> Void
    let reviewWritingRequested: (ReviewWriteRequest) -> Void
    let reviewEditingRequested: (Int) -> Void
}
