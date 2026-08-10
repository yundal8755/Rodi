import Foundation

final class PracticeRepositoryImpl: PracticeRepository {
    private let remoteDataSource: PracticeRemoteDataSource

    init(remoteDataSource: PracticeRemoteDataSource) {
        self.remoteDataSource = remoteDataSource
    }

    func register(placeID: Int) async throws(NetworkError) -> PracticeRegistration {
        let response = try await remoteDataSource.register(placeID: placeID)
        return .init(practiceID: response.practiceID)
    }

    func recordVisit(practiceID: Int, certifiedDistanceMeters: Int?) async throws(NetworkError) -> PracticeVisit {
        let response = try await remoteDataSource.recordVisit(
            practiceID: practiceID,
            certifiedDistanceMeters: certifiedDistanceMeters
        )
        return .init(visitCount: response.visitCount, isVerified: response.isVerified)
    }

    func fetchSkipReasonForm() async throws(NetworkError) -> PracticeSkipReasonForm {
        let response = try await remoteDataSource.fetchSkipReasonForm()
        return .init(
            options: response.options
                .sorted { $0.order < $1.order }
                .map(PracticeSkipReasonOption.init)
        )
    }

    func submitSkipReason(
        practiceID: Int,
        reasonCode: String,
        detail: String?
    ) async throws(NetworkError) {
        try await remoteDataSource.submitSkipReason(
            practiceID: practiceID,
            reasonCode: reasonCode,
            detail: detail
        )
    }
}

private extension PracticeSkipReasonOption {

    init(_ response: PracticeSkipReasonOptionDTO) {
        self.init(
            code: response.code,
            label: response.label,
            order: response.order,
            requiresTextInput: response.requiresTextInput,
            textInputPlaceholder: response.textInputPlaceholder,
            textInputMaxLength: response.textInputMaxLength
        )
    }
}
