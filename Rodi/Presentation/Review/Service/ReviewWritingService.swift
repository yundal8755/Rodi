import Foundation

protocol ReviewWritingServicing {
    func submitReview(placeID: Int, submission: PlaceReviewSubmission) async throws
}

struct ReviewWritingService: ReviewWritingServicing {
    private let reviewRepository: ReviewRepository

    init(reviewRepository: ReviewRepository) {
        self.reviewRepository = reviewRepository
    }

    func submitReview(placeID: Int, submission: PlaceReviewSubmission) async throws {
        try await reviewRepository.create(placeID: placeID, submission: submission)
    }
}
