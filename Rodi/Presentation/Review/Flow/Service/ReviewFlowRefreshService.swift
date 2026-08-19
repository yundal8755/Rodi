//
//  ReviewFlowRefreshService.swift
//  Rodi
//

import Foundation

protocol ReviewFlowRefreshServicing {
    func refresh(entrySource: ReviewFlowEntrySource, placeID: Int) async
}

struct ReviewFlowRefreshService: ReviewFlowRefreshServicing {
    private let practiceRepository: PracticeRepository
    private let reviewRepository: ReviewRepository

    init(practiceRepository: PracticeRepository, reviewRepository: ReviewRepository) {
        self.practiceRepository = practiceRepository
        self.reviewRepository = reviewRepository
    }

    func refresh(entrySource: ReviewFlowEntrySource, placeID: Int) async {
        switch entrySource {
        case .courseDetail:
            _ = try? await reviewRepository.fetchReviews(
                placeID: placeID,
                query: .init(level: .current)
            )
        case .home, .my:
            _ = try? await practiceRepository.fetchMyPractices(query: .init(size: 20))
        case .myPosts:
            _ = try? await reviewRepository.fetchMyReviews(query: .init(size: 10))
        }
    }
}
