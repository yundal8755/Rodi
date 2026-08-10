import Alamofire
import Foundation

enum ReviewAPI: TargetType {
    case create(placeID: Int, request: ReviewRequestDTO)

    var method: HTTPMethod { .post }
    var path: String {
        switch self {
        case .create(let placeID, _): "/api/v1/places/\(placeID)/reviews"
        }
    }
    var optionalHeaders: HTTPHeaders? { nil }
    var parameters: Parameters? { nil }
    var body: Data? {
        switch self {
        case .create(_, let request): requestToBody(request)
        }
    }
    var encodingType: EncodingType { .json }
    var requiresAuthentication: Bool { true }
}
