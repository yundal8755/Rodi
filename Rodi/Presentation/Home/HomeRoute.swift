import Foundation

enum HomeRoute: Route {
    case courseDetail(placeID: Int)

    var id: String {
        switch self {
        case .courseDetail(let placeID):
            "courseDetail.\(placeID)"
        }
    }
}
