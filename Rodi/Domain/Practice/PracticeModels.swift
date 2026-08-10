import Foundation

struct PracticeRegistration: Equatable {
    let practiceID: Int
}

struct PracticeVisit: Equatable {
    let visitCount: Int
    let isVerified: Bool
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
