import Foundation

final class ReviewRepositoryImpl: ReviewRepository {
    private let remoteDataSource: ReviewRemoteDataSource

    init(remoteDataSource: ReviewRemoteDataSource) {
        self.remoteDataSource = remoteDataSource
    }

    func create(placeID: Int, submission: PlaceReviewSubmission) async throws(NetworkError) {
        try await remoteDataSource.create(placeID: placeID, submission: submission)
    }
}
