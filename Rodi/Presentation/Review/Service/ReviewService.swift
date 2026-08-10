import Foundation

struct ReviewService {
    private let placeRepository: PlaceRepository
    private let practiceRepository: PracticeRepository
    private let reviewRepository: ReviewRepository

    init(
        placeRepository: PlaceRepository,
        practiceRepository: PracticeRepository,
        reviewRepository: ReviewRepository
    ) {
        self.placeRepository = placeRepository
        self.practiceRepository = practiceRepository
        self.reviewRepository = reviewRepository
    }

    func prepareTarget(placeID: Int) async throws(ReviewTargetPreparationError) -> ReviewTarget {
        let place: PlaceDetail
        do {
            place = try await placeRepository.fetchPlaceDetail(id: placeID)
        } catch let error {
            throw ReviewTargetPreparationError.placeDetail(placeID: placeID, error: error)
        }

        do {
            let practice = try await practiceRepository.register(placeID: place.id)
            return ReviewTarget(
                placeID: place.id,
                practiceID: practice.practiceID,
                placeName: place.name
            )
        } catch let error {
            throw ReviewTargetPreparationError.practiceRegistration(placeID: place.id, error: error)
        }
    }

    func recordVisit(practiceID: Int) async throws(NetworkError) {
        _ = try await practiceRepository.recordVisit(
            practiceID: practiceID,
            certifiedDistanceMeters: nil
        )
    }

    func fetchSkipReasonForm() async throws(NetworkError) -> PracticeSkipReasonForm {
        try await practiceRepository.fetchSkipReasonForm()
    }

    func submitSkipReason(
        practiceID: Int,
        reasonCode: String,
        detail: String?
    ) async throws(NetworkError) {
        try await practiceRepository.submitSkipReason(
            practiceID: practiceID,
            reasonCode: reasonCode,
            detail: detail
        )
    }

    func submitReview(
        placeID: Int,
        submission: PlaceReviewSubmission
    ) async throws(NetworkError) {
        try await reviewRepository.create(placeID: placeID, submission: submission)
    }
}
