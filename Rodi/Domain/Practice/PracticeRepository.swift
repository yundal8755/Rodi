import Foundation

protocol PracticeRepository {
    func register(placeID: Int) async throws(NetworkError) -> PracticeRegistration
    func recordVisit(practiceID: Int, certifiedDistanceMeters: Int?) async throws(NetworkError) -> PracticeVisit
    func fetchSkipReasonForm() async throws(NetworkError) -> PracticeSkipReasonForm
    func submitSkipReason(
        practiceID: Int,
        reasonCode: String,
        detail: String?
    ) async throws(NetworkError)
}
