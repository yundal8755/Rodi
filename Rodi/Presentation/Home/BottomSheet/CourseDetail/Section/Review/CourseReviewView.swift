import SwiftUI

struct CourseReviewView: View {
    let state: CourseReviewReducer.State
    @Binding var activeDropdown: CourseReviewDropdown?
    let send: (CourseReviewReducer.Action) -> Void

    var body: some View {
        switch state.route {
        case .preview:
            CourseReviewSection(
                summary: summaryState.value,
                page: state.pages[state.selectedLevel],
                isSummaryLoading: summaryState.isLoading,
                summaryErrorMessage: summaryState.errorMessage,
                selectedLevel: state.selectedLevel,
                showsAllReviewsButton: (summaryState.value?.totalReviewCount ?? 0) > 0,
                activeDropdown: $activeDropdown,
                onSelectLevel: { send(.levelSelected($0)) },
                onShowAllReviews: { send(.allReviewsTapped) },
                onRetry: { send(.retryTapped) },
                onWriteReview: { send(.writingTapped) }
            )

        case .allReviews:
            CourseReviewAllContent(
                summary: summaryState.value,
                page: state.pages[state.selectedLevel],
                isSummaryLoading: summaryState.isLoading,
                summaryErrorMessage: summaryState.errorMessage,
                selectedLevel: state.selectedLevel,
                activeDropdown: $activeDropdown,
                onLoadMore: { send(.nextPageRequested) },
                onRetry: { send(.retryTapped) }
            )

        case .report:
            EmptyView()
        }
    }
}

private extension CourseReviewView {
    var summaryState: CourseReviewReducer.SummaryState {
        state.summaries[state.selectedLevel] ?? .init()
    }
}
