import Alamofire
import Foundation

enum PracticeAPI: TargetType {
    case register(placeID: Int)
    case recordVisit(practiceID: Int, request: PracticeVisitRequestDTO)
    case skipReasonForm
    case submitSkipReason(practiceID: Int, request: PracticeSkipReasonRequestDTO)

    var method: HTTPMethod {
        switch self {
        case .skipReasonForm:
            .get
        case .register, .recordVisit, .submitSkipReason:
            .post
        }
    }

    var path: String {
        switch self {
        case .register(let placeID): "/api/v1/places/\(placeID)/practices"
        case .recordVisit(let practiceID, _): "/api/v1/practices/\(practiceID)/visits"
        case .skipReasonForm: "/api/v1/practices/skip-reason-form"
        case .submitSkipReason(let practiceID, _): "/api/v1/practices/\(practiceID)/skip-reason"
        }
    }

    var optionalHeaders: HTTPHeaders? { nil }
    var parameters: Parameters? { nil }

    var body: Data? {
        switch self {
        case .register:
            nil
        case .recordVisit(_, let request):
            requestToBody(request)
        case .skipReasonForm:
            nil
        case .submitSkipReason(_, let request):
            requestToBody(request)
        }
    }

    var encodingType: EncodingType { .json }
    var requiresAuthentication: Bool { true }
}
