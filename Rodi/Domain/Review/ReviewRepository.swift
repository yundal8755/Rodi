import Foundation

protocol ReviewRepository {
    func create(placeID: Int, submission: PlaceReviewSubmission) async throws(NetworkError)
}
