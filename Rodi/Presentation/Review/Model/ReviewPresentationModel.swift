import Foundation

enum ReviewPresentation: Equatable {
    case hidden
    case preparing
    case prompt
    case formPage1
    case formPage2
    case skipReasonForm
    case discardConfirmation
    case completion
    case skipReasonCompletion
}

struct ReviewTarget: Equatable {
    let placeID: Int
    let practiceID: Int
    let placeName: String
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

enum ReviewTargetPreparationResult {
    case success(ReviewTarget)
    case failure(String)
}

enum ReviewVisitResult {
    case success
    case failure(String)
}

enum ReviewSubmissionResult {
    case success
    case failure(String)
}

enum ReviewSkipReasonFormState: Equatable {
    case idle
    case loading
    case loaded(PracticeSkipReasonForm)
    case failed
}

enum ReviewSkipReasonFormResult {
    case success(PracticeSkipReasonForm)
    case failure(String)
}

enum ReviewSkipReasonSubmissionResult {
    case success
    case failure(String)
}
