import Foundation

struct PracticeRegistration: Equatable {
    let practiceID: Int
}

struct PracticeVisit: Equatable {
    let visitCount: Int
    let addedCertifiedDistanceMeters: Int
    let requiredDistanceMeters: Int
    let isCertifiedNow: Bool
    let totalDistanceKm: Double
    let levelUp: Bool
    let newLevel: MemberProfile.Level?
}

enum MyPracticeStatus: String, Equatable {
    case planned = "PLANNED"
    case visited = "VISITED"
    case notVisited = "NOT_VISITED"
}

struct MyPracticeItem: Equatable, Identifiable {
    let id: Int
    let placeID: Int
    let placeName: String
    let practiceTypes: [String]
    let status: MyPracticeStatus
    let visitCount: Int
    let lastActivityAt: Date?
    let hasReview: Bool
}

struct MyPracticePage: Equatable {
    let items: [MyPracticeItem]
    let hasNext: Bool
    let nextCursor: String?
    let totalCount: Int?
}

struct MyPracticeQuery: Equatable {
    let size: Int
    let cursor: String?

    init(size: Int = 20, cursor: String? = nil) {
        self.size = size
        self.cursor = cursor
    }
}

struct PracticeSkipReasonForm: Equatable {
    let options: [PracticeSkipReasonOption]
}

struct PracticeSkipReasonOption: Equatable, Identifiable {
    let code: String
    let label: String
    let order: Int
    let requiresTextInput: Bool
    let textInputPlaceholder: String?
    let textInputMaxLength: Int?

    var id: String { code }
}
