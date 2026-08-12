import Foundation

struct ReviewDraft: Equatable {
    var isRecommended: Bool?
    var difficulty: ReviewDifficulty?
    var congestion: ReviewCongestion?
    var caution = ""
    var practiceMethod: ReviewPracticeMethod?
    var content = ""

    var canProceedToSecondPage: Bool {
        isRecommended != nil
            && difficulty != nil
            && congestion != nil
            && !caution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submission() -> PlaceReviewSubmission? {
        guard let isRecommended,
              let difficulty,
              let congestion,
              let practiceMethod
        else {
            return nil
        }

        return .init(
            isRecommended: isRecommended,
            difficulty: difficulty,
            congestion: congestion,
            practiceMethod: practiceMethod,
            content: content.normalizedOptionalText,
            caution: caution.normalizedOptionalText
        )
    }
}

extension String {
    var normalizedOptionalText: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
