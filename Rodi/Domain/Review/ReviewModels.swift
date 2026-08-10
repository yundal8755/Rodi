import Foundation

enum ReviewDifficulty: String, CaseIterable, Equatable, Hashable {
    case veryEasy = "VERY_EASY"
    case easy = "EASY"
    case normal = "NORMAL"
    case hard = "HARD"
    case veryHard = "VERY_HARD"

    var title: String {
        switch self {
        case .veryEasy: "매우 쉬움"
        case .easy: "쉬움"
        case .normal: "보통"
        case .hard: "어려움"
        case .veryHard: "매우 어려움"
        }
    }
}

enum ReviewCongestion: String, CaseIterable, Equatable, Hashable {
    case quiet = "QUIET"
    case normal = "NORMAL"
    case crowded = "CROWDED"

    var title: String {
        switch self {
        case .quiet: "한산해요"
        case .normal: "보통이에요"
        case .crowded: "복잡해요"
        }
    }
}

enum ReviewPracticeMethod: String, CaseIterable, Equatable, Hashable {
    case solo = "SOLO"
    case accompanied = "ACCOMPANIED"

    var title: String {
        switch self {
        case .solo: "혼자 연습"
        case .accompanied: "동승자와 연습"
        }
    }
}

struct PlaceReviewSubmission: Equatable {
    let isRecommended: Bool
    let difficulty: ReviewDifficulty
    let congestion: ReviewCongestion
    let practiceMethod: ReviewPracticeMethod
    let content: String?
    let caution: String?
}
