import Alamofire
import Foundation

enum ReviewAPI: TargetType {
    case create(placeID: Int, request: ReviewRequestDTO)
    case summary(placeID: Int, level: ReviewLevelFilter)
    case list(placeID: Int, query: PlaceReviewQuery)
    case reportForm
    case report(reviewID: Int, request: ReviewReportRequestDTO)

    var method: HTTPMethod {
        switch self {
        case .create, .report: .post
        case .summary, .list, .reportForm: .get
        }
    }

    var path: String {
        switch self {
        case .create(let placeID, _): "/api/v1/places/\(placeID)/reviews"
        case .summary(let placeID, _): "/api/v1/places/\(placeID)/reviews/summary"
        case .list(let placeID, _): "/api/v1/places/\(placeID)/reviews"
        case .reportForm: "/api/v1/reviews/report-form"
        case .report(let reviewID, _): "/api/v1/reviews/\(reviewID)/report"
        }
    }
    var optionalHeaders: HTTPHeaders? { nil }

    var parameters: Parameters? {
        switch self {
        case .create:
            return nil

        case .summary(_, let level):
            guard let level = level.queryValue else { return nil }
            return ["level": level]

        case .list(_, let query):
            var parameters: Parameters = ["size": query.size]
            if let level = query.level.queryValue {
                parameters["level"] = level
            }
            if let cursor = query.cursor, !cursor.isEmpty {
                parameters["cursor"] = cursor
            }
            return parameters

        case .reportForm, .report:
            return nil
        }
    }

    var body: Data? {
        switch self {
        case .create(_, let request): requestToBody(request)
        case .report(_, let request): requestToBody(request)
        case .summary, .list, .reportForm: nil
        }
    }

    var encodingType: EncodingType {
        switch self {
        case .create, .report: .json
        case .summary, .list, .reportForm: .url
        }
    }

    var requiresAuthentication: Bool { true }
}
