import Foundation

final class ReviewRemoteDataSource {
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    func create(placeID: Int, submission: PlaceReviewSubmission) async throws(NetworkError) {
        let response = try await networkManager.request(
            ReviewAPI.create(placeID: placeID, request: .init(submission)),
            as: ServerResponse<ReviewCreateResponseDTO>.self
        )
        guard response.isSuccess, response.data != nil else {
            throw .apiError(code: response.code, message: response.message)
        }
    }
}
