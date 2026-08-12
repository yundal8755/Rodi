//
//  MemberRepositoryImpl.swift
//  Rodi
//

import Foundation

// Member remote DTO를 앱의 회원 계약으로 변환한다.

final class MemberRepositoryImpl: MemberRepository {
    private let remoteDataSource: MemberRemoteDataSource

    init(remoteDataSource: MemberRemoteDataSource) {
        self.remoteDataSource = remoteDataSource
    }

    func fetchMyProfile() async throws(NetworkError) -> MemberProfile {
        let profile = try await remoteDataSource.fetchProfile()

        #if DEBUG
        let profileLog: String
        let drivingGoal = profile.drivingGoal ?? "nil"
        profileLog = "nickname=\(profile.nickname), level=\(profile.level), recommendationTags=\(profile.recommendationTags), drivingGoal=\(drivingGoal), savedPlaceCount=\(profile.savedPlaceCount)"
        RodiLogger.debug(
            "GET /api/v1/members/me response: data={\(profileLog)}"
        )
        #endif

        return try profile.toDomain()
    }

    func withdraw() async throws(NetworkError) {
        try await remoteDataSource.withdraw()
    }

    func block(memberID: Int) async throws(NetworkError) {
        try await remoteDataSource.block(memberID: memberID)
    }

    func fetchBlockedMembers(query: BlockedMemberQuery) async throws(NetworkError) -> BlockedMemberPage {
        try page(from: await remoteDataSource.fetchBlockedMembers(query: query))
    }

    func unblock(memberID: Int) async throws(NetworkError) {
        try await remoteDataSource.unblock(memberID: memberID)
    }

    func updateDrivingGoal(_ drivingGoal: String) async throws(NetworkError) {
        try await remoteDataSource.updateDrivingGoal(.init(drivingGoal: drivingGoal))
    }

    func updatePlaceFilterTags(_ tags: [PlacePracticeType]) async throws(NetworkError) {
        try await remoteDataSource.updateFilterTags(.init(tags))
    }

    func submitOnboarding(_ submission: MemberOnboardingSubmission) async throws(NetworkError) {
        try await remoteDataSource.submitOnboarding(.init(submission))
    }
}

// MARK: - Mapper
private extension MemberRepositoryImpl {

    func page(from dto: BlockedMemberCursorPageResponseDTO) throws(NetworkError) -> BlockedMemberPage {
        .init(
            items: try dto.items.map(blockedMember(from:)),
            hasNext: dto.hasNext,
            nextCursor: dto.nextCursor,
            totalCount: try dto.totalCount.map(int(from:))
        )
    }

    func blockedMember(from dto: BlockedMemberItemResponseDTO) throws(NetworkError) -> BlockedMember {
        guard let blockedAt = Self.date(from: dto.blockedAt) else {
            throw .decodingFail
        }

        return .init(
            id: try int(from: dto.memberId),
            nickname: dto.nickname,
            blockedAt: blockedAt
        )
    }

    func int(from value: Int64) throws(NetworkError) -> Int {
        guard let value = Int(exactly: value) else {
            throw .decodingFail
        }
        return value
    }

    static let iso8601DateFormatter = ISO8601DateFormatter()

    static let fractionalISO8601DateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        fractionalISO8601DateFormatter.date(from: value)
            ?? iso8601DateFormatter.date(from: value)
    }
}
