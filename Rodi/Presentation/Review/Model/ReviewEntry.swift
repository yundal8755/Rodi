import Foundation

enum ReviewFlowRoute: Equatable {
    case hidden
    case prompt
    case writing
    case skipReason
}

struct ReviewTarget: Equatable {
    let placeID: Int
    let practiceID: Int?
    let placeName: String
}

struct ReviewWriteRequest: Equatable {
    let placeID: Int
    let placeName: String
}

enum ReviewFlowEntrySource: Equatable {
    case home
    case my
}

struct ReviewFlowRequest: Equatable {
    let writeRequest: ReviewWriteRequest
    let entrySource: ReviewFlowEntrySource
}

/// Review feature effects keep a user-facing failure message without exposing
/// transport types to presentation state.
enum ReviewRequestResult<Value> {
    case success(Value)
    case failure(String)
}

enum ReviewTargetPreparationError: Error {
    case placeDetail(placeID: Int, error: NetworkError)
    case practiceRegistration(placeID: Int, error: NetworkError)

    var endpoint: String {
        switch self {
        case .placeDetail(let placeID, _):
            "GET /api/v1/places/\(placeID)"
        case .practiceRegistration(let placeID, _):
            "POST /api/v1/places/\(placeID)/practices"
        }
    }

    var underlyingError: NetworkError {
        switch self {
        case .placeDetail(_, let error), .practiceRegistration(_, let error):
            error
        }
    }
}
